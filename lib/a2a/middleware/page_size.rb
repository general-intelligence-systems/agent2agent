# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Clamps `request.page_size` to a valid range and sets
    # `env["a2a.page_size"]` for downstream handlers.
    #
    # Defaults to 50. Clamps to [1, max] (default max: 100).
    #
    # Usage:
    #
    #   on "ListTasks" do
    #     use A2A::Middleware::PageSize
    #     respond_with -> (env) {
    #       page_size = env["a2a.page_size"]
    #       # ...
    #     }
    #   end
    #
    #   # Custom default and max:
    #   on "ListTasks" do
    #     use A2A::Middleware::PageSize, default: 25, max: 50
    #     respond_with -> (env) { ... }
    #   end
    #
    class PageSize
      def initialize(app, default: 50, max: 100)
        @app     = app
        @default = default
        @max     = max
      end

      def call(env)
        request = env["a2a.request"]

        page_size = @default
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

test do
  describe "A2A::Middleware::PageSize" do
    it "uses the default page size when not specified" do
      request = Object.new
      request.define_singleton_method(:page_size) { nil }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 50
    end

    it "uses a custom default" do
      request = Object.new
      request.define_singleton_method(:page_size) { nil }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream, default: 25)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 25
    end

    it "clamps to minimum of 1" do
      request = Object.new
      request.define_singleton_method(:page_size) { 0 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 1
    end

    it "clamps to the max" do
      request = Object.new
      request.define_singleton_method(:page_size) { 999 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 100
    end

    it "clamps to a custom max" do
      request = Object.new
      request.define_singleton_method(:page_size) { 999 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream, max: 50)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 50
    end

    it "passes through a valid page size" do
      request = Object.new
      request.define_singleton_method(:page_size) { 30 }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 30
    end

    it "handles string values" do
      request = Object.new
      request.define_singleton_method(:page_size) { "20" }

      downstream = -> (env) { env["a2a.page_size"] }
      mw = A2A::Middleware::PageSize.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 20
    end
  end
end
