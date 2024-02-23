# frozen_string_literal: true

require 'socket'
require 'pg'
require 'json'
require 'byebug'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

if ENV['ASYNC']
  readable = {}
  fibers = []

  accept = Fiber.new do |io| 
    loop do
      client, _addr = io.accept_nonblock
      headline = client.gets

      config = {
        host: 'localhost',
        user: 'postgres',
        password: 'postgres', 
        dbname: 'postgres'
      }

      conn = PG::Connection.connect_start(config)
      pg_socket = IO.for_fd(conn.socket)

      poll_status = PG::PGRES_POLLING_WRITING

      until poll_status == PG::PGRES_POLLING_OK || poll_status == PG::PGRES_POLLING_FAILED
        case poll_status
        in PG::PGRES_POLLING_READING
          IO.select([pg_socket], nil, nil, 0.5)
        in PG::PGRES_POLLING_WRITING
          IO.select(nil, [pg_socket], nil, 0.5)
        end

        poll_status = conn.connect_poll
      end

      conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

      loop do 
        conn.consume_input

        while conn.is_busy
          IO.select([pg_socket], nil, nil, 0.5)
          conn.consume_input
        end

        result = conn.get_result or break
        body = result.to_a.to_json

        client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body}"
        client.close
      end

      conn.close
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
    headline = client.gets

    config = {
      host: 'localhost',
      user: 'postgres',
      password: 'postgres', 
      dbname: 'postgres'
    }

    conn = PG.connect(config)
    result = conn.exec_params("SELECT * FROM accounts WHERE id = $1", [1])
    body = result.to_a.to_json

    client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body}"
    client.close
  end
end
