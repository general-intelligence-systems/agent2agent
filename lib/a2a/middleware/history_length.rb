# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Parses `request.history_length` and applies history truncation to
    # the task loaded by FetchTask.
    #
    # Sets `env["a2a.history"]`:
    #   - `nil` when history_length is 0 (exclude history)
    #   - truncated array when history_length > 0
    #   - full history when history_length is not specified
    #
    # Should be placed after FetchTask in the middleware stack so that
    # `env["a2a.task"]` is available.
    #
    # Usage:
    #
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store
    #     use A2A::Middleware::HistoryLength
    #     respond_with -> (env) {
    #       task = env["a2a.task"]
    #       history = env["a2a.history"]
    #       # ...
    #     }
    #   end
    #
    class HistoryLength
      def initialize(app)
        @app = app
      end

      def call(env)
        request = env["a2a.request"]
        task    = env["a2a.task"]
        history = task ? task[:history] : nil

        if request.respond_to?(:history_length) && request.history_length
          hl = request.history_length.to_i
          history = if hl == 0
            nil
          else
            history&.last(hl)
          end
        end

        env["a2a.history"] = history

        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::HistoryLength" do
    it "passes full history when history_length is not specified" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      history = [{ "role" => "user" }, { "role" => "agent" }, { "role" => "user" }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::HistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == history
    end

    it "returns nil when history_length is 0" do
      request = Object.new
      request.define_singleton_method(:history_length) { 0 }

      task = { history: [{ "role" => "user" }] }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::HistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should.be.nil
    end

    it "truncates history to the last N entries" do
      request = Object.new
      request.define_singleton_method(:history_length) { 2 }

      history = [{ "m" => 1 }, { "m" => 2 }, { "m" => 3 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::HistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 2 }, { "m" => 3 }]
    end

    it "handles string history_length values" do
      request = Object.new
      request.define_singleton_method(:history_length) { "1" }

      history = [{ "m" => 1 }, { "m" => 2 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::HistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 2 }]
    end
  end
end
