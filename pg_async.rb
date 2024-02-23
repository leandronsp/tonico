require 'pg'
require 'connection_pool'
require 'byebug'

def pool
  @pool ||= ConnectionPool.new(size: 5, timeout: 300) do 
    config = {
      host: 'localhost',
      user: 'postgres',
      password: 'postgres', 
      dbname: 'postgres'
    }

    PG::Connection.connect_start(config) # non-blocking
  end
end

starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

50.times do 
  conn = pool.checkout

  loop do 
    break if [PG::PGRES_POLLING_OK, PG::PGRES_POLLING_FAILED].include?(conn.connect_poll)
  end

  conn.send_query_params("SELECT * FROM accounts WHERE id = $1", [1]) # non-blocking

  loop do 
    # blocking until connection is not busy
    while conn.is_busy
      conn.consume_input
    end

    # fetch results
    result = conn.get_result
    break unless result

    puts "Query result: #{result.to_a}"
  end
end

ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts "Finished in #{(ending - starting) * 1000}ms"
