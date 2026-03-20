# lib/eksa_server/dsl.rb
module EksaServer
  class DSL
    def initialize(options)
      @options = options
    end

    def threads(min, max)
      @options[:min_threads] = min
      @options[:max_threads] = max
    end

    def workers(count)
      @options[:workers] = count
    end

    def bind(url)
      @options[:binds] ||= []
      @options[:binds] << url
    end

    def port(p)
      @options[:port] = p
    end

    def host(h)
      @options[:host] = h
    end

    def ssl_bind(p, cert, key)
      @options[:ssl] = true
      @options[:port] = p
      @options[:cert] = cert
      @options[:key] = key
    end

    def on_worker_boot(&block)
      @options[:on_worker_boot] = block
    end
  end
end
