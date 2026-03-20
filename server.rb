# server.rb
require 'nio'
require 'socket'
require 'thread'
require 'json'
require 'fileutils'
require 'openssl'
require 'rack'
require 'rackup'

# Load Modular Core
require_relative 'lib/eksa_server/events'
require_relative 'lib/eksa_server/binder'
require_relative 'lib/eksa_server/thread_pool'
require_relative 'lib/eksa_server/configuration'

class EksaServerCore
  def initialize(app, config = {})
    @app_path_or_obj = app
    @config = EksaServer::Configuration.new(config)
    
    # Load optional config file
    if File.exist?('config/eksa_server.rb')
      @config.load_config('config/eksa_server.rb')
    end

    @options = @config.options
    @events = EksaServer::Events.new($stdout, $stderr)
    @binder = EksaServer::Binder.new(@events)
    
    @app = load_app(@app_path_or_obj)
    @worker_pids = {}
    @heartbeats = {}
    @hb_dir = "/tmp/eksa_hb"
    FileUtils.mkdir_p(@hb_dir)
  end

  def start
    print_banner
    
    # Bina Sockets (Binder)
    if @options[:binds].any?
      @options[:binds].each do |url|
        if url =~ %r{tcp://(.*):(\d+)}
          @binder.add_tcp_listener($1, $2.to_i, @options)
        elsif url =~ %r{unix://(.*)}
          @binder.add_unix_listener($1)
        end
      end
    else
      @binder.add_tcp_listener(@options[:host], @options[:port], @options)
    end

    print_server_info
    
    @events.info "Memuat aplikasi (Optimasi Copy-on-Write)..."
    start_control_server if @options[:control_port]

    if @options[:workers] > 0
      start_cluster
    else
      run_worker
    end
  rescue Interrupt
    terminate_all
  ensure
    cleanup
  end

  private

  def load_app(app_path_or_obj)
    if app_path_or_obj.is_a?(String) && File.extname(app_path_or_obj) == ".ru"
      app_path = File.expand_path(app_path_or_obj)
      @events.info "Memuat aplikasi dari #{app_path}..."
      app_dir = File.dirname(app_path)
      Dir.chdir(app_dir)
      result = Rack::Builder.parse_file(app_path)
      result.respond_to?(:first) ? result.first : result
    else
      app_path_or_obj
    end
  end

  def start_cluster
    @options[:workers].times { |i| spawn_worker(i) }
    @events.info "Cluster aktif dengan #{@options[:workers]} worker. 🚀"

    trap('INT') { terminate_all }
    trap('TERM') { terminate_all }
    trap('USR2') { phased_restart }

    loop do
      check_workers
      sleep 2
    end
  end

  def spawn_worker(index)
    pid = fork do
      @options[:on_worker_boot]&.call(index)
      run_worker(index)
    end
    @worker_pids[index] = pid
    @heartbeats[pid] = Time.now
  end

  def check_workers
    @worker_pids.each do |index, pid|
      hb_file = "#{@hb_dir}/#{pid}.hb"
      @heartbeats[pid] = File.mtime(hb_file) if File.exist?(hb_file)

      if Time.now - @heartbeats[pid] > @options[:timeout]
        @events.warn "Worker #{index} (PID:#{pid}) timeout! Me-restart..."
        Process.kill('KILL', pid) rescue nil
        spawn_worker(index)
      end
    end
  end

  def phased_restart
    @events.info "\e[35mMemulai Phased Restart...\e[0m"
    @worker_pids.each do |index, pid|
      Process.kill('TERM', pid)
      Process.wait(pid)
      spawn_worker(index)
    end
    @events.info "Phased Restart selesai. ✔"
  end

  def terminate_all
    @events.info "Mematikan server..."
    @worker_pids.values.each { |pid| Process.kill('TERM', pid) rescue nil }
    cleanup
    exit
  end

  def run_worker(id = 0)
    srand
    @selector = NIO::Selector.new
    @thread_pool = EksaServer::ThreadPool.new(@options[:min_threads], @options[:max_threads]) do |client|
      process_client(client)
    end
    
    @binder.listeners.each do |io, _|
      @selector.register(io, :r).value = :accept
    end

    Thread.new do
      loop do
        FileUtils.touch("#{@hb_dir}/#{Process.pid}.hb")
        sleep 5
      end
    end

    loop do
      @selector.select(5) do |monitor|
        if monitor.value == :accept
          begin
            client = monitor.io.accept_nonblock
            @selector.register(client, :r).value = :read
          rescue IO::WaitReadable
          end
        else
          client = monitor.io
          @selector.deregister(client)
          @thread_pool << client
        end
      end
    end
  rescue Interrupt, SignalException
  ensure
    @thread_pool&.shutdown
    @selector&.close
  end

  def process_client(client)
    # Baca request line & headers
    lines = []
    while (line = client.gets) && line != "\r\n"
      lines << line.chomp
    end
    return client.close if lines.empty?

    method, path, _version = lines.first.split(" ")
    headers = lines[1..-1].each_with_object({}) do |line, h|
      k, v = line.split(": ", 2)
      h[k] = v
    end

    env = {
      'REQUEST_METHOD'    => method,
      'SCRIPT_NAME'       => '',
      'PATH_INFO'         => path.split("?", 2)[0],
      'QUERY_STRING'      => path.split("?", 2)[1] || "",
      'SERVER_NAME'       => @options[:host],
      'SERVER_PORT'       => @options[:port].to_s,
      'rack.version'      => Rack::VERSION,
      'rack.url_scheme'   => @options[:ssl] ? 'https' : 'http',
      'rack.input'        => StringIO.new(""),
      'rack.errors'       => $stderr,
      'rack.multithread'  => true,
      'rack.multiprocess' => @options[:workers] > 0,
      'rack.run_once'     => false
    }

    headers.each { |k, v| env["HTTP_#{k.upcase.gsub('-', '_')}"] = v }

    # Panggil aplikasi Rack
    begin
      status, res_headers, res_body = @app.call(env)
    rescue => e
      @events.error "Aplikasi gagal merespons: #{e.message}"
      status = 500
      res_headers = { "Content-Type" => "text/html" }
      res_body = [render_error_page(e)]
    end
    
    # Send Response
    response = "HTTP/1.1 #{status} OK\r\n"
    res_headers.each { |k, v| response << "#{k}: #{v}\r\n" }
    
    full_body = ""
    res_body = [res_body] unless res_body.respond_to?(:each)
    res_body.each { |chunk| full_body << chunk }
    res_body.close if res_body.respond_to?(:close)

    response << "Content-Length: #{full_body.bytesize}\r\n\r\n"
    response << full_body

    client.write(response)
    @events.info "Selesai: #{method} #{path} -> #{status} (Threads: #{@thread_pool.spawned})"
    client.close
  rescue => e
    @events.error "Kesalahan tingkat rendah: #{e.message}"
    client.close rescue nil
  end

  def render_error_page(e)
    # Gunakan path absolut relatif terhadap file ini agar aman saat jadi gem
    template_path = File.expand_path('../lib/eksa_server/error.html', __FILE__)
    @error_template ||= File.read(template_path) rescue nil
    
    if @error_template
       @error_template.gsub("{{ERROR}}", "#{e.class}: #{e.message}")
    else
      "<html><body><h1>Internal Server Error</h1><p>#{e.message}</p></body></html>"
    end
  end

  def start_control_server
    start_time = Time.now
    Thread.new do
      begin
        server = TCPServer.new('127.0.0.1', @options[:control_port])
        loop do
          client = server.accept
          uptime = (Time.now - start_time).to_i
          stats = { workers: @worker_pids.size, uptime: uptime }.to_json
          client.puts "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n#{stats}"
          client.close
        end
      rescue => e
        @events.error "Control Server Gagal: #{e.message}"
      end
    end
  end

  def cleanup
    @binder&.close
    FileUtils.rm_rf(@hb_dir)
  end

  def print_banner
    puts "\e[34m"
    puts "  \e[1mEKSA SERVER v2 \e[0m- \e[90mBy: IshikawaUta\e[0m"
    puts "\e[34m"
    puts "  ╔═╗╦╔═╔═╗╔═╗  ╔═╗╔═╗╦═╗╦   ╦╔═╗╦═╗"
    puts "  ║╣ ╠╩╗╚═╗╠═╣  ╚═╗║╣ ╠╦╝╚╗ ╔╝║╣ ╠╦╝"
    puts "  ╚═╝╩ ╩╚═╝╩ ╩  ╚═╝╚═╝╩╚═ ╚═╝ ╚═╝╩╚═"
    puts "\e[0m"
    puts "  \e[90mPowered by nio4r | Modular High-Performance Engine\e[0m"
  end

  def print_server_info
    puts "\n  \e[1mKONFIGURASI SERVER:\e[0m"
    @binder.listeners.each do |io, type|
       puts "  \e[36m•\e[0m Bind [#{type.upcase}]: \e[33m#{io.local_address.inspect_sockaddr}\e[0m"
    end
    puts "  \e[36m•\e[0m Threads: \e[33m#{@options[:min_threads]}..#{@options[:max_threads]}\e[0m"
    puts "  \e[36m•\e[0m Workers: \e[33m#{@options[:workers]} (#{@options[:workers] > 0 ? 'Cluster' : 'Single'} Mode)\e[0m"
    puts "  \e[36m•\e[0m Control: \e[33mlocalhost:#{@options[:control_port]}\e[0m\n\n"
  end
end

if __FILE__ == $0
  # Default ke config.ru di direktori saat ini
  app_path = ARGV[0] || "config.ru"
  
  app = if File.exist?(app_path)
    app_path
  else
    proc { |env| 
      [404, {"Content-Type" => "text/html"}, ["<h1>Aplikasi tidak ditemukan di #{Dir.pwd}/#{app_path}</h1><p>Silakan buat file config.ru atau masukkan path sebagai argumen.</p>"]] 
    }
  end

  EksaServerCore.new(app).start
end
