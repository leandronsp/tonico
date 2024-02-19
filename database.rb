require 'pg'
require 'connection_pool'

class Database 
  def self.pool
    @pool ||= ConnectionPool.new(size: 5, timeout: 300) { new_connection }
  end

  def self.new_connection
    PG.connect(host: (ENV['DATABASE_HOST'] || 'localhost'), user: 'postgres',
               password: 'postgres', dbname: 'postgres')
  end
end
