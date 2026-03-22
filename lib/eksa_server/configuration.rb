# lib/eksa_server/configuration.rb
require_relative 'dsl'

module EksaServer
  class Configuration
    attr_reader :options

    def initialize(user_options = {})
      load_env
      @options = default_options.merge(user_options)
    end

    def load_env(path = '.env')
      return unless File.exist?(path)
      File.readlines(path).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        key, value = line.split('=', 2)
        next unless key && value
        ENV[key] ||= value.gsub(/^["']|["']$/, '') # Bersihkan quote jika ada
      end
    end

    def load_config(path)
      return unless File.exist?(path)
      dsl = DSL.new(@options)
      dsl.instance_eval(File.read(path), path)
    end

    def merge!(new_options)
      @options.merge!(new_options)
    end

    private

    def default_options
      {
        host: ENV['HOST'] || '0.0.0.0',
        port: (ENV['PORT'] || 3000).to_i,
        min_threads: 5,
        max_threads: 16,
        workers: 0,
        control_port: 3001,
        timeout: 15,
        ssl: false,
        binds: []
      }
    end
  end
end
