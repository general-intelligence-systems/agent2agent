# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server/sse"
require "async/semaphore"
require "console"
require "securerandom"
require "async"
require "yaml"

# --- Agent Card ---

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# --- Helpers ---

NOW = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze

# --- Store ---

TASKS = {}
LOCK  = Async::Semaphore.new(1)

# --- Agent ---

agent = A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]

  # -- SendMessage ---
  #
  # Always returns immediately (SUBMITTED). Work runs in background.
  # Push notification configs (inline or CRUD) receive webhook POSTs
  # for each state transition and artifact.
  #
  in "SendMessage"
    request = env["a2a.request"]
    msg = request.message
    text = env["a2a.message"]

    context_id = msg.context_id
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    # Extract inline push notification config from configuration
    push_config = nil
    if request.configuration
      cfg = request.configuration
      pnc = cfg.task_push_notification_config
      push_config = pnc if pnc
    end

    LOCK.acquire do
      TASKS[task_id] = {
        id: task_id, context_id: context_id,
        state: "TASK_STATE_SUBMITTED", updated_at: NOW.(),
        artifacts: [], history: [], push_configs: [push_config].compact,
      }
      TASKS[task_id][:history] << {
        "messageId" => msg.message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      }
    end

    # Process in background
    Async do
      LOCK.acquire do
        TASKS[task_id][:state] = "TASK_STATE_WORKING"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id][:history] << {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Starting work on: #{text}" }],
        }
      end

      sleep 1

      LOCK.acquire do
        TASKS[task_id][:state] = "TASK_STATE_WORKING"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id][:history] << {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Processing... 50% complete" }],
        }
      end

      sleep 1

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "result",
        "parts"      => [{ "text" => "Result for: #{text}\n\nProcessed successfully via webhook worker." }],
      }

      LOCK.acquire do
        TASKS[task_id][:artifacts] << artifact
        TASKS[task_id][:history] << {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Work complete." }],
        }
        TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
        TASKS[task_id][:updated_at] = NOW.()
      end
    end

    # Return immediately with SUBMITTED state
    task = LOCK.acquire { TASKS[task_id] }
    A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
      }
    )

  # -- GetTask ---
  in "GetTask"
    request = env["a2a.request"]
    id = request.id

    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history],
    )

  # -- Push Notification Config CRUD ---

  in "CreateTaskPushNotificationConfig"
    request = env["a2a.request"]
    task_id = request.task_id

    task = LOCK.acquire { TASKS[task_id] }
    raise A2A::TaskNotFoundError.new(task_id) unless task

    config_data = request.to_h
    config_data.delete("taskId")
    config_data.delete("tenant")
    config_data["id"] ||= SecureRandom.uuid

    LOCK.acquire { TASKS[task_id][:push_configs] << config_data }

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config_data)

  in "GetTaskPushNotificationConfig"
    request   = env["a2a.request"]
    task_id   = request.task_id
    config_id = request.id

    task = LOCK.acquire { TASKS[task_id] }
    raise A2A::TaskNotFoundError.new(task_id) unless task

    config = task[:push_configs]&.find { |c| c["id"] == config_id }
    raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id) unless config

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)

  in "ListTaskPushNotificationConfigs"
    request = env["a2a.request"]
    task_id = request.task_id

    task = LOCK.acquire { TASKS[task_id] }
    raise A2A::TaskNotFoundError.new(task_id) unless task

    A2A::Protocol::JsonSchema["List Task Push Notification Configs Response"].new(
      configs:         task[:push_configs] || [],
      next_page_token: "",
    )

  in "DeleteTaskPushNotificationConfig"
    request   = env["a2a.request"]
    task_id   = request.task_id
    config_id = request.id

    task = LOCK.acquire { TASKS[task_id] }
    raise A2A::TaskNotFoundError.new(task_id) unless task

    LOCK.acquire { TASKS[task_id][:push_configs]&.reject! { |c| c["id"] == config_id } }
    nil
  end
end

# --- Boot ---

Console.info(self) { "Webhook Worker starting..." }
Console.info(self) { "Push notifications example: async processing + webhook delivery" }

run agent
