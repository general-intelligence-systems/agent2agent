# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "async/semaphore"
require "brute"
require "console"
require "securerandom"
require "async"
require "json"
require "yaml"

# --- Remote Agent Discovery ---

REMOTE_AGENTS = {
  "greeter"    => "http://greeter:9292",
  "translator" => "http://translator:9293",
}

remote_cards = {}

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

router_llm = Brute::Agent.new(
  provider: Brute.provider,
  model:    ENV.fetch("MODEL", "claude-sonnet-4-20250514"),
  tools:    [],
) do
  use Brute::Middleware::ToolResultLoop
  use Brute::Middleware::MaxIterations, max_iterations: 1
  run Brute::Middleware::LLMCall.new
end

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

agent = A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    request = env["a2a.request"]
    msg = request.message
    text = env["a2a.message"]

    context_id = msg.context_id
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    LOCK.acquire do
      TASKS[task_id] = { id: task_id, context_id: context_id, state: "TASK_STATE_WORKING", updated_at: NOW.(), artifacts: [], history: [] }
    end

    # Step 1: Discover remote agents (lazy, cached)
    REMOTE_AGENTS.each do |name, url|
      next if remote_cards[name]
      begin
        client = A2A::Client.new(url)
        remote_cards[name] = client.agent_card
        Console.info(self) { "Discovered agent: #{remote_cards[name].name} at #{url}" }
      rescue => e
        Console.warn(self, "Failed to discover #{name} at #{url}", e)
      end
    end

    # Step 2: Use LLM to decide which agent to route to
    agent_descriptions = remote_cards.map do |name, card|
      skills = (card.skills || []).map { |s| "  - #{s.name}: #{s.description}" }.join("\n")
      "Agent '#{name}' (#{card.name}): #{card.description}\nSkills:\n#{skills}"
    end.join("\n\n")

    session = Brute::Session.new
    session.system(<<~PROMPT)
      You are a routing agent. Given a user request, decide which remote agent should handle it.

      Available agents:
      #{agent_descriptions}

      Respond with ONLY the agent name (one of: #{remote_cards.keys.join(", ")}). Nothing else.
      If no agent is a good fit, respond with "none".
    PROMPT
    session.user(text)

    chosen_agent = nil
    begin
      router_llm.call(session)
      choice = session.last&.content&.strip&.downcase || "none"
      chosen_agent = choice if remote_cards.key?(choice)
    rescue => e
      Console.error(self, "Router LLM failed", e)
    end

    if chosen_agent.nil?
      # No suitable agent found -- respond directly
      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "response",
        "parts"      => [{ "text" => "I couldn't determine which agent should handle your request: '#{text}'. Available agents are: #{remote_cards.keys.join(", ")}." }],
      }

      task = LOCK.acquire do
        TASKS[task_id][:artifacts] << artifact
        TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id]
      end

      next A2A::Protocol::JsonSchema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
          "artifacts" => task[:artifacts],
        }
      )
    end

    # Step 3: Delegate to the chosen agent via A2A::Client
    Console.info(self) { "Routing to '#{chosen_agent}' for: #{text}" }

    begin
      client = A2A::Client.new(REMOTE_AGENTS[chosen_agent])
      result = client.send_message(
        message: {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_USER",
          "parts"     => [{ "text" => text }],
          "contextId" => context_id,
        }
      )

      # Extract the remote agent's response
      remote_task = result.task || result
      remote_artifacts = remote_task.artifacts || []
      remote_text = remote_artifacts
        .flat_map { |a| a.parts || [] }
        .filter_map { |p| p.text }
        .join("\n")

      remote_text = "#{chosen_agent} agent returned no response." if remote_text.empty?

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "delegated-response",
        "description" => "Response from #{chosen_agent} agent",
        "parts"      => [{ "text" => remote_text }],
        "metadata"   => { "delegatedTo" => chosen_agent, "remoteTaskId" => remote_task.id },
      }

      LOCK.acquire do
        TASKS[task_id][:artifacts] << artifact
        TASKS[task_id][:history] << {
          "messageId" => SecureRandom.uuid,
          "role"      => "ROLE_AGENT",
          "parts"     => [{ "text" => "[Delegated to #{chosen_agent}] #{remote_text}" }],
        }
        TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
        TASKS[task_id][:updated_at] = NOW.()
      end
    rescue => e
      Console.error(self, "Delegation to #{chosen_agent} failed", e)

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "error",
        "parts"      => [{ "text" => "Failed to delegate to #{chosen_agent}: #{e.message}" }],
      }

      LOCK.acquire do
        TASKS[task_id][:artifacts] << artifact
        TASKS[task_id][:state] = "TASK_STATE_FAILED"
        TASKS[task_id][:updated_at] = NOW.()
      end
    end

    task = LOCK.acquire { TASKS[task_id] }

    A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        "artifacts" => task[:artifacts],
        "history"   => task[:history],
      }
    )
  in "GetTask"
    request = env["a2a.request"]
    id = request.id

    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history],
    )
  end
end

Console.info(self) { "Host Orchestrator starting on :9294..." }
Console.info(self) { "Remote agents: #{REMOTE_AGENTS.map { |k,v| "#{k}=#{v}" }.join(", ")}" }

run agent
