require 'socket'

server = Socket.new(:INET, :STREAM)
addr = Socket.pack_sockaddr_in(3000, '0.0.0.0')

## Bind the socket to the address
server.bind(addr)
server.listen(2)

puts "Listening on port 3000"

# Main Thread (process)
loop do
  #client, _ = server.accept # Blocking I/O

  # emulate server.accept
  begin
    client, _ = server.accept_nonblock # I/O non-blocking
  rescue IO::WaitReadable, Errno::EINTR
    IO.select([server])
    retry
  end

  puts "Client connected"

  client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n{}"
  client.close
end
