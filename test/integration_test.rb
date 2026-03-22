# test/integration_test.rb
require 'net/http'
require 'json'
require 'timeout'

def test(name)
  print "Testing #{name}... "
  yield
  puts "\e[32mPASSED\e[0m"
rescue => e
  puts "\e[31mFAILED\e[0m"
  puts "  Error: #{e.message}"
end

def wait_for_server(port, ssl: false)
  Timeout.timeout(10) do
    begin
      uri = URI("#{ssl ? 'https' : 'http'}://127.0.0.1:#{port}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = ssl
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if ssl
      http.open_timeout = 1
      http.get('/')
      true
    rescue Errno::ECONNREFUSED, Net::ReadTimeout, OpenSSL::SSL::SSLError
      sleep 0.5
      retry
    end
  end
end

project_root = File.expand_path("..", __dir__)
bin_path = File.join(project_root, "bin/eksa-server")
app_path = File.join(project_root, "examples/hello.ru")

# --- TEST 1: Basic HTTP (Single Mode) ---
test "Basic HTTP (Single Mode)" do
  server_pid = spawn("bundle exec #{bin_path} #{app_path} -p 4050 -w 0")
  wait_for_server(4050)
  
  res = Net::HTTP.get_response(URI("http://127.0.0.1:4050"))
  raise "Status #{res.code} should be 200" unless res.code == "200"
  raise "Body mismatch" unless res.body.include?("Halo dari EksaServer")
  
  Process.kill("TERM", server_pid)
  Process.wait(server_pid)
  sleep 1
end

# --- TEST 2: Cluster Mode & Controls ---
test "Cluster Mode & Stats" do
  server_pid = spawn("bundle exec #{bin_path} #{app_path} -p 4071 -w 2 -c 4072")
  wait_for_server(4071)
  sleep 1 # Pastikan worker sudah siap
  
  # Check stats
  stats_res = Net::HTTP.get(URI("http://127.0.0.1:4072"))
  stats = JSON.parse(stats_res)
  raise "Worker count mismatch" unless stats["workers"] == 2
  raise "Memory info missing" unless stats["memory_kb"] > 0
  
  Process.kill("TERM", server_pid)
  Process.wait(server_pid)
  sleep 1
end

# --- TEST 3: SSL / HTTPS ---
test "HTTPS (SSL)" do
  cert = File.join(project_root, "test/server.crt")
  key = File.join(project_root, "test/server.key")
  server_pid = spawn("bundle exec #{bin_path} #{app_path} -p 4453 --ssl-cert #{cert} --ssl-key #{key}")
  wait_for_server(4453, ssl: true)
  
  uri = URI("https://127.0.0.1:4453")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  res = http.get('/')
  raise "HTTPS Status #{res.code} should be 200" unless res.code == "200"
  
  Process.kill("TERM", server_pid)
  Process.wait(server_pid)
  sleep 1
end

# --- TEST 4: .env Priority ---
test ".env Priority vs CLI" do
  File.write(".env", "PORT=5565")
  # CLI -p 5566 should override .env 5565
  server_pid = spawn("bundle exec #{bin_path} #{app_path} -p 5566 -c 0")
  wait_for_server(5566)
  
  res = Net::HTTP.get_response(URI("http://127.0.0.1:5566"))
  raise "CLI should override .env" unless res.code == "200"
  
  Process.kill("TERM", server_pid)
  Process.wait(server_pid)
  sleep 1
  
  # Now test automatic .env use
  server_pid = spawn("bundle exec #{bin_path} #{app_path} -c 0")
  wait_for_server(5565)
  res = Net::HTTP.get_response(URI("http://127.0.0.1:5565"))
  raise ".env should be used automatically" unless res.code == "200"
  
  Process.kill("TERM", server_pid)
  Process.wait(server_pid)
  File.delete(".env")
  sleep 1
end

puts "\n\e[32mAll integration tests completed successfully!\e[0m"
