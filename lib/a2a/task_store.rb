# frozen_string_literal: true

module A2A
  # Agent Task Store interface.
  #
  # Defines the methods for persisting and retrieving Task objects.
  class TaskStore
    def save(task, context)
      raise NotImplementedError
    end

    def get(task_id, context)
      raise NotImplementedError
    end

    def list(params, context)
      raise NotImplementedError
    end

    def delete(task_id, context)
      raise NotImplementedError
    end
  end
end
