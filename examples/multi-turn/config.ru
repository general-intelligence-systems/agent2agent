# frozen_string_literal: true

# Multi-Turn Conversation Agent
#
# Demonstrates the INPUT_REQUIRED state for multi-turn interactions:
#   1. User sends a message with a topic
#   2. Agent creates a task, transitions to INPUT_REQUIRED asking for confirmation
#   3. User sends follow-up with the same taskId
#   4. Agent completes (or re-asks) based on user response
#
# This is the A2A equivalent of the .NET ResearcherAgent and the
# Python Airbnb agent's input_required pattern.
#
# Run with:
#   cd examples/multi-turn && bundle install && bundle exec falcon serve --bind http://0.0.0.0:9292
#
# Test multi-turn flow:
#   # Turn 1: start a research task
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
#       "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Research quantum computing"}]}
#     }}'
#
#   # Turn 2: confirm (use the taskId from turn 1)
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
#       "message":{"messageId":"m2","role":"ROLE_USER","taskId":"TASK_ID_HERE","parts":[{"text":"go ahead"}]}
#     }}'

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
  parts = message.respond_to?(:parts) ? message.parts : (message["parts"] || [])
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
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

    task_id    = msg.respond_to?(:task_id)    ? msg.task_id    : msg["taskId"]
    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    message_id = msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    if task_id && !task_id.empty?
      # ── Continuation: user is responding to INPUT_REQUIRED ──────────

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

      unless existing[:state] == "TASK_STATE_INPUT_REQUIRED"
        respond nil
        @env["a2a.error"] = { code: -32004, message: "Task is not awaiting input", data: [{ "@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "UNSUPPORTED_OPERATION", "domain" => "a2a-protocol.org" }] }
        next
      end

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
        respond A2A::Schema["Send Message Response"].new(
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
        respond A2A::Schema["Send Message Response"].new(
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
      respond A2A::Schema["Send Message Response"].new(
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
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Research Planner starting..." }
Console.info(self) { "Multi-turn example: INPUT_REQUIRED → confirmation → COMPLETED" }

run app
