require 'pg'
require 'connection_pool'
require 'byebug'

@readable = {}
@writable = {}

## Define Main Fiber
main = Fiber.new do |pool|
  starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  50.times do 
    poller = Fiber.new do |conn|
      io = IO.for_fd(conn.socket)

      loop do 
        case conn.connect_poll
        in PG::PGRES_POLLING_READING
          @readable[io] = Fiber.current
          Fiber.yield(:continue, conn)
        in PG::PGRES_POLLING_WRITING
          @writable[io] = Fiber.current
          Fiber.yield(:continue, conn)
        else
          Fiber.yield(:stop, conn)
        end
      end
    end

    flag, conn = poller.resume(pool.checkout)

    next if flag == :stop

    conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

    loop do 
      while conn.is_busy
        conn.consume_input
      end

      result = conn.get_result 
      break unless result

      puts "Query result: #{result.values}"
    end
  rescue => e
    byebug
  end

  ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  puts "Finished in #{(ending - starting) * 1000}ms"
end

## Databse Pool
pool = ConnectionPool.new(size: 5, timeout: 300) do 
  config = {
    host: 'localhost',
    user: 'postgres',
    password: 'postgres', 
    dbname: 'postgres'
  }

  PG::Connection.connect_start(config)
end

## Start Main Fiber
main.resume(pool)

## Event loop 
loop do
  ready_to_read, _, _ = IO.select(@readable.keys, nil, nil, 0.1)

  ready_to_read&.each do |io|
    fiber = @readable.delete(io)
    fiber&.resume
  end

  _, ready_to_write, _ = IO.select(nil, @writable.keys, nil, 0.1)

  ready_to_write&.each do |io|
    fiber = @writable.delete(io)
    fiber&.resume
  end
end
