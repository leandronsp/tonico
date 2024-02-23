# frozen_string_literal: true

require 'socket'
require 'pg'
require 'json'
require 'connection_pool'

require 'byebug'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

def pool
  @pool ||= ConnectionPool.new(size: 5, timeout: 300) do 
    config = {
      host: (ENV['DATABASE_HOST'] || 'localhost'),
      user: 'postgres',
      password: 'postgres', 
      dbname: 'postgres'
    }

    PG.connect(config)
  end
end

loop do
  client, _ = server.accept # blocking

  headline = client.gets
  puts headline

  conn = pool.checkout
  result = conn.exec_params("SELECT * FROM accounts WHERE id = $1", [1]) # blocking
  body = result.to_a.to_json

  client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body}"
  client.close
end
