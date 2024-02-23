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

puts 'Listening on port 3000'

def pool
  @pool ||= ConnectionPool.new(size: 5, timeout: 300) do 
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

controller = Fiber.new do
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

    conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

    loop do 
      while conn.is_busy
        conn.consume_input
      end

      result = conn.get_result
      break unless result

      Fiber.yield(result.to_a.to_json)
    end
  end
end

handler = Fiber.new do |client|
  loop do 
    headline = client.gets
    puts headline

    body = nil

    while body == nil
      body = controller.resume
    end

    client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body}"
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
