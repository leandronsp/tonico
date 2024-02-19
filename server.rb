# frozen_string_literal: true

require 'socket'
require_relative 'handler'

server = Socket.new(:INET, :STREAM)
server.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

server.bind(addr)
server.listen(Socket::SOMAXCONN)

puts 'Listening on port 3000'

#loop do
#  client, _ = server.accept 
#
#  Handler.call(client)
#end

io = []

loop do
  ready_to_read, _ready_to_write, _ = IO.select(io, nil, nil, 0.1)

  ready_to_read&.each do |client|
    io.delete(client)
    Handler.call(client)
  end

  client, _addr = server.accept_nonblock
  io << client
rescue IO::WaitReadable, Errno::EINTR
  retry
end
