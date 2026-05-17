# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    class PaginationLimit
      def initialize(app, max = 100)
        @app = app
        @max = max
      end

      def call(env)
        request = env["a2a.request"]
        ps = request.page_size
        ps = ps.to_i if ps
        ps = @max if ps.nil? || ps < 1 || ps > @max
        env["a2a.page_size"] = ps
        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::PaginationLimit" do
    it "defaults to max when page_size is nil" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new({})
      env = { "a2a.request" => request }

      mw = A2A::Middleware::PaginationLimit.new(app, 50)
      result = mw.call(env)
      result["a2a.page_size"].should == 50
    end

    it "clamps page_size to max" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(page_size: 200)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::PaginationLimit.new(app, 50)
      result = mw.call(env)
      result["a2a.page_size"].should == 50
    end

    it "passes through valid page_size" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(page_size: 25)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::PaginationLimit.new(app, 50)
      result = mw.call(env)
      result["a2a.page_size"].should == 25
    end

    it "clamps page_size < 1 to max" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(page_size: 0)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::PaginationLimit.new(app, 50)
      result = mw.call(env)
      result["a2a.page_size"].should == 50
    end

    it "uses custom max" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(page_size: 30)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::PaginationLimit.new(app, 20)
      result = mw.call(env)
      result["a2a.page_size"].should == 20
    end
  end
end
