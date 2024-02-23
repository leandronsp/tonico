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

pool = ConnectionPool.new(size: 5, timeout: 300) do 
  config = {
    host: (ENV['DATABASE_HOST'] || 'localhost'),
    user: 'postgres',
    password: 'postgres', 
    dbname: 'postgres'
  }

  PG.connect(config)
end

@fibers = []
@readable = {}
@writable = {}

## Response Fiber
response = Fiber.new do |client, body|
  loop do
    client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
    client.close

    client, body = Fiber.yield # suspend
  end
end

## Database Fiber
db = Fiber.new do |client|
  loop do
    conn = pool.checkout
    pg_io = IO.for_fd(conn.socket)

    # async (nonblocking)
    conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

    @readable[pg_io] = [Fiber.current, [client]]
    client = Fiber.yield(client) # suspend

    while conn.consume_input
      @readable[pg_io] = [Fiber.current, [client]]
      client = Fiber.yield(client) # suspend
    end

    db_result = conn.get_result
    body = db_result.to_a.first

    conn.discard_results
    conn.flush

    response.resume(client, body)
    client = Fiber.yield(client) # suspend
  end
end

accept = Fiber.new do |io|
  loop do 
    client, _ = io.accept_nonblock 
    headline = client.gets
    puts headline

    db.resume(client)
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
