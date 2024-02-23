require 'pg'
require 'connection_pool'
require 'byebug'

## Define Main Fiber
main = Fiber.new do |pool|
  starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  50.times do 
    handler = Fiber.new do |conn|
      loop do 
        break if [PG::PGRES_POLLING_OK, PG::PGRES_POLLING_FAILED].include?(conn.connect_poll)
      end

      conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1])

      loop do 
        while conn.is_busy
          conn.consume_input
        end

        result = conn.get_result 
        break unless result

        puts "Query result: #{result.values}"
      end
    end

    handler.resume(pool.checkout)
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
