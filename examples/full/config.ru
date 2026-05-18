# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "console"
require "securerandom"
require "async"
require "yaml"

# ─── Agent Card (spec-compliant) ──────────────────────────────────────

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

extract_text = ->(message) {
  parts = message["parts"] || []
  parts.filter_map { |p| p["text"] }.join("\n")
}

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

terminal_states = A2A::Store::SQLite::TERMINAL_STATES

sqlite_store = A2A::Store::SQLite.new(path: "echo_agent.db")

agent = A2A::Agent.new do

  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    task_id    = msg["taskId"]
    context_id = msg["contextId"]
    message_id = msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    push_config = nil

    if request.configuration
      cfg = request.configuration
      pnc = cfg["taskPushNotificationConfig"] || cfg["pushNotificationConfig"]
      push_config = pnc if pnc
    end

    if task_id && !task_id.empty?
      existing = store.get(task_id)
      raise A2A::TaskNotFoundError.new(task_id) unless existing
      raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state") if terminal_states.include?(existing[:state])

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

    A2A::Schema["Send Message Response"].new(
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

    context_id = msg["contextId"]
    message_id = msg["messageId"]
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
    raise A2A::TaskNotFoundError.new(id) unless task

    history = task[:history]
    if request.history_length
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

    A2A::Schema["Task"].new(result)
  end

  # ── 4. ListTasks ────────────────────────────────────────────────────
  on "ListTasks" do |request|
    context_id = request.context_id
    status     = request.status
    context_id = nil if context_id.to_s.empty?
    status     = nil if status.to_s.empty?

    page_size = 50
    if request.page_size
      ps = request.page_size.to_i
      page_size = [[ps, 1].max, 100].min
    end

    all_tasks = store.list(context_id: context_id, state: status)
    total_size = all_tasks.size

    page_token = request.page_token
    if page_token && !page_token.to_s.empty?
      idx = all_tasks.index { |t| t[:id] == page_token }
      all_tasks = idx ? all_tasks[(idx + 1)..] : []
    end

    page = all_tasks.first(page_size)
    next_token = page.size == page_size && page.size < all_tasks.size ? page.last[:id] : ""

    include_artifacts = !!request.include_artifacts

    history_length = nil
    if request.history_length
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

    A2A::Schema["List Tasks Response"].new(
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
    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if terminal_states.include?(task[:state])

    store.cancel(id)
    task = store.get(id)

    A2A::Schema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
    )
  end

  # SSE stream via Falcon-native async streaming + Async::Queue pub/sub.
  # No threads — pure fiber-based cooperative concurrency.
  #
  on "SubscribeToTask" do |request|
    id = request.id
    task = store.get(id)
    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::UnsupportedOperationError.new(message: "Cannot subscribe to a task in a terminal state") if terminal_states.include?(task[:state])

    sub_queue = store.subscribe(id)
    raise A2A::TaskNotFoundError.new(id) unless sub_queue

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
    task_id = request.task_id
    task = store.get(task_id)
    raise A2A::TaskNotFoundError.new(task_id) unless task

    request.to_h.then do |config_data|
      config_data.delete("taskId")
      config_data.delete("tenant")

      store.create_push_config(task_id, config_data).then do |result|
        A2A::Schema["Task Push Notification Config"].new(result)
      end
    end
  end

  # ── 8. GetTaskPushNotificationConfig ────────────────────────────────
  on "GetTaskPushNotificationConfig" do |request|
    task_id   = request.task_id
    config_id = request.id

    task = store.get(task_id)
    raise A2A::TaskNotFoundError.new(task_id) unless task

    config = store.get_push_config(task_id, config_id)
    raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id) unless config

    A2A::Schema["Task Push Notification Config"].new(config)
  end

  on "ListTaskPushNotificationConfigs" do |request|
    task_id = request.task_id
    task = store.get(task_id)
    raise A2A::TaskNotFoundError.new(task_id) unless task

    store.list_push_configs(task_id).then do |configs|
      A2A::Schema["List Task Push Notification Configs Response"].new(
        configs:         configs,
        next_page_token: "",
      )
    end
  end

  # ── 10. DeleteTaskPushNotificationConfig ────────────────────────────
  on "DeleteTaskPushNotificationConfig" do |request|
    task_id   = request.task_id
    config_id = request.id

    task = store.get(task_id)
    raise A2A::TaskNotFoundError.new(task_id) unless task

    store.delete_push_config(task_id, config_id)
    nil
  end

  on "GetExtendedAgentCard" do |request|
    raise A2A::UnsupportedOperationError.new(message: "Extended agent card is not supported")
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
