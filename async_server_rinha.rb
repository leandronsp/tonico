# frozen_string_literal: true

require 'socket'
require 'pg'
require 'json'
require 'byebug'
require 'connection_pool'

require_relative 'app/request'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

class InvalidDataError < StandardError; end
class InvalidLimitAmountError < StandardError; end
class NotFoundError < StandardError; end

VALIDATION_ERRORS = [
  PG::InvalidTextRepresentation,
  PG::StringDataRightTruncation,
  InvalidDataError,
  InvalidLimitAmountError
].freeze

def pool
  @pool ||= ConnectionPool.new(size: 10, timeout: 300) do 
    config = {
      host: (ENV['DATABASE_HOST'] || 'localhost'),
      user: 'postgres',
      password: 'postgres', 
      dbname: 'postgres'
    }

    PG::Connection.connect_start(config)
  end
end

@readable = {}
@writable = {}
@fibers = []

db = Fiber.new do |sql, params|
  loop do 
    conn = pool.checkout 
    pg_socket = IO.for_fd(conn.socket)

    poll_status = PG::PGRES_POLLING_WRITING

    until poll_status == PG::PGRES_POLLING_OK || poll_status == PG::PGRES_POLLING_FAILED
      case poll_status
      in PG::PGRES_POLLING_READING
        @readable[pg_socket] = Fiber.current
      in PG::PGRES_POLLING_WRITING
        @writable[pg_socket] = Fiber.current
      end

      Fiber.yield

      poll_status = conn.connect_poll
    end

    conn.send_query_params(sql, params)

    loop do 
      while conn.consume_input
        @readable[pg_socket] = Fiber.current
        Fiber.yield
      end

      result = conn.get_result
      break unless result

      Fiber.yield(result)
    end
  end
end

handler = Fiber.new do |client|
  loop do 
    status = 200
    body = {}
    result = {}
    request, params = Request.parse(client)

    begin
      case request
      in "GET /clientes/:id/extrato"
        sql_select_account = <<~SQL
          SELECT 
            balances.amount AS balance, 
            accounts.limit_amount AS limit_amount
          FROM accounts 
          JOIN balances ON balances.account_id = accounts.id
          WHERE accounts.id = $1
        SQL

        db_result = nil

        until db_result
          db_result = db.resume(sql_select_account, [params['id']])
        end

        raise NotFoundError unless db_result
        account = db_result.to_a.first

        result["saldo"] = {  
          "total": account['balance'].to_i,
          "data_extrato": Time.now.strftime("%Y-%m-%d"),
          "limite": account['limit_amount'].to_i
        }

        sql_ten_transactions = <<~SQL
          SELECT amount, transaction_type, description, TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US') AS date
          FROM transactions
          WHERE transactions.account_id = $1
          ORDER BY date DESC
          LIMIT 10
        SQL

        db_result = nil

        until db_result
          byebug
          db_result = db.resume(sql_ten_transactions, [params['id']])
        end

        ten_transactions = db_result.to_a

        result["ultimas_transacoes"] = ten_transactions.map do |transaction|
          { 
            "valor": transaction['amount'].to_i,
            "tipo": transaction['transaction_type'],
            "descricao": transaction['description'],
            "realizada_em": transaction['date']
          }
        end

        body = result
      end
    rescue PG::ForeignKeyViolation, NotFoundError
      status = 404
    rescue *VALIDATION_ERRORS => err
      status = 422
      body = { error: err.message }
    end

    client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
    client.close

    client = Fiber.yield
  end
end

accept = Fiber.new do |io|
  loop do 
    client, _ = io.accept_nonblock

    @fibers << [handler, client]
  rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
    @readable[io] = Fiber.current
    Fiber.yield
  end
end

accept.resume(server)

loop do
  while @fibers.any?
    fiber, args = @fibers.shift
    fiber&.resume(args)
  end

  ready_to_read, _, _ = IO.select(@readable.keys, nil, nil, 0.1)

  ready_to_read&.each do |io|
    fiber = @readable.delete(io)
    fiber&.resume(io)
  end

  ready_to_write, _, _ = IO.select(nil, @writable.keys, nil, 0.1)

  ready_to_write&.each do |io|
    fiber = @writable.delete(io)
    fiber&.resume(io)
  end
end
