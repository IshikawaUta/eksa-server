# lib/eksa_server/binder.rb
require 'socket'
require 'openssl'
require 'fileutils'

module EksaServer
  class Binder
    attr_reader :listeners

    def initialize(events)
      @events = events
      @listeners = []
    end

    def add_tcp_listener(host, port, options = {})
      @events.info "Mendengarkan di TCP: #{host}:#{port} (SSL: #{!!options[:ssl]})"
      server = TCPServer.new(host, port)
      server.setsockopt(:SOCKET, :REUSEADDR, true)
      
      if options[:ssl] && options[:cert] && options[:key]
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.cert = OpenSSL::X509::Certificate.new(File.read(options[:cert]))
        ctx.key = OpenSSL::PKey::RSA.new(File.read(options[:key]))
        @listeners << [OpenSSL::SSL::SSLServer.new(server, ctx), :tcp_ssl]
      else
        @listeners << [server, :tcp]
      end
    end

    def add_unix_listener(path)
      @events.info "Mendengarkan di Unix Socket: #{path}"
      FileUtils.rm_f(path)
      server = UNIXServer.new(path)
      @listeners << [server, :unix]
    end

    def close
      @listeners.each do |io, type|
        io.close rescue nil
        if type == :unix
          File.delete(io.path) rescue nil
        end
      end
    end
    
    def ios
      @listeners.map(&:first)
    end
  end
end
