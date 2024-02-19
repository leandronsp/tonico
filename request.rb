require 'json'

require_relative 'bank_statement'
require_relative 'transaction'

class Request 
  def self.parse(client)
    request = ''
    message = ''
    headers = {}
    params = {}

    if (line = client.gets)
      message += line

      headline_regex = /^(GET|POST)\s\/clientes\/(\d+)\/(.*?)\sHTTP.*?$/
      verb, id, action = line.match(headline_regex).captures
      params['id'] = id
      request = "#{verb} /clientes/:id/#{action}"
    end

    puts "\n[#{Time.now}] #{message}"

    while (line = client.gets)
      break if line == "\r\n"

      header, value = line.split(': ')
      headers[header] = value.chomp

      message += line
    end

    if headers['Content-Length']
      body_size = headers['Content-Length'].to_i
      body = client.read(body_size)

      params.merge!(JSON.parse(body))
    end

    [request, params]
  end
end
