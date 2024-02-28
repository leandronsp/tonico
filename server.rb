# frozen_string_literal: true

require 'socket'
require 'pg'
require 'connection_pool'

require_relative 'app/acceptor'
require_relative 'app/event_loop'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

@state = { 
  readable: {},
  writable: {},
  waiting_pool: {},
  waiting_query: {},
}

@state[:pool] = ConnectionPool.new(size: (ENV['DB_POOL_SIZE'] || 10), timeout: 300) do 
  config = {
    host: (ENV['DATABASE_HOST'] || 'localhost'),
    port: 5432,
    user: 'postgres',
    password: 'postgres', 
    dbname: 'postgres'
  }

  PG::Connection.connect_start(config)
end

Acceptor.call(@state, server)
EventLoop.run(@state)
