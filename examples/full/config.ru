# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server/sse"
require "async/semaphore"
require "console"
require "securerandom"
require "async"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze

agent = A2A.agent(agent_card: agent_card, history_length: 20, page_size: 50) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    request    = env["a2a.request"]
    msg        = request.message
    text       = env["a2a.message"]

    context_id = msg.context_id
    message_id = msg.message_id
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = msg.task_id

    if task_id && !task_id.to_s.empty?
      existing = LOCK.acquire { TASKS[task_id] }
      raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state") if existing && TERMINAL_STATES.include?(existing[:state])
    else
      task_id = SecureRandom.uuid
      LOCK.acquire do
        TASKS[task_id] = { id: task_id, context_id: context_id, state: "TASK_STATE_SUBMITTED", updated_at: NOW.(), artifacts: [], history: [] }
      end
    end

    LOCK.acquire do
      TASKS[task_id][:history] << {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      }
    end

    artifact = {
      "artifactId" => SecureRandom.uuid,
      "name"       => "echo-response",
      "parts"      => [{ "text" => "Echo: #{text}" }],
    }

    task = LOCK.acquire do
      TASKS[task_id][:artifacts] << artifact
      TASKS[task_id][:history] << {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "Echo: #{text}" }],
      }
      TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
      TASKS[task_id][:updated_at] = NOW.()
      TASKS[task_id]
    end

    A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        "artifacts" => task[:artifacts],
        "history"   => task[:history],
      }
    )

  # Returns results as SSE events via Falcon-native async streaming.
  # Uses A2A::Server::SSE::Stream (Protocol::HTTP::Body::Writable) -- no threads.
  #
  in "SendStreamingMessage"
    request = env["a2a.request"]
    msg = request.message
    text = env["a2a.message"]

    context_id = msg.context_id
    message_id = msg.message_id
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    LOCK.acquire do
      TASKS[task_id] = { id: task_id, context_id: context_id, state: "TASK_STATE_SUBMITTED", updated_at: NOW.(), artifacts: [], history: [] }
      TASKS[task_id][:history] << {
        "messageId" => message_id || SecureRandom.uuid,
        "role"      => "ROLE_USER",
        "parts"     => [{ "text" => text }],
      }
      TASKS[task_id][:state] = "TASK_STATE_WORKING"
      TASKS[task_id][:updated_at] = NOW.()
    end

    env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
      sleep 0.05

      # Event 1: initial Task snapshot
      s.task(status: { state: "TASK_STATE_WORKING", timestamp: NOW.() })

      sleep 0.05

      # Event 2: artifact update
      artifact_id = SecureRandom.uuid

      LOCK.acquire do
        TASKS[task_id][:artifacts] << {
          "artifactId" => artifact_id,
          "name"       => "echo-response",
          "parts"      => [{ "text" => "Echo: #{text}" }],
        }
        TASKS[task_id][:history] << {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "Echo: #{text}" }],
        }
      end

      s.artifact_update(
        artifact: { artifact_id: artifact_id, name: "echo-response", parts: [{ text: "Echo: #{text}" }] },
        append: false,
        last_chunk: true,
      )

      sleep 0.05

      # Event 3: completed
      LOCK.acquire do
        TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
        TASKS[task_id][:updated_at] = NOW.()
      end

      s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: NOW.() })
    end

  in "GetTask"
    request = env["a2a.request"]
    id = request.id
    limit = env["a2a.history_length"]

    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { state: task[:state], timestamp: task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history]&.last(limit),
    )

  in "ListTasks"
    request    = env["a2a.request"]
    page_size  = env["a2a.page_size"]
    limit      = env["a2a.history_length"]
    context_id = request.context_id
    status     = request.status
    context_id = nil if context_id.to_s.empty?
    status     = nil if status.to_s.empty?

    all_tasks = LOCK.acquire do
      TASKS.values.select do |t|
        (context_id.nil? || t[:context_id] == context_id) &&
        (status.nil? || t[:state] == status)
      end
    end

    total_size = all_tasks.size

    page_token = request.page_token
    if page_token && !page_token.to_s.empty?
      idx = all_tasks.index { |t| t[:id] == page_token }
      all_tasks = idx ? all_tasks[(idx + 1)..] : []
    end

    page = all_tasks.first(page_size)
    next_token = page.size == page_size && page.size < all_tasks.size ? page.last[:id] : ""

    include_artifacts = !!request.include_artifacts

    tasks_json = page.map do |t|
      task_h = {
        "id"        => t[:id],
        "contextId" => t[:context_id],
        "status"    => { "state" => t[:state], "timestamp" => t[:updated_at] },
      }
      task_h["artifacts"] = t[:artifacts] if include_artifacts
      task_h["history"] = t[:history]&.last(limit)
      task_h
    end

    A2A::Protocol::JsonSchema["List Tasks Response"].new(
      tasks:           tasks_json,
      next_page_token: next_token,
      page_size:       page_size,
      total_size:      total_size,
    )

  in "CancelTask"
    request = env["a2a.request"]
    id = request.id

    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if TERMINAL_STATES.include?(task[:state])

    task = LOCK.acquire do
      TASKS[id][:state] = "TASK_STATE_CANCELLED"
      TASKS[id][:updated_at] = NOW.()
      TASKS[id]
    end

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
    )
  end
end

Console.info(self) { "Full Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }
Console.info(self) { "Store: in-memory (Async::Semaphore)" }
Console.info(self) { "Streaming: Falcon-native SSE via Protocol::HTTP::Body::Writable" }
Console.info(self) { "Concurrency: Async fibers (no threads)" }

run agent
