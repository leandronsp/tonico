class EventLoop
  def self.run(*args) = new(*args).run

  def initialize(state)
    @state = state
  end

  def run
    loop do 
      ############ Waiting Pool #############
      @state[:waiting_pool].each do |(fiber, pool)|
        if fiber.alive? && pool.available > 0
          fiber.resume
          @state[:waiting_pool].delete(fiber)
        end

        unless fiber.alive?
          @state[:waiting_pool].delete(fiber)
        end
      end

      ############ Waiting Query #############
      @state[:waiting_query].each do |(fiber, conn)|
        if conn.is_busy
          conn.consume_input
        elsif fiber.alive?
          @state[:waiting_query].delete(fiber) 
          fiber.resume 
        end

        unless fiber.alive?
          @state[:waiting_query].delete(fiber)
        end
      end

      ############ Waiting Reads #############
      reads, _, _ = IO.select(@state[:readable].keys, nil, nil, 0.1)

      reads&.each do |io|
        fiber = @state[:readable].delete(io)
        fiber.resume if fiber.alive?
      end

      ############ Waiting Writes #############
      _, writes, _ = IO.select(nil, @state[:writable].keys, nil, 0.1) 

      writes&.each do |io|
        fiber = @state[:writable].delete(io)
        fiber.resume if fiber.alive?
      end
    end
  end
end
