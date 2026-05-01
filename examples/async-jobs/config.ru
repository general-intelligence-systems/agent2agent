# frozen_string_literal: true

# Async Jobs Agent
#
# Demonstrates non-blocking/async task processing:
#   1. SendMessage with returnImmediately: true returns SUBMITTED instantly
#   2. Store::Processor runs the job in a background fiber
#   3. SubscribeToTask relays live progress via SSE
#   4. GetTask polls the final result
#
# Inspired by the .NET EchoAgentWithTasks (ReturnImmediately mode)
# and the Python adk-cloud-run agent.
#
# Run with:
#   cd examples/async-jobs && bundle install && bundle exec falcon serve --bind http://0.0.0.0:9292
#
# Test async flow:
#   # 1. Submit a job (returns immediately with SUBMITTED)
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
#       "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Analyze this dataset"}]},
#       "configuration":{"returnImmediately":true}
#     }}'
#
#   # 2. Subscribe for live updates (SSE stream)
#   curl -N -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":2,"method":"SubscribeToTask","params":{"id":"TASK_ID_HERE"}}'
#
#   # 3. Or poll for the result
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":3,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}'

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
  "name"               => "Slow Worker",
  "description"        => "An async agent that processes jobs in the background with progress updates.",
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
    "pushNotifications" => false,
  },
  "defaultInputModes"  => ["text/plain"],
  "defaultOutputModes" => ["text/plain"],
  "skills" => [
    {
      "id"          => "analyze",
      "name"        => "Data Analyzer",
      "description" => "Performs long-running analysis with progress updates. Supports async mode via returnImmediately.",
      "tags"        => ["analysis", "async", "background"],
      "examples"    => ["Analyze this dataset", "Process the logs"],
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
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    store.create(task_id, context_id)
    store.add_message(task_id, {
      "messageId" => (msg.respond_to?(:message_id) ? msg.message_id : msg["messageId"]) || SecureRandom.uuid,
      "role"      => "ROLE_USER",
      "parts"     => [{ "text" => text }],
    })

    # Check for returnImmediately configuration
    return_immediately = false
    if request.respond_to?(:configuration) && request.configuration
      cfg = request.configuration
      ri = cfg.respond_to?(:return_immediately) ? cfg.return_immediately : (cfg["returnImmediately"] || cfg["return_immediately"])
      return_immediately = !!ri
    end

    # The actual work — runs either inline or in background
    do_work = proc do
      store.update_state(task_id, "TASK_STATE_WORKING")

      WORK_STEPS.each do |step|
        sleep step[:delay]
        store.update_state(task_id, "TASK_STATE_WORKING", message: {
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
      store.add_artifact(task_id, artifact)
      store.add_message(task_id, {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Analysis complete. See the attached report." }],
      })
      store.complete(task_id, nil)
    end

    if return_immediately
      # ── Non-blocking: return SUBMITTED, process in background fiber ──
      processor.call(&do_work)

      task = store.get(task_id)
      respond A2A::Schema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        }
      )
    else
      # ── Blocking: do the work inline, return final result ──
      do_work.call

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
  end

  # ── SubscribeToTask ─────────────────────────────────────────────────
  #
  # SSE stream relaying live progress from the Store::PubSub.
  # First event is the current task snapshot, then live updates
  # until terminal state.
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

    s = stream

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
      store.unsubscribe(id, sub_queue)
    rescue => e
      Console.error("SubscribeToTask") { e.full_message }
      s.finish
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

  # ── CancelTask ──────────────────────────────────────────────────────
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
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Slow Worker starting..." }
Console.info(self) { "Async jobs example: returnImmediately + SubscribeToTask + Processor" }

run app
