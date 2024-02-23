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

    PG.connect(config)
  end
end

starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

50.times do 
  conn = pool.checkout

  result = conn.exec_params("SELECT * FROM accounts WHERE id = $1", [1])

  puts "Query result: #{result.values}"
end

ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts "Finished in #{(ending - starting) * 1000}ms"
