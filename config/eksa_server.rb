# config/eksa_server.rb
# Puma-style DSL configuration

threads 5, 20
workers 2
bind "tcp://0.0.0.0:3000"
# bind "unix:///tmp/eksa.sock"

on_worker_boot do |index|
  puts "Worker #{index} sedang bangun..."
end
