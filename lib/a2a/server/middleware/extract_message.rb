# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    module Middleware
      # Extracts text from the request message's parts and sets
      # `env["a2a.message"]` to the joined text string.
      #
      # Part of the A2A::Server middleware stack. Requests whose
      # operation carries no message pass through untouched, so
      # env["a2a.message"] is only present when a message is.
      #
      # Replaces the common `extract_text` lambda pattern found in examples:
      #
      #   extract_text = ->(message) {
      #     parts = message.parts || []
      #     parts.filter_map { |p| p.text }.join("\n")
      #   }
      #
      class ExtractMessage
        def initialize(app)
          @app = app
        end

        def call(env)
          request = env["a2a.request"]

          if request.respond_to?(:message) && (message = request.message)
            parts = message.parts || []

            env["a2a.message"] = parts.filter_map { |p|
              p.respond_to?(:text) ? p.text : p["text"]
            }.join("\n")
          end

          @app.call(env)
        end
      end
    end
end
end

__END__
  describe "A2A::Server::Middleware::ExtractMessage" do
    it "extracts text from message parts" do
      part1 = Object.new
      part1.define_singleton_method(:text) { "hello" }
      part2 = Object.new
      part2.define_singleton_method(:text) { "world" }

      message = Object.new
      message.define_singleton_method(:parts) { [part1, part2] }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.message"] }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == "hello\nworld"
    end

    it "handles nil parts" do
      message = Object.new
      message.define_singleton_method(:parts) { nil }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.message"] }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == ""
    end

    it "skips parts without text" do
      part1 = Object.new
      part1.define_singleton_method(:text) { "hello" }
      part2 = Object.new
      part2.define_singleton_method(:text) { nil }

      message = Object.new
      message.define_singleton_method(:parts) { [part1, part2] }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.message"] }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == "hello"
    end

    it "handles hash-style parts" do
      message = Object.new
      message.define_singleton_method(:parts) { [{ "text" => "from hash" }] }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.message"] }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == "from hash"
    end

    it "passes through when the request has no message reader" do
      request = Object.new

      downstream = -> (env) { env.key?("a2a.message") }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      mw.call(env).should == false
    end

    it "passes through when the message is nil" do
      request = Object.new
      request.define_singleton_method(:message) { nil }

      downstream = -> (env) { env.key?("a2a.message") }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)
      env = { "a2a.request" => request }

      mw.call(env).should == false
    end

    it "passes through when there is no request" do
      downstream = -> (env) { env.key?("a2a.message") }
      mw = A2A::Server::Middleware::ExtractMessage.new(downstream)

      mw.call({}).should == false
    end
  end
