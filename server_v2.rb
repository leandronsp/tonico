# frozen_string_literal: true

require 'socket'

require_relative 'app/request'
require_relative 'app/database'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

def handle(client)
  result= {}
  starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  request, params = Request.parse(client)

  conn = Database.pool.checkout

  #### Saldo

  sql_select_account = <<~SQL
    SELECT 
      balances.amount AS balance, 
      accounts.limit_amount AS limit_amount
    FROM accounts 
    JOIN balances ON balances.account_id = accounts.id
    WHERE accounts.id = $1
  SQL

  account = conn.exec_params(sql_select_account, [params['id']]).first

  result["saldo"] = {  
    "total": account['balance'].to_i,
    "data_extrato": Time.now.strftime("%Y-%m-%d"),
    "limite": account['limit_amount'].to_i
  }

  ## Transactions

  sql_ten_transactions = <<~SQL
    SELECT amount, transaction_type, description, TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US') AS date
    FROM transactions
    WHERE transactions.account_id = $1
    ORDER BY date DESC
    LIMIT 10
  SQL

  ten_transactions = conn.exec_params(sql_ten_transactions, [params['id']])

  result["ultimas_transacoes"] = ten_transactions.map do |transaction|
    { 
      "valor": transaction['amount'].to_i,
      "tipo": transaction['transaction_type'],
      "descricao": transaction['description'],
      "realizada_em": transaction['date']
    }
  end

  status = 200
  body = result.to_json

  response = <<~HTTP
    HTTP/2.0 #{status}
    Content-Type: application/json

    #{body}
  HTTP

  client.puts(response)
  client.close

  ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  puts "=> Took #{((ending - starting) * 1000).round(2)}ms)\n"
end

if ENV['ASYNC']
  readable = {}
  fibers = []

  accept = Fiber.new do |io| 
    loop do
      client, _addr = io.accept_nonblock

      handle(client)
    rescue IO::WaitReadable, Errno::EINTR
      readable[io] = Fiber.current
      Fiber.yield
    end
  end

  accept.resume(server)

  loop do 
    while fibers.any? 
      fiber = fibers.shift
      fiber&.resume
    end

    ready_to_read, _, _ = IO.select(readable.keys, nil, nil, 0.1)

    ready_to_read&.each do |io|
      fiber = readable.delete(io)
      fiber.resume
    end
  end
else 
  loop do
    client, _ = server.accept 
    handle(client)
  end
end
