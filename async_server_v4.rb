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

    PG::Connection.connect_start(config) # nonblocking connection
  end
end

@fibers = []
@readable = {}
@writable = {}

## Response Fiber
response = Fiber.new do |client, body|
  loop do
    client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
    client.close

    client, body = Fiber.yield
  end
end

## Database Fiber
db = Fiber.new do |client|
  loop do
    # nonblocking (async DB call)
    conn = pool.checkout
    pg_io = IO.for_fd(conn.socket)

    poll_status = conn.connect_poll

    until poll_status == PG::PGRES_POLLING_OK || poll_status == PG::PGRES_POLLING_FAILED
      case poll_status
      in PG::PGRES_POLLING_READING
        @readable[pg_io] = [Fiber.current, [client]]
      in PG::PGRES_POLLING_WRITING
        @writable[pg_io] = [Fiber.current, [client]]
      end

      Fiber.yield

      poll_status = conn.connect_poll
    end

    conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

    loop do 
      while conn.is_busy
        conn.consume_input

        @writable[pg_io] = [Fiber.current, [client]]
        Fiber.yield 
      end

      db_result = conn.get_result
      break unless db_result
      body = db_result.to_a.first

      @fibers << [response, [client, body]]

      client = Fiber.yield(client)
    end
  end
end

accept = Fiber.new do |io|
  loop do 
    client, _ = io.accept_nonblock # not raise WaitReadable
    headline = client.gets
    puts headline

    @fibers << [db, client]
  rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
    @readable[io] = [Fiber.current, []]
    Fiber.yield
  end
end

accept.resume(server)

# Event Loop (async)
loop do
  # Calling callbacks (resuming fibers)
  while @fibers.any?
    fiber, args = @fibers.shift
    fiber.resume(args) 
  end

  # Reading
  readable_fds = @readable.keys
  ready_to_read, _, _ = IO.select(readable_fds, nil, nil, 0.1)

  ready_to_read&.each do |io|
    (fiber, args) = @readable.delete(io)
    fiber.resume(args)
  end

  # Writing
  writable_fds = @writable.keys
  _, ready_to_write, _ = IO.select(nil, writable_fds, nil, 0.1)

  ready_to_write&.each do |io|
    (fiber, args) = @writable.delete(io)
    fiber.resume(args)
  end
end
