# frozen_string_literal: true

require 'socket'
require 'pg'
require 'json'
require 'byebug'
require 'connection_pool'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

def pool
  @pool ||= ConnectionPool.new(size: 5, timeout: 300) do 
    config = {
      host: (ENV['DATABASE_HOST'] || 'localhost'),
      user: 'postgres',
      password: 'postgres', 
      dbname: 'postgres'
    }

    PG::Connection.connect_start(config) # non-blocking
  end
end

puts 'Listening on port 3000'

loop do
  ready_to_read, _, _ = IO.select([server], nil, nil, 0.1)

  ready_to_read&.each do |io|
    client, _ = io.accept_nonblock
    headline = client.gets

    conn = pool.checkout # non-blocking connection

    loop do
      break if conn.connect_poll === PG::PGRES_POLLING_OK || conn.connect_poll == PG::PGRES_POLLING_FAILED
    end

    conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

    loop do 
      while conn.is_busy
        conn.consume_input
      end

      result = conn.get_result
      break unless result

      body = result.to_a.to_json

      client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body}"
      client.close
    end
  rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
    # faz nada
  end
end
