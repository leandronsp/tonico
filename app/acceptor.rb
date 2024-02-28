require_relative 'request'
require_relative 'controller'

class Acceptor < Fiber 
  def self.call(*args)
    new do |state, io|
      loop do 
        client, _ = io.accept_nonblock 
        request, params = Request.parse(client)

        Controller.call(state, client, request, params)
      rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
        state[:readable][io] = Fiber.current
        Fiber.yield
      end
    end.resume(*args)
  end
end
