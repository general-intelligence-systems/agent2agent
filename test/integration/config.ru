# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server/sse"
require "console"
require "securerandom"
require "yaml"
require "async"

# ─── In-memory state ──────────────────────────────────────────────────

TASKS        = {}   # task_id => Hash
PUSH_CONFIGS = {}   # task_id => { config_id => Hash }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELED TASK_STATE_FAILED].freeze

# ─── Agent Card ───────────────────────────────────────────────────────

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# ─── Helpers ──────────────────────────────────────────────────────────

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]

  # ── SendMessage ────────────────────────────────────────────────────
  in "SendMessage"
    request = env["a2a.request"]
    msg     = request.message
    text    = env["a2a.message"]

    task_id    = SecureRandom.uuid
    context_id = msg.context_id
    context_id = SecureRandom.uuid if context_id.to_s.empty?

    artifact = {
      "artifactId" => SecureRandom.uuid,
      "name"       => "echo-response",
      "parts"      => [{ "text" => "Echo: #{text}" }],
    }

    history = [
      { "messageId" => msg.message_id || SecureRandom.uuid, "role" => "ROLE_USER",  "parts" => [{ "text" => text }] },
      { "messageId" => SecureRandom.uuid,                   "role" => "ROLE_AGENT", "parts" => [{ "text" => "Echo: #{text}" }] },
    ]

    task = {
      "id"        => task_id,
      "contextId" => context_id,
      "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => now_ts.() },
      "artifacts" => [artifact],
      "history"   => history,
    }

    TASKS[task_id] = task

    A2A::Protocol::JsonSchema["Send Message Response"].new(task: task)

  # ── SendStreamingMessage ───────────────────────────────────────────
  in "SendStreamingMessage"
    request = env["a2a.request"]
    msg     = request.message
    text    = env["a2a.message"]

    task_id    = SecureRandom.uuid
    context_id = msg.context_id
    context_id = SecureRandom.uuid if context_id.to_s.empty?

    task = {
      "id"        => task_id,
      "contextId" => context_id,
      "status"    => { "state" => "TASK_STATE_WORKING", "timestamp" => now_ts.() },
      "artifacts" => [],
      "history"   => [
        { "messageId" => msg.message_id || SecureRandom.uuid, "role" => "ROLE_USER", "parts" => [{ "text" => text }] },
      ],
    }
    TASKS[task_id] = task

    env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |stream|
      sleep 0.05

      # Event 1: task snapshot
      stream.task(status: { state: "TASK_STATE_WORKING", timestamp: now_ts.() })

      sleep 0.05

      # Event 2: artifact
      artifact_id = SecureRandom.uuid
      artifact = {
        "artifactId" => artifact_id,
        "name"       => "echo-response",
        "parts"      => [{ "text" => "Echo: #{text}" }],
      }
      task["artifacts"] << artifact
      task["history"] << { "messageId" => SecureRandom.uuid, "role" => "ROLE_AGENT", "parts" => [{ "text" => "Echo: #{text}" }] }

      stream.artifact_update(
        artifact: { artifact_id: artifact_id, name: "echo-response", parts: [{ text: "Echo: #{text}" }] },
        append: false,
        last_chunk: true,
      )

      sleep 0.05

      # Event 3: completed
      task["status"] = { "state" => "TASK_STATE_COMPLETED", "timestamp" => now_ts.() }

      stream.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: now_ts.() })
    end

  # ── GetTask ────────────────────────────────────────────────────────
  in "GetTask"
    request = env["a2a.request"]
    id = request.id
    task = TASKS[id]
    raise A2A::TaskNotFoundError.new(id) unless task

    A2A::Protocol::JsonSchema["Task"].new(task)

  # ── ListTasks ──────────────────────────────────────────────────────
  in "ListTasks"
    request    = env["a2a.request"]
    context_id = request.context_id
    context_id = nil if context_id.to_s.empty?

    tasks = TASKS.values
    tasks = tasks.select { |t| t["contextId"] == context_id } if context_id

    A2A::Protocol::JsonSchema["List Tasks Response"].new(
      tasks: tasks,
    )

  # ── CancelTask ─────────────────────────────────────────────────────
  in "CancelTask"
    request = env["a2a.request"]
    id = request.id
    task = TASKS[id]
    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::TaskNotCancelableError.new(id, state: task["status"]["state"]) if TERMINAL_STATES.include?(task["status"]["state"])

    task["status"] = { "state" => "TASK_STATE_CANCELED", "timestamp" => now_ts.() }

    A2A::Protocol::JsonSchema["Task"].new(task)

  # ── SubscribeToTask ────────────────────────────────────────────────
  in "SubscribeToTask"
    request = env["a2a.request"]
    id = request.id
    task = TASKS[id]
    raise A2A::TaskNotFoundError.new(id) unless task

    env["a2a.stream"].open(task_id: id, context_id: task["contextId"]) do |stream|
      stream.task(
        status:    task["status"],
        artifacts: task["artifacts"],
        history:   task["history"],
      )

      stream.status_update(status: task["status"])
    end

  # ── CreateTaskPushNotificationConfig ───────────────────────────────
  in "CreateTaskPushNotificationConfig"
    request = env["a2a.request"]
    task_id = request.task_id
    raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

    config_id = SecureRandom.uuid
    config = {
      "id"     => config_id,
      "taskId" => task_id,
      "url"    => request.url,
    }

    PUSH_CONFIGS[task_id] ||= {}
    PUSH_CONFIGS[task_id][config_id] = config

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)

  # ── GetTaskPushNotificationConfig ──────────────────────────────────
  in "GetTaskPushNotificationConfig"
    request   = env["a2a.request"]
    task_id   = request.task_id
    config_id = request.id
    raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

    config = PUSH_CONFIGS.dig(task_id, config_id)
    raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id) unless config

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)

  # ── ListTaskPushNotificationConfigs ────────────────────────────────
  in "ListTaskPushNotificationConfigs"
    request = env["a2a.request"]
    task_id = request.task_id
    raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

    configs = (PUSH_CONFIGS[task_id] || {}).values

    A2A::Protocol::JsonSchema["List Task Push Notification Configs Response"].new(
      configs: configs,
    )

  # ── DeleteTaskPushNotificationConfig ───────────────────────────────
  in "DeleteTaskPushNotificationConfig"
    request   = env["a2a.request"]
    task_id   = request.task_id
    config_id = request.id
    raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

    PUSH_CONFIGS[task_id]&.delete(config_id)
    nil

  # ── GetExtendedAgentCard ───────────────────────────────────────────
  in "GetExtendedAgentCard"
    raise A2A::UnsupportedOperationError.new(message: "Extended agent card is not supported")
  end
end

# ─── Boot ─────────────────────────────────────────────────────────────

Console.info(self) { "Integration Test Agent starting..." }

run agent
