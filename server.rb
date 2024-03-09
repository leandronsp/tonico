# frozen_string_literal: true

require 'socket'
require_relative 'app/handler'

require 'async'
require 'async/scheduler'

scheduler = Async::Scheduler.new
Fiber.set_scheduler(scheduler)

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

Fiber.schedule do
  loop do
    client, _ = server.accept

    Fiber.schedule do
      Handler.call(client)
      client.close
    end
  end
end
