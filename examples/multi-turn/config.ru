# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/store"
require "console"
require "securerandom"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = {
  "name"               => "Research Planner",
  "description"        => "A multi-turn agent that plans research and asks for confirmation before proceeding.",
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
    "streaming"         => false,
    "pushNotifications" => false,
  },
  "defaultInputModes"  => ["text/plain"],
  "defaultOutputModes" => ["text/plain"],
  "skills" => [
    {
      "id"          => "research",
      "name"        => "Research Planner",
      "description" => "Plans research on a topic and asks for user confirmation before executing.",
      "tags"        => ["research", "planning", "multi-turn"],
      "examples"    => ["Research quantum computing", "Investigate Ruby concurrency models"],
    },
  ],
}

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message["parts"] || []
  parts.filter_map { |p| p["text"] }.join("\n")
}

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

terminal_states = A2A::Store::SQLite::TERMINAL_STATES

# ─── SQLite-backed store ─────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "research_planner.db")

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A::Agent.new do

  # ── SendMessage ──────────────────────────────────────────────────────
  #
  # Two code paths:
  #   1. New task (no taskId): create task, plan research, ask for confirmation
  #   2. Continuation (taskId present): check if user confirmed, then complete or re-ask
  #
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    task_id    = msg["taskId"]
    context_id = msg["contextId"]
    message_id = msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    if task_id && !task_id.empty?
      # ── Continuation: user is responding to INPUT_REQUIRED ──────────

      existing = store.get(task_id)
      raise A2A::TaskNotFoundError.new(task_id) unless existing
      raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state") if terminal_states.include?(existing[:state])
      raise A2A::UnsupportedOperationError.new(message: "Task is not awaiting input") unless existing[:state] == "TASK_STATE_INPUT_REQUIRED"

      # Record the user's follow-up message
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })

      # Check if user confirmed
      if text.strip.downcase.include?("go ahead") || text.strip.downcase.include?("yes") || text.strip.downcase.include?("confirm")
        # ── User confirmed: complete the research ──────────────────────
        store.update_state(task_id, "TASK_STATE_WORKING")

        # Extract the original topic from history
        original_msg = existing[:history].find { |m| m["role"] == "ROLE_USER" }
        topic = original_msg ? original_msg["parts"]&.first&.dig("text") : "the requested topic"

        artifact = {
          "artifactId" => SecureRandom.uuid,
          "name"       => "research-report",
          "parts"      => [{ "text" => "Research Report: #{topic}\n\n1. Background: #{topic} is a rapidly evolving field.\n2. Key findings: Multiple approaches exist.\n3. Recommendations: Further investigation warranted.\n\n[This is a simulated research output]" }],
        }
        store.add_artifact(task_id, artifact)
        store.add_message(task_id, {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Research complete. See the attached report." }],
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
      else
        # ── User didn't confirm: re-ask ────────────────────────────────
        agent_msg = {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "I didn't catch a confirmation. Please say 'go ahead' to proceed with the research, or describe what you'd like to change." }],
        }
        store.add_message(task_id, agent_msg)

        # Stay in INPUT_REQUIRED — re-set the state with the new message
        store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED", message: agent_msg)

        task = store.get(task_id)
        A2A::Schema["Send Message Response"].new(
          task: {
            "id"        => task[:id],
            "contextId" => task[:context_id],
            "status"    => {
              "state"     => task[:state],
              "timestamp" => task[:updated_at],
              "message"   => agent_msg,
            },
            "history"   => task[:history],
          }
        )
      end

    else
      # ── New task: plan the research, ask for confirmation ──────────

      task_id = SecureRandom.uuid
      store.create(task_id, context_id)
      store.add_message(task_id, {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })

      # Transition: SUBMITTED → WORKING → INPUT_REQUIRED
      store.update_state(task_id, "TASK_STATE_WORKING")

      agent_msg = {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "I've prepared a research plan for: #{text}\n\nPlan:\n1. Survey existing literature\n2. Identify key themes and gaps\n3. Synthesize findings into a report\n\nSay 'go ahead' to proceed." }],
      }
      store.add_message(task_id, agent_msg)
      store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED", message: agent_msg)

      task = store.get(task_id)
      A2A::Schema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => {
            "state"     => task[:state],
            "timestamp" => task[:updated_at],
            "message"   => agent_msg,
          },
          "history"   => task[:history],
        }
      )
    end
  end

  # ── GetTask ──────────────────────────────────────────────────────────
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
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Research Planner starting..." }
Console.info(self) { "Multi-turn example: INPUT_REQUIRED → confirmation → COMPLETED" }

run app
