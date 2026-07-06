# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    module Middleware
      # Clamps `request.page_size` to a valid range and sets
      # `env["a2a.page_size"]` for the agent.
      #
      # Accepts a single integer — the maximum page size (also used as the
      # default when the client doesn't specify one). Clamps to [1, max].
      #
      # Part of the A2A::Server middleware stack — the max comes from
      # `A2A::Server.new(page_size: 50)`.
      #
      class LimitPaginationSize
        def initialize(app, max = 100)
          @app = app
          @max = max
        end

        def call(env)
          request = env["a2a.request"]

          page_size = @max
          if request.respond_to?(:page_size) && request.page_size
            ps = request.page_size.to_i
            page_size = [[ps, 1].max, @max].min
          end

          env["a2a.page_size"] = page_size

          @app.call(env)
        end
      end
    end
end
end

__END__
  describe "A2A::Server::Middleware::LimitPaginationSize" do
    it "uses max as default page size when not specified by client" do
      request = Object.new
      request.define_singleton_method(:page_size) { nil }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 100
    end

    it "uses a custom max as the default" do
      request = Object.new
      request.define_singleton_method(:page_size) { nil }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream, 25)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 25
    end

    it "clamps to minimum of 1" do
      request = Object.new
      request.define_singleton_method(:page_size) { 0 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 1
    end

    it "clamps to the max" do
      request = Object.new
      request.define_singleton_method(:page_size) { 999 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 100
    end

    it "clamps to a custom max" do
      request = Object.new
      request.define_singleton_method(:page_size) { 999 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream, 50)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 50
    end

    it "passes through a valid page size" do
      request = Object.new
      request.define_singleton_method(:page_size) { 30 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 30
    end

    it "handles string values" do
      request = Object.new
      request.define_singleton_method(:page_size) { "20" }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Server::Middleware::LimitPaginationSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 20
    end
  end
