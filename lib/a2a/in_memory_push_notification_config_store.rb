# frozen_string_literal: true

require "a2a/push_notification_config_store"

module A2A
  class InMemoryPushNotificationConfigStore < PushNotificationConfigStore
    def set_info(task_id, notification_config, context)
    end

    def get_info(task_id, context)
    end

    def get_info_for_dispatch(task_id)
    end

    def delete_info(task_id, context, config_id: nil)
    end
  end
end
