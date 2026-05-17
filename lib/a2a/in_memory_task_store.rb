# frozen_string_literal: true

require "a2a/task_store"

module A2A
  class InMemoryTaskStore < TaskStore
    def save(task, context)
    end

    def get(task_id, context)
    end

    def list(params, context)
    end

    def delete(task_id, context)
    end
  end
end
