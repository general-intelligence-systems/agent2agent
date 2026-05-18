# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "a2a/middleware"
require "console"
require "securerandom"
require "async"
require "yaml"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# ─── Helpers ──────────────────────────────────────────────────────────

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

terminal_states = A2A::Store::SQLite::TERMINAL_STATES

# ─── Store + Processor ────────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "webhook_worker.db")
processor    = A2A::Store::Processor.new

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A::Agent.new do

  # ── SendMessage ──────────────────────────────────────────────────────
  #
  # Always returns immediately (SUBMITTED). Work runs in background.
  # Push notification configs (inline or CRUD) receive webhook POSTs
  # for each state transition and artifact.
  #
  on "SendMessage" do
    use A2A::Middleware::ExtractMessage
    respond_with -> (env) {
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

      sqlite_store.create(task_id, context_id, push_config)
      sqlite_store.add_message(task_id, {
        "messageId" => msg.message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })

      # Process in background — each state change triggers webhook delivery
      processor.call do
        sqlite_store.update_state(task_id, "TASK_STATE_WORKING", message: {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Starting work on: #{text}" }],
        })

        sleep 1

        sqlite_store.update_state(task_id, "TASK_STATE_WORKING", message: {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Processing... 50% complete" }],
        })

        sleep 1

        artifact = {
          "artifactId" => SecureRandom.uuid,
          "name"       => "result",
          "parts"      => [{ "text" => "Result for: #{text}\n\nProcessed successfully via webhook worker." }],
        }
        sqlite_store.add_artifact(task_id, artifact)

        sqlite_store.add_message(task_id, {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Work complete." }],
        })

        sqlite_store.complete(task_id, nil)
      end

      # Return immediately with SUBMITTED state
      task = sqlite_store.get(task_id)
      A2A::Schema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        }
      )
    }
  end

  # ── GetTask ──────────────────────────────────────────────────────────
  on "GetTask" do
    use A2A::Middleware::FetchTask, store: sqlite_store
    respond_with -> (env) {
      task = env["a2a.task"]

      A2A::Schema["Task"].new(
        id:         task[:id],
        context_id: task[:context_id],
        status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
        artifacts:  task[:artifacts],
        history:    task[:history],
      )
    }
  end

  # ── Push Notification Config CRUD ────────────────────────────────────

  on "CreateTaskPushNotificationConfig" do
    use A2A::Middleware::FetchTask, store: sqlite_store, id_field: :task_id
    respond_with -> (env) {
      request = env["a2a.request"]
      task_id = env["a2a.task"][:id]

      config_data = request.to_h
      config_data.delete("taskId")
      config_data.delete("tenant")

      result = sqlite_store.create_push_config(task_id, config_data)
      A2A::Schema["Task Push Notification Config"].new(result)
    }
  end

  on "GetTaskPushNotificationConfig" do
    use A2A::Middleware::FetchTask, store: sqlite_store, id_field: :task_id
    respond_with -> (env) {
      request   = env["a2a.request"]
      task_id   = env["a2a.task"][:id]
      config_id = request.id

      config = sqlite_store.get_push_config(task_id, config_id)
      raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id) unless config

      A2A::Schema["Task Push Notification Config"].new(config)
    }
  end

  on "ListTaskPushNotificationConfigs" do
    use A2A::Middleware::FetchTask, store: sqlite_store, id_field: :task_id
    respond_with -> (env) {
      task_id = env["a2a.task"][:id]

      configs = sqlite_store.list_push_configs(task_id)
      A2A::Schema["List Task Push Notification Configs Response"].new(
        configs:         configs,
        next_page_token: "",
      )
    }
  end

  on "DeleteTaskPushNotificationConfig" do
    use A2A::Middleware::FetchTask, store: sqlite_store, id_field: :task_id
    respond_with -> (env) {
      request   = env["a2a.request"]
      task_id   = env["a2a.task"][:id]
      config_id = request.id

      sqlite_store.delete_push_config(task_id, config_id)
      nil
    }
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Webhook Worker starting..." }
Console.info(self) { "Push notifications example: async processing + webhook delivery" }

run app
