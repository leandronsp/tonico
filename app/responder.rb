class Responder < Fiber 
  def initialize
    super(&lambda do |client, status, body|
      client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    end)
  end
end
