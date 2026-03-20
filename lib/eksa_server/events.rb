# lib/eksa_server/events.rb
require 'logger'

module EksaServer
  class Events
    def initialize(stdout, stderr)
      @stdout = stdout
      @stderr = stderr
      @logger = setup_logger
    end

    def info(msg)
      @logger.info msg
    end

    def error(msg)
      @logger.error msg
    end

    def warn(msg)
      @logger.warn msg
    end

    def debug(msg)
      @logger.debug msg
    end

    def write(msg)
      @stdout.puts msg
    end

    private

    def setup_logger
      logger = Logger.new(@stdout)
      logger.formatter = proc do |severity, datetime, _, msg|
        time = datetime.strftime('%H:%M:%S')
        case severity
        when "INFO"
          "\e[34m[#{time}] ℹ INFO  [PID:#{Process.pid}]: #{msg}\e[0m\n"
        when "ERROR"
          "\e[31m[#{time}] ✘ GAGAL [PID:#{Process.pid}]: \e[1m#{msg}\e[0m\n"
        when "WARN"
          "\e[33m[#{time}] ‼ PERINGATAN [PID:#{Process.pid}]: #{msg}\e[0m\n"
        else
          "[#{time}] #{severity}: #{msg}\n"
        end
      end
      logger
    end
  end
end
