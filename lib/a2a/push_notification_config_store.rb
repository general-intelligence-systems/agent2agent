# frozen_string_literal: true

require "console"

module A2A
  # Interface for storing and retrieving push notification
  # configurations for tasks.
  class PushNotificationConfigStore
    def set_info(task_id, notification_config, context)
      raise NotImplementedError
    end

    def get_info(task_id, context)
      raise NotImplementedError
    end

    def get_info_for_dispatch(task_id)
      Console.warn(self) {
        "#{self.class.name} does not override " \
        "PushNotificationConfigStore#get_info_for_dispatch; falling back " \
        "to a context-less get_info call which silently drops " \
        "notifications in any deployment with multiple owners. Override " \
        "get_info_for_dispatch to return all configs for task_id across " \
        "every owner."
      }
      get_info(task_id, nil)
    end

    def delete_info(task_id, context, config_id: nil)
      raise NotImplementedError
    end
  end
end
