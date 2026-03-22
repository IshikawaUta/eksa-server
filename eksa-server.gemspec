# eksa_server.gemspec
require_relative "lib/eksa_server/version"

Gem::Specification.new do |spec|
  spec.name          = "eksa-server"
  spec.version       = EksaServer::VERSION
  spec.authors       = ["IshikawaUta"]
  spec.email         = ["komikers09@gmail.com"]

  spec.summary       = "High Performance Asynchronous Ruby Web Server"
  spec.description   = "A modular, concurrent web server built with nio4r."
  spec.homepage      = "https://github.com/IshikawaUta/eksa-server"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "lib/**/*.html", "config/**/*.rb", "bin/*", "README.md", "LICENSE", "CONTRIBUTING.md", "server.rb"]
  end
  spec.bindir        = "bin"
  spec.executables   = ["eksa-server"]
  spec.require_paths = ["lib"]

  spec.add_dependency "nio4r", "~> 2.0"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "rackup", "~> 2.0"
  spec.add_dependency "logger", "~> 1.6"
end
