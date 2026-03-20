# lib/eksa_server/configuration.rb
require_relative 'dsl'

module EksaServer
  class Configuration
    attr_reader :options

    def initialize(user_options = {})
      @options = default_options.merge(user_options)
    end

    def load_config(path)
      return unless File.exist?(path)
      dsl = DSL.new(@options)
      dsl.instance_eval(File.read(path), path)
    end

    private

    def default_options
      {
        host: '0.0.0.0',
        port: 3000,
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
