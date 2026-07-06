# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "async/semaphore"
require "console"
require "securerandom"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze

agent = A2A.agent do |env|
  case env["a2a.operation"]

  # -- SendMessage ---
  #
  # Two code paths:
  #   1. New task (no taskId): create task, plan research, ask for confirmation
  #   2. Continuation (taskId present): check if user confirmed, then complete or re-ask
  #
  in "SendMessage"
    request = env["a2a.request"]
    msg = request.message
    text = env["a2a.message"]

    task_id    = msg.task_id
    context_id = msg.context_id
    message_id = msg.message_id
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id

    if task_id && !task_id.empty?
      # -- Continuation: user is responding to INPUT_REQUIRED ---

      existing = LOCK.acquire { TASKS[task_id] }
      raise A2A::TaskNotFoundError.new(task_id) unless existing
      raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state") if TERMINAL_STATES.include?(existing[:state])
      raise A2A::UnsupportedOperationError.new(message: "Task is not awaiting input") unless existing[:state] == "TASK_STATE_INPUT_REQUIRED"

      # Record the user's follow-up message
      LOCK.acquire do
        TASKS[task_id][:history] << {
          "messageId" => message_id || SecureRandom.uuid,
          "role"      => "ROLE_USER",
          "parts"     => [{ "text" => text }],
        }
      end

      # Check if user confirmed
      if text.strip.downcase.include?("go ahead") || text.strip.downcase.include?("yes") || text.strip.downcase.include?("confirm")
        # -- User confirmed: complete the research ---

        # Extract the original topic from history
        original_msg = existing[:history].find { |m| m["role"] == "ROLE_USER" }
        topic = original_msg ? original_msg["parts"]&.first&.dig("text") : "the requested topic"

        artifact = {
          "artifactId" => SecureRandom.uuid,
          "name"       => "research-report",
          "parts"      => [{ "text" => "Research Report: #{topic}\n\n1. Background: #{topic} is a rapidly evolving field.\n2. Key findings: Multiple approaches exist.\n3. Recommendations: Further investigation warranted.\n\n[This is a simulated research output]" }],
        }

        task = LOCK.acquire do
          TASKS[task_id][:state] = "TASK_STATE_WORKING"
          TASKS[task_id][:updated_at] = NOW.()
          TASKS[task_id][:artifacts] << artifact
          TASKS[task_id][:history] << {
            "messageId" => SecureRandom.uuid,
            "role"      => "ROLE_AGENT",
            "parts"     => [{ "text" => "Research complete. See the attached report." }],
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
      else
        # -- User didn't confirm: re-ask ---
        agent_msg = {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "I didn't catch a confirmation. Please say 'go ahead' to proceed with the research, or describe what you'd like to change." }],
        }

        task = LOCK.acquire do
          TASKS[task_id][:history] << agent_msg
          TASKS[task_id][:state] = "TASK_STATE_INPUT_REQUIRED"
          TASKS[task_id][:updated_at] = NOW.()
          TASKS[task_id]
        end

        A2A::Protocol::JsonSchema["Send Message Response"].new(
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
      # -- New task: plan the research, ask for confirmation ---

      task_id = SecureRandom.uuid

      LOCK.acquire do
        TASKS[task_id] = { id: task_id, context_id: context_id, state: "TASK_STATE_SUBMITTED", updated_at: NOW.(), artifacts: [], history: [] }
        TASKS[task_id][:history] << {
          "messageId" => message_id || SecureRandom.uuid,
          "role"      => "ROLE_USER",
          "parts"     => [{ "text" => text }],
        }
      end

      # Transition: SUBMITTED -> WORKING -> INPUT_REQUIRED
      agent_msg = {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "I've prepared a research plan for: #{text}\n\nPlan:\n1. Survey existing literature\n2. Identify key themes and gaps\n3. Synthesize findings into a report\n\nSay 'go ahead' to proceed." }],
      }

      task = LOCK.acquire do
        TASKS[task_id][:state] = "TASK_STATE_WORKING"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id][:history] << agent_msg
        TASKS[task_id][:state] = "TASK_STATE_INPUT_REQUIRED"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id]
      end

      A2A::Protocol::JsonSchema["Send Message Response"].new(
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
  end
end

Console.info(self) { "Research Planner starting..." }
Console.info(self) { "Multi-turn example: INPUT_REQUIRED -> confirmation -> COMPLETED" }

run A2A::Server.new(agent_card: agent_card, agent: agent, history_length: 20)
