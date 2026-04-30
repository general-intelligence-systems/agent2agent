# frozen_string_literal: true

# Full Echo Agent — A2A Rack entry point
#
# Demonstrates ALL 11 A2A protocol operations:
#
#   1. SendMessage              — echo user text back as a completed task
#   2. SendStreamingMessage     — echo with SSE streaming (task → artifact → completed)
#   3. GetTask                  — retrieve task by ID
#   4. ListTasks                — list tasks with filtering & pagination
#   5. CancelTask               — cancel an in-progress task
#   6. SubscribeToTask          — SSE stream of task updates
#   7. CreateTaskPushNotificationConfig  — register a webhook
#   8. GetTaskPushNotificationConfig     — retrieve a webhook config
#   9. ListTaskPushNotificationConfigs   — list webhook configs for a task
#  10. DeleteTaskPushNotificationConfig  — remove a webhook config
#  11. GetExtendedAgentCard             — returns UnsupportedOperationError
#
# Run with:
#   cd examples/full && bundle install && bundle exec falcon serve --bind http://0.0.0.0:9292
#
# Test with:
#   curl http://localhost:9292/.well-known/agent-card.json | jq .
#
#   # JSON-RPC: SendMessage
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{
#       "jsonrpc": "2.0", "id": 1, "method": "SendMessage",
#       "params": {
#         "message": {
#           "messageId": "msg-1",
#           "role": "ROLE_USER",
#           "parts": [{"text": "Hello, Echo Agent!"}]
#         }
#       }
#     }'
#
#   # JSON-RPC: SendStreamingMessage (SSE)
#   curl -N -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{
#       "jsonrpc": "2.0", "id": 2, "method": "SendStreamingMessage",
#       "params": {
#         "message": {
#           "messageId": "msg-2",
#           "role": "ROLE_USER",
#           "parts": [{"text": "Stream me!"}]
#         }
#       }
#     }'
#
#   # REST: SendMessage
#   curl -X POST http://localhost:9292/message:send \
#     -H "Content-Type: application/a2a+json" \
#     -d '{
#       "message": {
#         "messageId": "msg-3",
#         "role": "ROLE_USER",
#         "parts": [{"text": "Hello via REST!"}]
#       }
#     }'

require "bundler/setup"
require "a2a"
require "console"
require "securerandom"

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

# Extract the concatenated text from a message's parts array.
def extract_text(message)
  parts = message.respond_to?(:parts) ? message.parts : (message["parts"] || [])
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
end

# Build a timestamp string.
def now_ts
  Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
end

TERMINAL_STATES = A2A::TaskStore::TERMINAL_STATES

# ─── Agent: all 11 operations ────────────────────────────────────────

agent = A2A::Agent.new do

  # ── 1. SendMessage ──────────────────────────────────────────────────
  #
  # Accepts a user message, creates a completed task with an echo artifact.
  # If the message references an existing taskId, continues that task.
  #
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text(msg)

    task_id    = msg.respond_to?(:task_id)    ? msg.task_id    : msg["taskId"]
    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    message_id = msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    # Push notification config from configuration
    push_config = nil
    if request.respond_to?(:configuration) && request.configuration
      cfg = request.configuration
      pnc = cfg.respond_to?(:task_push_notification_config) ? cfg.task_push_notification_config : (cfg["taskPushNotificationConfig"] || cfg["pushNotificationConfig"])
      if pnc
        push_config = pnc.respond_to?(:to_h) ? pnc.to_h : pnc
      end
    end

    if task_id && !task_id.empty?
      # Continue existing task
      existing = store.get(task_id)
      unless existing
        respond nil
        @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => task_id } }] }
        next
      end
      if TERMINAL_STATES.include?(existing.state)
        respond nil
        @env["a2a.error"] = { code: -32004, message: "Task is in a terminal state", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org" }] }
        next
      end
      # Record user message in history
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })
    else
      # Create new task
      task_id = SecureRandom.uuid
      store.create(task_id, context_id, push_config)
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })
    end

    # Build echo artifact
    artifact_id = SecureRandom.uuid
    artifact = {
      "artifactId" => artifact_id,
      "name"       => "echo-response",
      "parts"      => [{ "text" => "Echo: #{text}" }],
    }

    store.add_artifact(task_id, artifact)

    # Record agent response in history
    store.add_message(task_id, {
      "messageId" => SecureRandom.uuid,
      "role"      => "ROLE_AGENT",
      "parts"     => [{ "text" => "Echo: #{text}" }],
    })

    store.complete(task_id, nil)

    task = store.get(task_id)
    respond A2A::Schema["Send Message Response"].new(
      task: {
        "id"        => task.id,
        "contextId" => task.context_id,
        "status"    => {
          "state"     => task.state,
          "timestamp" => task.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        },
        "artifacts" => task.artifacts,
        "history"   => task.history,
      }
    )
  end

  # ── 2. SendStreamingMessage ─────────────────────────────────────────
  #
  # Like SendMessage, but returns results as SSE events:
  #   1. Task (state=WORKING)
  #   2. TaskArtifactUpdateEvent with echo text
  #   3. TaskStatusUpdateEvent (state=COMPLETED)
  #
  on "SendStreamingMessage" do |request|
    msg = request.message
    text = extract_text(msg)

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

    queue = Thread::Queue.new

    # Emit events in a background thread so SSE starts immediately
    Thread.new do
      sleep 0.05  # tiny delay to simulate processing

      # Event 1: initial Task with WORKING state
      task = store.get(task_id)
      queue << {
        "task" => {
          "id"        => task.id,
          "contextId" => task.context_id,
          "status"    => {
            "state"     => "TASK_STATE_WORKING",
            "timestamp" => now_ts,
          },
        },
      }

      sleep 0.05

      # Event 2: artifact update
      artifact_id = SecureRandom.uuid
      artifact = {
        "artifactId" => artifact_id,
        "name"       => "echo-response",
        "parts"      => [{ "text" => "Echo: #{text}" }],
      }
      store.add_artifact(task_id, artifact)
      store.add_message(task_id, {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Echo: #{text}" }],
      })

      queue << {
        "artifactUpdate" => {
          "taskId"    => task_id,
          "contextId" => context_id,
          "artifact"  => artifact,
          "append"    => false,
          "lastChunk" => true,
        },
      }

      sleep 0.05

      # Event 3: status update → COMPLETED
      store.update_state(task_id, "TASK_STATE_COMPLETED")

      queue << {
        "statusUpdate" => {
          "taskId"    => task_id,
          "contextId" => context_id,
          "status"    => {
            "state"     => "TASK_STATE_COMPLETED",
            "timestamp" => now_ts,
          },
        },
      }

      queue << nil  # sentinel: end of stream
    rescue => e
      Console.error("SendStreamingMessage") { e.full_message }
      queue << nil
    end

    # Signal the binding to return an SSE stream
    @env["a2a.stream"] = queue
  end

  # ── 3. GetTask ──────────────────────────────────────────────────────
  #
  # Returns the current state of a task by ID.
  #
  on "GetTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    history = task.history
    if request.respond_to?(:history_length) && request.history_length
      hl = request.history_length.to_i
      history = hl == 0 ? nil : history.last(hl)
    end

    result = {
      "id"        => task.id,
      "contextId" => task.context_id,
      "status"    => {
        "state"     => task.state,
        "timestamp" => task.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
      },
      "artifacts" => task.artifacts,
    }
    result["history"] = history if history

    respond A2A::Schema["Task"].new(result)
  end

  # ── 4. ListTasks ────────────────────────────────────────────────────
  #
  # Lists tasks with optional filtering by contextId and status,
  # plus cursor-based pagination.
  #
  on "ListTasks" do |request|
    context_id = request.respond_to?(:context_id) ? request.context_id : nil
    status     = request.respond_to?(:status)     ? request.status     : nil

    context_id = nil if context_id.to_s.empty?
    status     = nil if status.to_s.empty?

    page_size  = 50
    if request.respond_to?(:page_size) && request.page_size
      ps = request.page_size.to_i
      page_size = [[ps, 1].max, 100].min
    end

    all_tasks = store.list(context_id: context_id, state: status)
    total_size = all_tasks.size

    # Cursor-based pagination: page_token is the ID of the last task seen
    page_token = request.respond_to?(:page_token) ? request.page_token : nil
    if page_token && !page_token.to_s.empty?
      idx = all_tasks.index { |t| t.id == page_token }
      all_tasks = idx ? all_tasks[(idx + 1)..] : []
    end

    page = all_tasks.first(page_size)
    next_token = page.size == page_size && page.size < all_tasks.size ? page.last.id : ""

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
        "id"        => t.id,
        "contextId" => t.context_id,
        "status"    => {
          "state"     => t.state,
          "timestamp" => t.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        },
      }
      task_h["artifacts"] = t.artifacts if include_artifacts
      if history_length.nil?
        # no limit specified, include all
        task_h["history"] = t.history
      elsif history_length > 0
        task_h["history"] = t.history.last(history_length)
      end
      # history_length == 0 means omit history
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
  #
  # Cancels an in-progress task.
  #
  on "CancelTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    if TERMINAL_STATES.include?(task.state)
      respond nil
      @env["a2a.error"] = { code: -32002, message: "Task is not cancelable", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_CANCELABLE", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id, "state" => task.state } }] }
      next
    end

    store.cancel(id)
    task = store.get(id)

    respond A2A::Schema["Task"].new(
      id:         task.id,
      context_id: task.context_id,
      status: {
        "state"     => task.state,
        "timestamp" => task.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
      },
      artifacts: task.artifacts,
    )
  end

  # ── 6. SubscribeToTask ─────────────────────────────────────────────
  #
  # Subscribes to real-time SSE updates for an existing task.
  # Returns current task state first, then streams updates until terminal.
  #
  on "SubscribeToTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id.to_s } }] }
      next
    end

    if TERMINAL_STATES.include?(task.state)
      respond nil
      @env["a2a.error"] = { code: -32004, message: "Cannot subscribe to a task in a terminal state", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org", "metadata" => { "taskId" => id, "state" => task.state } }] }
      next
    end

    # Subscribe to updates via the store's pub/sub
    sub_queue = store.subscribe(id)

    unless sub_queue
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    output_queue = Thread::Queue.new

    Thread.new do
      # First event: current task state
      output_queue << {
        "task" => {
          "id"        => task.id,
          "contextId" => task.context_id,
          "status"    => {
            "state"     => task.state,
            "timestamp" => task.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
          },
          "artifacts" => task.artifacts,
        },
      }

      # Relay store events to the output queue
      loop do
        event = sub_queue.pop
        break if event.nil?  # stream closed

        case event[:type]
        when :status
          output_queue << { "statusUpdate" => event[:data] }
        when :artifact
          output_queue << { "artifactUpdate" => event[:data] }
        end

        # If the status event indicates a terminal state, we're done
        if event[:type] == :status
          state = event[:data].dig("status", "state")
          break if TERMINAL_STATES.include?(state)
        end
      end

      output_queue << nil  # sentinel: end of stream
      store.unsubscribe(id, sub_queue)
    rescue => e
      Console.error("SubscribeToTask") { e.full_message }
      output_queue << nil
    end

    @env["a2a.stream"] = output_queue
  end

  # ── 7. CreateTaskPushNotificationConfig ─────────────────────────────
  #
  # Registers a webhook for task update notifications.
  #
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
  #
  # Retrieves a specific push notification config.
  #
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
  #
  # Lists all push notification configs for a task.
  #
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
  #
  # Deletes a push notification config. Idempotent.
  #
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

    # google.protobuf.Empty → nil
    respond nil
  end

  # ── 11. GetExtendedAgentCard ────────────────────────────────────────
  #
  # Extended agent card is not supported (capabilities.extendedAgentCard = false).
  # Returns UnsupportedOperationError per spec section 3.3.4.
  #
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

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Full Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }
Console.info(self) { "Capabilities: streaming=#{agent_card.dig("capabilities", "streaming")}, pushNotifications=#{agent_card.dig("capabilities", "pushNotifications")}" }
Console.info(self) { "Operations: all 11 A2A operations registered" }

run app
