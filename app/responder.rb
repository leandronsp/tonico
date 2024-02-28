class Responder < Fiber 
  def self.call(*args)
    new do |client, status, body|
      client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    end.resume(*args)
  end
end
