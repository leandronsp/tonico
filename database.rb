require 'pg'
require 'connection_pool'

class Database 
  POOL_SIZE = ENV['DB_POOL_SIZE'] || 5

  def self.pool
    @pool ||= ConnectionPool.new(size: POOL_SIZE, timeout: 300) { new_connection }
  end

  def self.new_connection
    PG.connect(host: (ENV['DATABASE_HOST'] || 'localhost'), user: 'postgres',
               password: 'postgres', dbname: 'postgres')
  end
end
