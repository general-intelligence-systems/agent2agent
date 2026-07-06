# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    module Middleware
      # Loads a task from the store and places it on `env["a2a.task"]`.
      # Sets `env["a2a.task"]` to nil when the ID is absent or the task
      # does not exist. Does not raise.
      #
      # The task ID is read from the request — by default from `request.id`.
      # Use `id_field:` to read from a different field, and `from:` to
      # read from a nested object on the request.
      #
      # Not part of the default A2A::Server stack (it needs a store, and
      # the ID field varies per operation) — wrap your agent with it:
      #
      #   agent = A2A::Server::Middleware::FetchTask.new(
      #     A2A.agent { |env| existing = env["a2a.task"] }, # nil if new task
      #     store: sqlite_store, id_field: :task_id, from: :message
      #   )
      #
      class FetchTask
        def initialize(app, store:, id_field: :id, from: nil)
          @app      = app
          @store    = store
          @id_field = id_field
          @from     = from
        end

        def call(env)
          request = env["a2a.request"]
          source  = @from ? request.public_send(@from) : request
          id      = source.public_send(@id_field)

          env["a2a.task"] = id.to_s.empty? ? nil : @store.get(id)

          @app.call(env)
        end
      end

      # Loads a task from the store and places it on `env["a2a.task"]`.
      # Raises `A2A::TaskNotFoundError` if the task does not exist.
      #
      # The task ID is read from the request — by default from `request.id`.
      # Use `id_field:` to read from a different field, and `from:` to
      # read from a nested object on the request.
      #
      # Not part of the default A2A::Server stack — wrap your agent with it:
      #
      #   agent = A2A::Server::Middleware::FetchTaskOrRaise.new(
      #     A2A.agent { |env| task = env["a2a.task"] },
      #     store: sqlite_store
      #   )
      #
      class FetchTaskOrRaise
        def initialize(app, store:, id_field: :id, from: nil)
          @app      = app
          @store    = store
          @id_field = id_field
          @from     = from
        end

        def call(env)
          request = env["a2a.request"]
          source  = @from ? request.public_send(@from) : request
          id      = source.public_send(@id_field)

          task = @store.get(id)
          raise A2A::TaskNotFoundError.new(id) unless task

          env["a2a.task"] = task

          @app.call(env)
        end
      end
    end
end
end

__END__
  describe "A2A::Server::Middleware::FetchTask" do
    before do
      @store = Object.new
    end

    it "sets env[\"a2a.task\"] when task exists" do
      task_data = { id: "t-1", state: "TASK_STATE_COMPLETED" }
      @store.define_singleton_method(:get) { |id| id == "t-1" ? task_data : nil }

      request = Object.new
      request.define_singleton_method(:id) { "t-1" }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTask.new(downstream, store: @store)
      env = { "a2a.request" => request }

      mw.call(env).should == task_data
    end

    it "sets env[\"a2a.task\"] to nil when task does not exist" do
      @store.define_singleton_method(:get) { |id| nil }

      request = Object.new
      request.define_singleton_method(:id) { "missing" }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTask.new(downstream, store: @store)
      env = { "a2a.request" => request }

      mw.call(env).should.be.nil
    end

    it "sets env[\"a2a.task\"] to nil when id is empty" do
      request = Object.new
      request.define_singleton_method(:id) { "" }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTask.new(downstream, store: @store)
      env = { "a2a.request" => request }

      mw.call(env).should.be.nil
    end

    it "sets env[\"a2a.task\"] to nil when id is nil" do
      message = Object.new
      message.define_singleton_method(:task_id) { nil }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTask.new(downstream, store: @store, id_field: :task_id, from: :message)
      env = { "a2a.request" => request }

      mw.call(env).should.be.nil
    end

    it "reads id from a nested object via from:" do
      task_data = { id: "t-2", state: "TASK_STATE_WORKING" }
      @store.define_singleton_method(:get) { |id| id == "t-2" ? task_data : nil }

      message = Object.new
      message.define_singleton_method(:task_id) { "t-2" }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTask.new(downstream, store: @store, id_field: :task_id, from: :message)
      env = { "a2a.request" => request }

      mw.call(env).should == task_data
    end
  end

  describe "A2A::Server::Middleware::FetchTaskOrRaise" do
    before do
      @store = Object.new
    end

    it "sets env[\"a2a.task\"] when task exists" do
      task_data = { id: "t-1", state: "TASK_STATE_COMPLETED" }
      @store.define_singleton_method(:get) { |id| id == "t-1" ? task_data : nil }

      request = Object.new
      request.define_singleton_method(:id) { "t-1" }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTaskOrRaise.new(downstream, store: @store)
      env = { "a2a.request" => request }

      mw.call(env).should == task_data
    end

    it "raises TaskNotFoundError when task does not exist" do
      @store.define_singleton_method(:get) { |id| nil }

      request = Object.new
      request.define_singleton_method(:id) { "missing" }

      downstream = -> (env) { :should_not_reach }
      mw = A2A::Server::Middleware::FetchTaskOrRaise.new(downstream, store: @store)
      env = { "a2a.request" => request }

      lambda { mw.call(env) }.should.raise(A2A::TaskNotFoundError)
    end

    it "reads task_id when id_field: :task_id is specified" do
      task_data = { id: "t-2", state: "TASK_STATE_WORKING" }
      @store.define_singleton_method(:get) { |id| id == "t-2" ? task_data : nil }

      request = Object.new
      request.define_singleton_method(:task_id) { "t-2" }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTaskOrRaise.new(downstream, store: @store, id_field: :task_id)
      env = { "a2a.request" => request }

      mw.call(env).should == task_data
    end

    it "reads id from a nested object via from:" do
      task_data = { id: "t-3", state: "TASK_STATE_WORKING" }
      @store.define_singleton_method(:get) { |id| id == "t-3" ? task_data : nil }

      message = Object.new
      message.define_singleton_method(:task_id) { "t-3" }

      request = Object.new
      request.define_singleton_method(:message) { message }

      downstream = -> (env) { env["a2a.task"] }
      mw = A2A::Server::Middleware::FetchTaskOrRaise.new(downstream, store: @store, id_field: :task_id, from: :message)
      env = { "a2a.request" => request }

      mw.call(env).should == task_data
    end
  end
