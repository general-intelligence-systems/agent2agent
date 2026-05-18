# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "console"
require "securerandom"
require "async"
require "yaml"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message.parts || []
  parts.filter_map { |p| p.text }.join("\n")
}

now_ts = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

terminal_states = A2A::Store::SQLite::TERMINAL_STATES

# ─── Store + Processor ────────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "slow_worker.db")
processor    = A2A::Store::Processor.new

# Simulated work steps
WORK_STEPS = [
  { delay: 0.5, message: "Step 1/4: Loading data..." },
  { delay: 0.8, message: "Step 2/4: Running analysis..." },
  { delay: 0.6, message: "Step 3/4: Generating insights..." },
  { delay: 0.4, message: "Step 4/4: Compiling report..." },
].freeze

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A::Agent.new do

  # ── SendMessage ──────────────────────────────────────────────────────
  #
  # Supports two modes:
  #   - Blocking (default): waits for job to complete, returns final result
  #   - Non-blocking (returnImmediately: true): returns SUBMITTED, processes in background
  #
  on "SendMessage" do
    respond_with -> (env) {
      request = env["a2a.request"]
      msg = request.message
      text = extract_text.(msg)

      context_id = msg.context_id
      context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
      task_id    = SecureRandom.uuid

      sqlite_store.create(task_id, context_id)
      sqlite_store.add_message(task_id, {
        "messageId" => msg.message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      })

      # Check for returnImmediately configuration
      return_immediately = false
      if request.configuration
        cfg = request.configuration
        return_immediately = !!(cfg.return_immediately)
      end

      # The actual work — runs either inline or in background
      do_work = proc do
        sqlite_store.update_state(task_id, "TASK_STATE_WORKING")

        WORK_STEPS.each do |step|
          sleep step[:delay]
          sqlite_store.update_state(task_id, "TASK_STATE_WORKING", message: {
            "messageId" => SecureRandom.uuid,
            "role"      => "ROLE_AGENT",
            "parts"     => [{ "text" => step[:message] }],
          })
        end

        artifact = {
          "artifactId" => SecureRandom.uuid,
          "name"       => "analysis-report",
          "parts"      => [{ "text" => "Analysis Report for: #{text}\n\nFindings:\n- Data processed: 1,247 records\n- Anomalies detected: 3\n- Confidence: 94.7%\n- Recommendation: Proceed with caution\n\n[Simulated analysis result]" }],
        }
        sqlite_store.add_artifact(task_id, artifact)
        sqlite_store.add_message(task_id, {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Analysis complete. See the attached report." }],
        })
        sqlite_store.complete(task_id, nil)
      end

      if return_immediately
        # ── Non-blocking: return SUBMITTED, process in background fiber ──
        processor.call(&do_work)

        task = sqlite_store.get(task_id)
        A2A::Schema["Send Message Response"].new(
          task: {
            "id"        => task[:id],
            "contextId" => task[:context_id],
            "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
          }
        )
      else
        # ── Blocking: do the work inline, return final result ──
        do_work.call

        task = sqlite_store.get(task_id)
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
    }
  end

  # ── SubscribeToTask ─────────────────────────────────────────────────
  #
  # SSE stream relaying live progress from the Store::PubSub.
  # First event is the current task snapshot, then live updates
  # until terminal state.
  #
  on "SubscribeToTask" do
    respond_with -> (env) {
      request = env["a2a.request"]
      id = request.id
      task = sqlite_store.get(id)
      raise A2A::TaskNotFoundError.new(id) unless task
      raise A2A::UnsupportedOperationError.new(message: "Cannot subscribe to a task in a terminal state") if terminal_states.include?(task[:state])

      sub_queue = sqlite_store.subscribe(id)
      raise A2A::TaskNotFoundError.new(id) unless sub_queue

      s = if env["a2a.json_rpc_id"]
        A2A::SSE::JsonRpcStream.new(json_rpc_id: env["a2a.json_rpc_id"])
      else
        A2A::SSE::RestStream.new
      end
      env["a2a.stream"] = s

      Async do
        # First event: current snapshot
        s.event({
          "task" => {
            "id"        => task[:id],
            "contextId" => task[:context_id],
            "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
            "artifacts" => task[:artifacts],
          },
        })

        # Relay live events from PubSub
        while (event = sub_queue.dequeue)
          case event[:type]
          when :status
            s.event({ "statusUpdate" => event[:data] })
          when :artifact
            s.event({ "artifactUpdate" => event[:data] })
          end

          if event[:type] == :status
            state = event[:data].dig("status", "state")
            break if terminal_states.include?(state)
          end
        end

        s.finish
        sqlite_store.unsubscribe(id, sub_queue)
      rescue => e
        Console.error("SubscribeToTask") { e.full_message }
        s.finish
      end
    }
  end

  # ── GetTask ──────────────────────────────────────────────────────────
  on "GetTask" do
    respond_with -> (env) {
      request = env["a2a.request"]
      id = request.id
      task = sqlite_store.get(id)
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
    }
  end

  # ── CancelTask ──────────────────────────────────────────────────────
  on "CancelTask" do
    respond_with -> (env) {
      request = env["a2a.request"]
      id = request.id
      task = sqlite_store.get(id)
      raise A2A::TaskNotFoundError.new(id) unless task
      raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if terminal_states.include?(task[:state])

      sqlite_store.cancel(id)
      task = sqlite_store.get(id)

      A2A::Schema["Task"].new(
        id:         task[:id],
        context_id: task[:context_id],
        status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
        artifacts:  task[:artifacts],
      )
    }
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Slow Worker starting..." }
Console.info(self) { "Async jobs example: returnImmediately + SubscribeToTask + Processor" }

run app
