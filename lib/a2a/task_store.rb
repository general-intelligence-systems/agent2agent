# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  Task = Struct.new(:id, :context_id, :state, :result, :push_config, :created_at, keyword_init: true)

  # In-memory task registry. Swap for a DB-backed implementation in production —
  # if the server crashes, in-memory tasks vanish and the client never gets notified.
  class TaskStore
    def initialize
      @tasks = {}
      @mutex = Mutex.new
    end

    def create(id, context_id, push_config)
      @mutex.synchronize do
        @tasks[id] = Task.new(
          id: id, context_id: context_id, state: "submitted",
          result: nil, push_config: push_config, created_at: Time.now.utc,
        )
      end
    end

    def get(id)                     = @mutex.synchronize { @tasks[id] }
    def update_state(id, state)     = @mutex.synchronize { @tasks[id]&.state = state }
    def complete(id, result)        = @mutex.synchronize { t = @tasks[id]; t&.state = "completed"; t&.result = result }
    def fail(id, msg)               = @mutex.synchronize { t = @tasks[id]; t&.state = "failed";    t&.result = msg }
    def cancel(id)                  = update_state(id, "canceled")
    def set_push_config(id, cfg)    = @mutex.synchronize { @tasks[id]&.push_config = cfg }
    def get_push_config(id, _cfg_id) = @mutex.synchronize { @tasks[id]&.push_config }
    def list_push_configs(id)       = @mutex.synchronize { Array(@tasks[id]&.push_config) }
    def delete_push_config(id, _)   = @mutex.synchronize { @tasks[id]&.push_config = nil }

    def list(context_id: nil, state: nil)
      @mutex.synchronize do
        @tasks.values
              .select { |t| context_id.nil? || t.context_id == context_id }
              .select { |t| state.nil?      || t.state == state }
      end
    end
  end
end
