# lib/eksa_server/http.rb
require 'stringio'

module EksaServer
  class Request
    attr_reader :env

    def initialize(client, options = {})
      @client = client
      @options = options
      @env = parse_request
    end

    private

    def parse_request
      lines = []
      while (line = @client.gets) && line != "\r\n"
        lines << line.chomp
      end
      return nil if lines.empty?

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
        'rack.errors'       => $stderr,
        'rack.multithread'  => true,
        'rack.multiprocess' => @options[:workers] > 0,
        'rack.run_once'     => false
      }

      headers.each do |k, v|
        key = k.upcase.gsub('-', '_')
        if key == 'CONTENT_TYPE' || key == 'CONTENT_LENGTH'
          env[key] = v
        else
          env["HTTP_#{key}"] = v
        end
      end

      # Read body if Content-Length is present
      content_length = env['CONTENT_LENGTH'].to_i
      body = content_length > 0 ? @client.read(content_length) : ""
      env['rack.input'] = StringIO.new(body)

      env
    end
  end

  class Response
    def self.send_response(client, status, headers, body)
      response = "HTTP/1.1 #{status} OK\r\n"
      headers.each { |k, v| response << "#{k}: #{v}\r\n" }
      
      full_body = ""
      body = [body] unless body.respond_to?(:each)
      body.each { |chunk| full_body << chunk }
      body.close if body.respond_to?(:close)

      response << "Content-Length: #{full_body.bytesize}\r\n\r\n"
      response << full_body

      client.write(response)
    end
  end
end
