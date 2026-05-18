# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Loads a task from the store and places it on `env["a2a.task"]`.
    # Raises `A2A::TaskNotFoundError` if the task does not exist.
    #
    # The task ID is read from the request — by default from `request.id`,
    # or from `request.task_id` when `id_field: :task_id` is specified.
    #
    # Usage:
    #
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store
    #     respond_with -> (env) {
    #       task = env["a2a.task"]
    #       A2A::Schema["Task"].new(...)
    #     }
    #   end
    #
    #   # For push notification config operations (task_id field):
    #   on "GetTaskPushNotificationConfig" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store, id_field: :task_id
    #     respond_with -> (env) { ... }
    #   end
    #
    class FetchTask
      def initialize(app, store:, id_field: :id)
        @app      = app
        @store    = store
        @id_field = id_field
      end

      def call(env)
        request = env["a2a.request"]
        id = request.public_send(@id_field)

        task = @store.get(id)
        raise A2A::TaskNotFoundError.new(id) unless task

        env["a2a.task"] = task

        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::FetchTask" do
    before do
      @store = Object.new
    end

    it "loads a task into env[\"a2a.task\"] and calls downstream" do
      task_data = { id: "t-1", state: "TASK_STATE_COMPLETED" }
      @store.define_singleton_method(:get) { |id| id == "t-1" ? task_data : nil }

      request = Object.new
      request.define_singleton_method(:id) { "t-1" }

      downstream = -> (env) { env["a2a.task"] }

      mw = A2A::Middleware::FetchTask.new(downstream, store: @store)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == task_data
    end

    it "raises TaskNotFoundError when task does not exist" do
      @store.define_singleton_method(:get) { |id| nil }

      request = Object.new
      request.define_singleton_method(:id) { "missing" }

      downstream = -> (env) { :should_not_reach }

      mw = A2A::Middleware::FetchTask.new(downstream, store: @store)
      env = { "a2a.request" => request }

      lambda { mw.call(env) }.should.raise(A2A::TaskNotFoundError)
    end

    it "reads task_id when id_field: :task_id is specified" do
      task_data = { id: "t-2", state: "TASK_STATE_WORKING" }
      @store.define_singleton_method(:get) { |id| id == "t-2" ? task_data : nil }

      request = Object.new
      request.define_singleton_method(:task_id) { "t-2" }

      downstream = -> (env) { env["a2a.task"] }

      mw = A2A::Middleware::FetchTask.new(downstream, store: @store, id_field: :task_id)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == task_data
    end
  end
end
