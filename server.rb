# server.rb
require 'nio'
require 'socket'
require 'thread'
require 'json'
require 'fileutils'
require 'openssl'
require 'stringio'
require 'rack'
require 'rackup'

# Load Modular Core
require_relative 'lib/eksa_server/events'
require_relative 'lib/eksa_server/binder'
require_relative 'lib/eksa_server/thread_pool'
require_relative 'lib/eksa_server/configuration'
require_relative 'lib/eksa_server/http'
require_relative 'lib/eksa_server/version'

class EksaServerCore
  def initialize(app, user_options = {})
    @app_path_or_obj = app.is_a?(String) ? File.expand_path(app) : app
    @config = EksaServer::Configuration.new
    @signal_queue = []
    @project_root = Dir.pwd
    
    # 1. Load optional config file (priority paling rendah)
    if File.exist?('config/eksa_server.rb')
      @config.load_config('config/eksa_server.rb')
    end

    # 2. Muat .env (menimpa config file jika ada variabelnya)
    @config.load_env

    # 3. Gabungkan user_options dari CLI (priority paling tinggi)
    # Jika user memberikan port/host secara eksplisit di CLI atau ada di ENV,
    # kita prioritaskan itu dan kosongkan binds agar tidak tumpang tindih.
    cli_port = user_options[:port] || user_options[:host]
    if cli_port || ENV['PORT'] || ENV['HOST']
      @config.options[:binds] = []
      @config.options[:port] = (user_options[:port] || ENV['PORT'] || @config.options[:port]).to_i
      @config.options[:host] = user_options[:host] || ENV['HOST'] || @config.options[:host]
    end
    @config.merge!(user_options.compact)
    
    # Expand paths to absolute versions before load_app changes Dir.chdir
    [:cert, :key, :log_file].each do |opt|
      if @config.options[opt] && @config.options[opt].is_a?(String)
        @config.options[opt] = File.expand_path(@config.options[opt])
      end
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
    if @options[:daemonize]
      @events.info "Berjalan di latar belakang (Daemon Mode)..."
      Process.daemon(true, true)
    end

    if @options[:log_file]
      log_file = File.open(@options[:log_file], 'a')
      log_file.sync = true
      @events.reopen(log_file)
    end

    start_reloader if @options[:reload]

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

    trap('INT') { @signal_queue << :TERM }
    trap('TERM') { @signal_queue << :TERM }
    trap('USR2') { @signal_queue << :USR2 }

    loop do
      case @signal_queue.shift
      when :TERM
        terminate_all
      when :USR2
        phased_restart
      end

      check_workers
      sleep 1
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
    @app = load_app(@app_path_or_obj)
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

    # Signal handling untuk single-worker mode
    if @options[:workers] == 0
      trap('INT') { @signal_queue << :TERM }
      trap('TERM') { @signal_queue << :TERM }
    end

    Thread.new do
      loop do
        begin
          if File.directory?(@hb_dir)
            FileUtils.touch("#{@hb_dir}/#{Process.pid}.hb")
          end
        rescue
          # Abaikan error saat shutdown
        end
        sleep 5
      end
    end

    loop do
      if @signal_queue.include?(:TERM)
        @events.info "Worker #{id} berhenti..."
        break
      end

      @selector.select(1) do |monitor|
        if monitor.value == :accept
          begin
            if monitor.io.respond_to?(:accept_nonblock)
              client = monitor.io.accept_nonblock
            else
              client = monitor.io.accept
            end
            @selector.register(client, :r).value = :read
          rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET => e
            @events.warn "Gagal jabat tangan SSL/Koneksi terputus: #{e.message}"
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
    request = EksaServer::Request.new(client, @options)
    env = request.env
    return client.close unless env

    # Panggil aplikasi Rack
    begin
      status, res_headers, res_body = @app.call(env)
    rescue => e
      @events.error "Aplikasi gagal merespons: #{e.message}"
      status = 500
      res_headers = { "Content-Type" => "text/html" }
      res_body = [render_error_page(e)]
    end
    
    # Kirim Response
    EksaServer::Response.send_response(client, status, res_headers, res_body)
    
    @events.info "Selesai: #{env['REQUEST_METHOD']} #{env['PATH_INFO']} -> #{status} (Threads: #{@thread_pool.spawned})"
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

  def start_reloader
    @events.info "Pemuatan otomatis (Auto-Reload) aktif. 👀"
    Thread.new do
      # Pantau file di project root agar mencakup lib dan server.rb
      loop do
        sleep 2
        changed = false
        files = Dir.chdir(@project_root) { Dir["**/*.{rb,ru}"] }
        
        @mtimes ||= {}
        files.each do |f|
          full_path = File.join(@project_root, f)
          current_mtime = File.mtime(full_path) rescue next
          if @mtimes[f] && @mtimes[f] != current_mtime
            @events.warn "Perubahan terdeteksi di #{f}. Me-restart..."
            changed = true
          end
          @mtimes[f] = current_mtime
        end

        if changed
          if @options[:workers] > 0
            @signal_queue << :USR2
          else
            @signal_queue << :TERM
          end
        end
      end
    end
  end

  def start_control_server
    return if @options[:control_port] == false || @options[:control_port] == nil
    start_time = Time.now
    Thread.new do
      begin
        # Jika port 0, OS akan memilih port acak
        server = TCPServer.new('127.0.0.1', @options[:control_port])
        actual_port = server.addr[1]
        @events.info "Control Server aktif di http://localhost:#{actual_port}" if @options[:control_port] == 0
        
        loop do
          client = server.accept
          uptime = (Time.now - start_time).to_i
          
          # Hitung memori (RSS) di Linux
          mem = `ps -o rss= -p #{Process.pid}`.strip.to_i rescue 0
          
          stats = { 
            workers: @worker_pids.size, 
            uptime: uptime,
            version: EksaServer::VERSION,
            memory_kb: mem,
            threads: { spawned: @thread_pool&.spawned, waiting: @thread_pool&.waiting }
          }.to_json
          client.puts "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n#{stats}"
          client.close
        end
      rescue => e
        @events.error "Control Server Gagal di port #{@options[:control_port]}: #{e.message}"
      end
    end
  end

  def cleanup
    @binder&.close
    FileUtils.rm_rf(@hb_dir)
  end

  def print_banner
    puts "\e[34m"
    puts "  \e[1mEKSA SERVER v#{EksaServer::VERSION} \e[0m- \e[90mBy: IshikawaUta\e[0m"
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
       # SSLServer tidak punya local_address langsung, panggil to_io
       sock = io.respond_to?(:local_address) ? io : io.to_io
       puts "  \e[36m•\e[0m Bind [#{type.upcase}]: \e[33m#{sock.local_address.inspect_sockaddr}\e[0m"
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
