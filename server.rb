# frozen_string_literal: true

require 'socket'
require_relative 'handler'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

#tqueue = Queue.new
#
#5.times do
#  Thread.new do
#    loop do
#      client = tqueue.pop
#      Handler.call(client)
#    end
#  end
#end

#loop do
#  client, _ = server.accept 
#  Handler.call(client)
#end

fibers = []
readable = {}

accept = Fiber.new do
  loop do
    client, _addr = server.accept_nonblock
    
    Handler.call(client, fibers)
  rescue IO::WaitReadable, Errno::EINTR
    readable[server] = Fiber.current
    Fiber.yield
  end
end

accept.resume

loop do 
  while fibers.any?
    fiber = fibers.shift
    fiber.resume if fiber&.alive?
  end

  ready_to_read, _ready_to_write, _ = IO.select(readable.keys, nil, nil, 0.1)

  ready_to_read&.each do |io|
    fiber = readable.delete(io)
    fiber.resume
  end
end
