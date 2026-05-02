# frozen_string_literal: true

require_relative 'lib/a2a/version'

Gem::Specification.new do |spec|
  spec.name          = 'agent2agent'
  spec.version       = A2A::VERSION
  spec.authors       = ['A2A Contributors']
  spec.summary       = 'Agent2Agent protocol'
  spec.description   = 'Abstraction to help work with A2A protocol'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata = {
    "documentation_uri" => "https://general-intelligence-systems.github.io/agent2agent/",
  }

  spec.files         = Dir['lib/**/*.rb', 'lib/**/*.txt', 'data/**/*', 'config/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'async'
  spec.add_dependency 'async-http', "~> 0.95"
  spec.add_dependency 'protocol-http', "~> 0.62"
  spec.add_dependency 'scampi'
  spec.add_dependency 'rack', "~> 3.0"
  spec.add_dependency "json_schemer", "~> 2.5"
  spec.add_dependency "google-protobuf", "~> 4.34"
  spec.add_dependency "sqlite3"

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'falcon', '~> 0.55'
end
