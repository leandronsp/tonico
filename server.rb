if ENV['ASYNC']
  load 'async_server.rb'
else 
  load 'sync_server.rb'
end
