# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"
require "json"

module A2A
  module Faraday
    module Middleware
      # Faraday request middleware that converts A2A::Schema::Definition
      # objects into their hash representation for JSON serialization.
      #
      # Place this before the :json request middleware in the stack so
      # that Schema bodies are converted to hashes before Faraday's
      # JSON middleware serializes them to strings.
      #
      class SchemaRequest < ::Faraday::Middleware
        def on_request(env)
          body = env.body
          return unless body.is_a?(A2A::Schema::Definition)

          env.body = body.to_h
          env.request_headers["content-type"] ||= "application/json"
        end
      end
    end
  end
end

::Faraday::Request.register_middleware(a2a_schema: A2A::Faraday::Middleware::SchemaRequest)

test do
  middleware = A2A::Faraday::Middleware::SchemaRequest

  it "converts Schema::Definition to hash" do
    schema_obj = A2A::Schema["Agent Capabilities"].new(streaming: true)
    env = ::Faraday::Env.new
    env.body = schema_obj
    env.request_headers = {}

    middleware.new(nil).on_request(env)

    env.body.should == { "streaming" => true }
    env.request_headers["content-type"].should == "application/json"
  end

  it "does not modify non-Schema bodies" do
    env = ::Faraday::Env.new
    env.body = { "foo" => "bar" }
    env.request_headers = {}

    middleware.new(nil).on_request(env)

    env.body.should == { "foo" => "bar" }
    env.request_headers["content-type"].should.be.nil
  end

  it "does not overwrite existing content-type" do
    schema_obj = A2A::Schema["Agent Capabilities"].new(streaming: true)
    env = ::Faraday::Env.new
    env.body = schema_obj
    env.request_headers = { "content-type" => "application/a2a+json" }

    middleware.new(nil).on_request(env)

    env.request_headers["content-type"].should == "application/a2a+json"
  end
end
