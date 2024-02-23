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

pool = ConnectionPool.new(size: 10, timeout: 300) do 
  config = {
    host: (ENV['DATABASE_HOST'] || 'localhost'),
    port: 5432,
    user: 'postgres',
    password: 'postgres', 
    dbname: 'postgres'
  }

  PG.connect(config)
end

@fibers = []
@readable = {}
@writable = {}

class NotFoundError < StandardError; end
class InvalidDataError < StandardError; end

accept = Fiber.new do |io|
  loop do 
    client, _ = io.accept_nonblock 
    request, params = Request.parse(client)

    db = Fiber.new do |sql, params|
      loop do 
        conn = pool.checkout
        pg_io = conn.socket_io

        conn.send_query_params(sql, params)

        result = nil

        loop do
          conn.consume_input

          while conn.is_busy
            conn.consume_input
          end

          db_result = conn.get_result
          break unless db_result

          result = db_result.to_a
          break if result
        end

        conn.discard_results
        pool.checkin
        sql, params = Fiber.yield(result)
      end
    end

    case request
    in 'GET /clientes/:id/extrato'
      status = 200

      sql_select_account = <<~SQL
        SELECT 
          limit_amount,
          balance
        FROM accounts
        WHERE id = $1
      SQL

      sql_ten_transactions = <<~SQL
        SELECT 
          amount, 
          transaction_type, 
          description, 
          TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US') AS date
        FROM transactions
        WHERE transactions.account_id = $1
        ORDER BY date DESC
        LIMIT 10
      SQL

      account = db.resume(sql_select_account, [params['id']]).first
      raise NotFoundError unless account

      ten_transactions = db.resume(sql_ten_transactions, [params['id']])

      body = {
        "saldo": { 
          "total": account['balance'].to_i,
          "data_extrato": Time.now.strftime("%Y-%m-%d"),
          "limite": account['limit_amount'].to_i
        },
        "ultimas_transacoes": ten_transactions.map do |transaction|
          { 
            "valor": transaction['amount'].to_i,
            "tipo": transaction['transaction_type'],
            "descricao": transaction['description'],
            "realizada_em": transaction['date']
          }
        end
      }

      client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    in 'POST /clientes/:id/transacoes'
      status = 200

      reached_limit = lambda do |balance, amount, limit_amount|
        return false if (balance - amount) > limit_amount
        (balance - amount).abs > limit_amount
      end

      raise InvalidDataError unless params['id'] && params['valor'] && params['tipo'] && params['descricao'] 
      raise InvalidDataError if params['descricao'] && params['descricao'].empty?
      raise InvalidDataError if params['descricao'] && params['descricao'].size > 10
      raise InvalidDataError if params['valor'] && (!params['valor'].is_a?(Integer) || !params['valor'].positive?)
      raise InvalidDataError unless %w[d c].include?(params['tipo'])

      operator = params['tipo'] == 'd' ? '-' : '+'

      sql_insert_transaction = <<~SQL
        INSERT INTO transactions (account_id, amount, transaction_type, description)
        VALUES ($1, $2, $3, $4)
      SQL

      sql_update_balance = <<~SQL
        UPDATE accounts 
        SET balance = balance #{operator} $2
        WHERE id = $1
      SQL

      sql_select_account = <<~SQL
        SELECT 
          limit_amount,
          balance
        FROM accounts
        WHERE id = $1
        FOR UPDATE
      SQL

      account = db.resume(sql_select_account, [params['id']]).first
      raise NotFoundError unless account

      raise InvalidDataError if params['tipo'] == 'd' && 
        reached_limit.call(account['balance'].to_i, params['valor'].to_i, account['limit_amount'].to_i)

      db.resume(sql_insert_transaction, params.values_at('id', 'valor', 'tipo', 'descricao'))
      db.resume(sql_update_balance, params.values_at('id', 'valor'))

      account = db.resume(sql_select_account, [params['id']]).first

      body = {
        "limite": account["limit_amount"].to_i,
        "saldo": account["balance"].to_i
      }
        
      client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    else 
      raise NotFoundError
    end
  rescue InvalidDataError
    client.puts "HTTP/1.1 422\r\n\r\n"
    client.close
  rescue NotFoundError
    client.puts "HTTP/1.1 404\r\n\r\n"
    client.close
  rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
    @readable[io] = [Fiber.current, []]
    Fiber.yield
  end
end

accept.resume(server)

# Event Loop (async)
loop do
  # Reading
  ready_to_read, _, _ = IO.select(@readable.keys, nil, nil, 0.1)

  ready_to_read&.each do |io|
    fiber, args = @readable.delete(io)
    fiber.resume(*args)
  end

  # Writing
  _, ready_to_write, _ = IO.select(nil, @writable.keys, nil, 0.1)

  ready_to_write&.each do |io|
    fiber, args = @writable.delete(io)
    fiber&.resume(*args)
  end
end
