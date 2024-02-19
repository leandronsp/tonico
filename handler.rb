# frozen_string_literal: true

require 'pg'
require 'json'

## Handler
class Handler
  def self.call(client)
    starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    headline = client.gets
    return unless headline

    db = PG.connect(host: 'localhost', user: 'postgres',
                    password: 'postgres', dbname: 'postgres')
    
    sql = <<~SQL
      SELECT * FROM accounts
    SQL

    result = db.async_exec(sql).to_a
    db.close

    status = 200
    body = result.to_json

    response = <<~HTTP
      HTTP/2.0 #{status}
      Content-Type: application/json

      #{body}
    HTTP

    client.puts(response)
    client.close

    ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    puts "#{headline.chomp} (took #{((ending - starting) * 1000).round(2)}ms)\n"
  end
end
