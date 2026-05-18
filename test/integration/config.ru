# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/sse"
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

extract_text = ->(message) {
  parts = message.parts || []
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
}

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

make_stream = ->(env) {
  if env["a2a.json_rpc_id"]
    A2A::SSE::JsonRpcStream.new(json_rpc_id: env["a2a.json_rpc_id"])
  else
    A2A::SSE::RestStream.new
  end
}

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A::Agent.new do

  # ── SendMessage ────────────────────────────────────────────────────
  on "SendMessage" do
    respond_with ->(env) {
      request = env["a2a.request"]
      msg     = request.message
      text    = extract_text.(msg)

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

      A2A::Schema["Send Message Response"].new(task: task)
    }
  end

  # ── SendStreamingMessage ───────────────────────────────────────────
  on "SendStreamingMessage" do
    respond_with ->(env) {
      request = env["a2a.request"]
      msg     = request.message
      text    = extract_text.(msg)

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

      stream = make_stream.(env)
      env["a2a.stream"] = stream

      Async do
        sleep 0.05

        # Event 1: task snapshot
        stream.event({
          "task" => {
            "id"        => task_id,
            "contextId" => context_id,
            "status"    => { "state" => "TASK_STATE_WORKING", "timestamp" => now_ts.() },
          },
        })

        sleep 0.05

        # Event 2: artifact
        artifact = {
          "artifactId" => SecureRandom.uuid,
          "name"       => "echo-response",
          "parts"      => [{ "text" => "Echo: #{text}" }],
        }
        task["artifacts"] << artifact
        task["history"] << { "messageId" => SecureRandom.uuid, "role" => "ROLE_AGENT", "parts" => [{ "text" => "Echo: #{text}" }] }

        stream.event({
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
        task["status"] = { "state" => "TASK_STATE_COMPLETED", "timestamp" => now_ts.() }

        stream.event({
          "statusUpdate" => {
            "taskId"    => task_id,
            "contextId" => context_id,
            "status"    => task["status"],
          },
        })

        stream.finish
      rescue => e
        Console.error("SendStreamingMessage") { e.full_message }
        stream.finish
      end

      nil
    }
  end

  # ── GetTask ────────────────────────────────────────────────────────
  on "GetTask" do
    respond_with ->(env) {
      request = env["a2a.request"]
      id = request.id
      task = TASKS[id]
      raise A2A::TaskNotFoundError.new(id) unless task

      A2A::Schema["Task"].new(task)
    }
  end

  # ── ListTasks ──────────────────────────────────────────────────────
  on "ListTasks" do
    respond_with ->(env) {
      request    = env["a2a.request"]
      context_id = request.context_id
      context_id = nil if context_id.to_s.empty?

      tasks = TASKS.values
      tasks = tasks.select { |t| t["contextId"] == context_id } if context_id

      A2A::Schema["List Tasks Response"].new(
        tasks: tasks,
      )
    }
  end

  # ── CancelTask ─────────────────────────────────────────────────────
  on "CancelTask" do
    respond_with ->(env) {
      request = env["a2a.request"]
      id = request.id
      task = TASKS[id]
      raise A2A::TaskNotFoundError.new(id) unless task
      raise A2A::TaskNotCancelableError.new(id, state: task["status"]["state"]) if TERMINAL_STATES.include?(task["status"]["state"])

      task["status"] = { "state" => "TASK_STATE_CANCELED", "timestamp" => now_ts.() }

      A2A::Schema["Task"].new(task)
    }
  end

  # ── SubscribeToTask ────────────────────────────────────────────────
  on "SubscribeToTask" do
    respond_with ->(env) {
      request = env["a2a.request"]
      id = request.id
      task = TASKS[id]
      raise A2A::TaskNotFoundError.new(id) unless task

      stream = make_stream.(env)
      env["a2a.stream"] = stream

      Async do
        stream.event({
          "task" => task,
        })

        stream.event({
          "statusUpdate" => {
            "taskId"    => id,
            "contextId" => task["contextId"],
            "status"    => task["status"],
          },
        })

        stream.finish
      rescue => e
        Console.error("SubscribeToTask") { e.full_message }
        stream.finish
      end

      nil
    }
  end

  # ── CreateTaskPushNotificationConfig ───────────────────────────────
  on "CreateTaskPushNotificationConfig" do
    respond_with ->(env) {
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

      A2A::Schema["Task Push Notification Config"].new(config)
    }
  end

  # ── GetTaskPushNotificationConfig ──────────────────────────────────
  on "GetTaskPushNotificationConfig" do
    respond_with ->(env) {
      request   = env["a2a.request"]
      task_id   = request.task_id
      config_id = request.id
      raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

      config = PUSH_CONFIGS.dig(task_id, config_id)
      raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id) unless config

      A2A::Schema["Task Push Notification Config"].new(config)
    }
  end

  # ── ListTaskPushNotificationConfigs ────────────────────────────────
  on "ListTaskPushNotificationConfigs" do
    respond_with ->(env) {
      request = env["a2a.request"]
      task_id = request.task_id
      raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

      configs = (PUSH_CONFIGS[task_id] || {}).values

      A2A::Schema["List Task Push Notification Configs Response"].new(
        configs: configs,
      )
    }
  end

  # ── DeleteTaskPushNotificationConfig ───────────────────────────────
  on "DeleteTaskPushNotificationConfig" do
    respond_with ->(env) {
      request   = env["a2a.request"]
      task_id   = request.task_id
      config_id = request.id
      raise A2A::TaskNotFoundError.new(task_id) unless TASKS[task_id]

      PUSH_CONFIGS[task_id]&.delete(config_id)
      nil
    }
  end

  # ── GetExtendedAgentCard ───────────────────────────────────────────
  on "GetExtendedAgentCard" do
    respond_with ->(env) {
      raise A2A::UnsupportedOperationError.new(message: "Extended agent card is not supported")
    }
  end
end

# ─── Boot ─────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Integration Test Agent starting..." }

run app
