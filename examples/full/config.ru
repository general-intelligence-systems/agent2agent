# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "console"
require "securerandom"
require "async"

# ─── Agent Card (spec-compliant) ──────────────────────────────────────

agent_card = {
  "name"               => "Full Echo Agent",
  "description"        => "A2A echo agent demonstrating all 11 protocol operations.",
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
    "extendedAgentCard" => false,
  },
  "defaultInputModes"  => ["text/plain"],
  "defaultOutputModes" => ["text/plain"],
  "skills" => [
    {
      "id"          => "echo",
      "name"        => "Echo",
      "description" => "Echoes user messages back as task artifacts.",
      "tags"        => ["echo", "test"],
      "examples"    => ["Say hello", "Echo this message"],
      "inputModes"  => ["text/plain"],
      "outputModes" => ["text/plain"],
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

# ─── SQLite-backed store ──────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "echo_agent.db")

# ─── Agent: all 11 operations ────────────────────────────────────────

agent = A2A::Agent.new do

  # ── 1. SendMessage ──────────────────────────────────────────────────
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    task_id    = msg.respond_to?(:task_id)    ? msg.task_id    : msg["taskId"]
    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    message_id = msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    push_config = nil
    if request.respond_to?(:configuration) && request.configuration
      cfg = request.configuration
      pnc = cfg.respond_to?(:task_push_notification_config) ? cfg.task_push_notification_config : (cfg["taskPushNotificationConfig"] || cfg["pushNotificationConfig"])
      push_config = pnc.respond_to?(:to_h) ? pnc.to_h : pnc if pnc
    end

    if task_id && !task_id.empty?
      existing = store.get(task_id)
      unless existing
        respond nil
        @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id } }] }
        next
      end
      if terminal_states.include?(existing[:state])
        respond nil
        @env["a2a.error"] = { code: -32004, message: "Task is in a terminal state", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org" }] }
        next
      end
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })
    else
      task_id = SecureRandom.uuid
      store.create(task_id, context_id, push_config)
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })
    end

    artifact = {
      "artifactId" => SecureRandom.uuid,
      "name"       => "echo-response",
      "parts"      => [{ "text" => "Echo: #{text}" }],
    }
    store.add_artifact(task_id, artifact)

    store.add_message(task_id, {
      "messageId" => SecureRandom.uuid,
      "role"      => "ROLE_AGENT",
      "parts"     => [{ "text" => "Echo: #{text}" }],
    })

    store.complete(task_id, nil)
    task = store.get(task_id)

    respond A2A::Schema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        "artifacts" => task[:artifacts],
        "history"   => task[:history],
      }
    )
  end

  # ── 2. SendStreamingMessage ─────────────────────────────────────────
  #
  # Returns results as SSE events via Falcon-native async streaming.
  # Uses A2A::SSE::Stream (Protocol::HTTP::Body::Writable) — no threads.
  #
  on "SendStreamingMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    message_id = msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    store.create(task_id, context_id)
    store.add_message(task_id, {
      "messageId" => message_id || SecureRandom.uuid,
      "role"      => "ROLE_USER",
      "parts"     => [{ "text" => text }],
    })
    store.update_state(task_id, "TASK_STATE_WORKING")

    # Create the SSE stream — binding-aware (JsonRpc or Rest)
    s = stream

    # Emit events in a background fiber — no threads, pure async
    Async do
      sleep 0.05

      # Event 1: initial Task snapshot
      task = store.get(task_id)
      s.event({
        "task" => {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => "TASK_STATE_WORKING", "timestamp" => now_ts.() },
        },
      })

      sleep 0.05

      # Event 2: artifact update
      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "echo-response",
        "parts"      => [{ "text" => "Echo: #{text}" }],
      }
      store.add_artifact(task_id, artifact)
      store.add_message(task_id, {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Echo: #{text}" }],
      })

      s.event({
        "artifactUpdate" => {
          "taskId"    => task_id,
          "contextId" => context_id,
          "artifact"  => artifact,
          "append"    => false,
          "lastChunk" => true,
        },
      })

      sleep 0.05

      # Event 3: completed
      store.update_state(task_id, "TASK_STATE_COMPLETED")

      s.event({
        "statusUpdate" => {
          "taskId"    => task_id,
          "contextId" => context_id,
          "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => now_ts.() },
        },
      })

      s.finish
    rescue => e
      Console.error("SendStreamingMessage") { e.full_message }
      s.finish
    end
  end

  # ── 3. GetTask ──────────────────────────────────────────────────────
  on "GetTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    history = task[:history]
    if request.respond_to?(:history_length) && request.history_length
      hl = request.history_length.to_i
      history = hl == 0 ? nil : history.last(hl)
    end

    result = {
      "id"        => task[:id],
      "contextId" => task[:context_id],
      "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
      "artifacts" => task[:artifacts],
    }
    result["history"] = history if history

    respond A2A::Schema["Task"].new(result)
  end

  # ── 4. ListTasks ────────────────────────────────────────────────────
  on "ListTasks" do |request|
    context_id = request.respond_to?(:context_id) ? request.context_id : nil
    status     = request.respond_to?(:status)     ? request.status     : nil
    context_id = nil if context_id.to_s.empty?
    status     = nil if status.to_s.empty?

    page_size = 50
    if request.respond_to?(:page_size) && request.page_size
      ps = request.page_size.to_i
      page_size = [[ps, 1].max, 100].min
    end

    all_tasks = store.list(context_id: context_id, state: status)
    total_size = all_tasks.size

    page_token = request.respond_to?(:page_token) ? request.page_token : nil
    if page_token && !page_token.to_s.empty?
      idx = all_tasks.index { |t| t[:id] == page_token }
      all_tasks = idx ? all_tasks[(idx + 1)..] : []
    end

    page = all_tasks.first(page_size)
    next_token = page.size == page_size && page.size < all_tasks.size ? page.last[:id] : ""

    include_artifacts = false
    if request.respond_to?(:include_artifacts)
      include_artifacts = !!request.include_artifacts
    end

    history_length = nil
    if request.respond_to?(:history_length) && request.history_length
      history_length = request.history_length.to_i
    end

    tasks_json = page.map do |t|
      task_h = {
        "id"        => t[:id],
        "contextId" => t[:context_id],
        "status"    => { "state" => t[:state], "timestamp" => t[:updated_at] },
      }
      task_h["artifacts"] = t[:artifacts] if include_artifacts
      if history_length.nil?
        task_h["history"] = t[:history]
      elsif history_length > 0
        task_h["history"] = t[:history].last(history_length)
      end
      task_h
    end

    respond A2A::Schema["List Tasks Response"].new(
      tasks:           tasks_json,
      next_page_token: next_token,
      page_size:       page_size,
      total_size:      total_size,
    )
  end

  # ── 5. CancelTask ──────────────────────────────────────────────────
  on "CancelTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    if terminal_states.include?(task[:state])
      respond nil
      @env["a2a.error"] = { code: -32002, message: "Task is not cancelable", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_CANCELABLE", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id, "state" => task[:state] } }] }
      next
    end

    store.cancel(id)
    task = store.get(id)

    respond A2A::Schema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
    )
  end

  # ── 6. SubscribeToTask ─────────────────────────────────────────────
  #
  # SSE stream via Falcon-native async streaming + Async::Queue pub/sub.
  # No threads — pure fiber-based cooperative concurrency.
  #
  on "SubscribeToTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    if terminal_states.include?(task[:state])
      respond nil
      @env["a2a.error"] = { code: -32004, message: "Cannot subscribe to a task in a terminal state", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id, "state" => task[:state] } }] }
      next
    end

    sub_queue = store.subscribe(id)
    unless sub_queue
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    # Create the SSE stream — binding-aware
    s = stream

    # Relay store pub/sub events to SSE in a background fiber
    Async do
      # First event: current task snapshot (per A2A spec)
      s.event({
        "task" => {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
          "artifacts" => task[:artifacts],
        },
      })

      # Relay events from Async::Queue (fiber-safe dequeue)
      while (event = sub_queue.dequeue)
        case event[:type]
        when :status
          s.event({ "statusUpdate" => event[:data] })
        when :artifact
          s.event({ "artifactUpdate" => event[:data] })
        end

        # Close on terminal state
        if event[:type] == :status
          state = event[:data].dig("status", "state")
          break if terminal_states.include?(state)
        end
      end

      s.finish
      store.unsubscribe(id, sub_queue)
    rescue => e
      Console.error("SubscribeToTask") { e.full_message }
      s.finish
    end
  end

  # ── 7. CreateTaskPushNotificationConfig ─────────────────────────────
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

  # ── 8. GetTaskPushNotificationConfig ────────────────────────────────
  on "GetTaskPushNotificationConfig" do |request|
    task_id   = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    config_id = request.id

    task = store.get(task_id)
    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id.to_s } }] }
      next
    end

    config = store.get_push_config(task_id, config_id)
    unless config
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Push notification config not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id.to_s, "configId" => config_id.to_s } }] }
      next
    end

    respond A2A::Schema["Task Push Notification Config"].new(config)
  end

  # ── 9. ListTaskPushNotificationConfigs ──────────────────────────────
  on "ListTaskPushNotificationConfigs" do |request|
    task_id = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]

    task = store.get(task_id)
    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id.to_s } }] }
      next
    end

    configs = store.list_push_configs(task_id)
    respond A2A::Schema["List Task Push Notification Configs Response"].new(
      configs:         configs,
      next_page_token: "",
    )
  end

  # ── 10. DeleteTaskPushNotificationConfig ────────────────────────────
  on "DeleteTaskPushNotificationConfig" do |request|
    task_id   = request.respond_to?(:task_id) ? request.task_id : request.to_h["taskId"]
    config_id = request.id

    task = store.get(task_id)
    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id.to_s } }] }
      next
    end

    store.delete_push_config(task_id, config_id)
    respond nil
  end

  # ── 11. GetExtendedAgentCard ────────────────────────────────────────
  on "GetExtendedAgentCard" do |request|
    respond nil
    @env["a2a.error"] = {
      code:    -32004,
      message: "Extended agent card is not supported",
      data:    [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org" }],
    }
  end
end

# ─── Boot ─────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Full Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }
Console.info(self) { "Store: SQLite (echo_agent.db)" }
Console.info(self) { "Streaming: Falcon-native SSE via Protocol::HTTP::Body::Writable" }
Console.info(self) { "Concurrency: Async fibers (no threads)" }

run app
