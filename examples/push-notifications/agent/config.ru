# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "console"
require "securerandom"
require "async"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = {
  "name"               => "Webhook Worker",
  "description"        => "An async agent that delivers task updates via push notification webhooks.",
  "version"            => "1.0.0",
  "supportedInterfaces" => [
    {
      "url"             => "http://localhost:9292/a2a",
      "protocolBinding" => "JSONRPC",
      "protocolVersion" => "1.0",
    },
    {
      "url"             => "http://localhost:9292",
      "protocolBinding" => "HTTP+JSON",
      "protocolVersion" => "1.0",
    },
  ],
  "capabilities" => {
    "streaming"         => true,
    "pushNotifications" => true,
  },
  "defaultInputModes"  => ["text/plain"],
  "defaultOutputModes" => ["text/plain"],
  "skills" => [
    {
      "id"          => "process",
      "name"        => "Background Processor",
      "description" => "Processes tasks asynchronously and delivers updates via push notification webhooks.",
      "tags"        => ["async", "webhooks", "push-notifications"],
      "examples"    => ["Process this data", "Run analysis"],
    },
  ],
}

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message.respond_to?(:parts) ? message.parts : (message["parts"] || [])
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
}

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
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    # Extract inline push notification config from configuration
    push_config = nil
    if request.respond_to?(:configuration) && request.configuration
      cfg = request.configuration
      pnc = cfg.respond_to?(:task_push_notification_config) ? cfg.task_push_notification_config : (cfg["taskPushNotificationConfig"] || cfg["pushNotificationConfig"])
      push_config = pnc.respond_to?(:to_h) ? pnc.to_h : pnc if pnc
    end

    store.create(task_id, context_id, push_config)
    store.add_message(task_id, {
      "messageId" => (msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]) || SecureRandom.uuid,
      "role"      => "ROLE_USER",
      "parts"     => [{ "text" => text }],
    })

    # Process in background — each state change triggers webhook delivery
    # via store.update_state -> store.webhooks.deliver
    processor.call do
      store.update_state(task_id, "TASK_STATE_WORKING", message: {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Starting work on: #{text}" }],
      })

      sleep 1

      store.update_state(task_id, "TASK_STATE_WORKING", message: {
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
      store.add_artifact(task_id, artifact)

      store.add_message(task_id, {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Work complete." }],
      })

      store.complete(task_id, nil)
    end

    # Return immediately with SUBMITTED state
    task = store.get(task_id)
    respond A2A::Schema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
      }
    )
  end

  # ── GetTask ──────────────────────────────────────────────────────────
  on "GetTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    respond A2A::Schema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history],
    )
  end

  # ── Push Notification Config CRUD ────────────────────────────────────

  on "CreateTaskPushNotificationConfig" do |request|
    task_id = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    task = store.get(task_id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id.to_s } }] }
      next
    end

    config_data = request.to_h
    config_data.delete("taskId")
    config_data.delete("tenant")

    result = store.create_push_config(task_id, config_data)
    respond A2A::Schema["Task Push Notification Config"].new(result)
  end

  on "GetTaskPushNotificationConfig" do |request|
    task_id   = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    config_id = request.id

    task = store.get(task_id)
    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    config = store.get_push_config(task_id, config_id)
    unless config
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Push notification config not found" }
      next
    end

    respond A2A::Schema["Task Push Notification Config"].new(config)
  end

  on "ListTaskPushNotificationConfigs" do |request|
    task_id = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    task = store.get(task_id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    configs = store.list_push_configs(task_id)
    respond A2A::Schema["List Task Push Notification Configs Response"].new(
      configs:         configs,
      next_page_token: "",
    )
  end

  on "DeleteTaskPushNotificationConfig" do |request|
    task_id   = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    config_id = request.id

    task = store.get(task_id)
    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    store.delete_push_config(task_id, config_id)
    respond nil
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Webhook Worker starting..." }
Console.info(self) { "Push notifications example: async processing + webhook delivery" }

run app
