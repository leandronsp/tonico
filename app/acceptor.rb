require_relative 'request'
require_relative 'controller'
require_relative 'responder'

class Acceptor < Fiber 
  def initialize(state)
    @state = state

    super(&lambda do |io|
      loop do 
        client, _ = io.accept_nonblock 
        request, params = Request.parse(client)

        controller = Controller.new(@state)

        while controller.alive?
          continuation, data = controller.resume(request, params)

          if continuation == :result
            controller.raise rescue nil # terminate preemptively

            responder = Responder.new
            responder.resume(client, *data)
          end
        end
      rescue IO::WaitReadable, Errno::EINTR, IO::EAGAINWaitReadable
        @state[:readable][io] = Fiber.current
        Fiber.yield
      end
    end)
  end
end
