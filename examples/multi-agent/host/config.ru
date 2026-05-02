# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/store"
require "brute"
require "console"
require "securerandom"
require "async"
require "json"

# ─── Remote Agent Discovery ──────────────────────────────────────────

REMOTE_AGENTS = {
  "greeter"    => "http://greeter:9292",
  "translator" => "http://translator:9293",
}

# Discover remote agent cards at startup
remote_cards = {}

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = {
  "name"               => "Host Orchestrator",
  "description"        => "An LLM-powered orchestrator that discovers remote agents and delegates tasks to the most appropriate one.",
  "version"            => "1.0.0",
  "supportedInterfaces" => [
    {
      "url"             => "http://localhost:9294/a2a",
      "protocolBinding" => "JSONRPC",
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
      "id"          => "orchestrate",
      "name"        => "Multi-Agent Orchestrator",
      "description" => "Routes user requests to the most appropriate remote agent. Available agents: Greeter (creative greetings) and Translator (language translation).",
      "tags"        => ["orchestration", "multi-agent", "routing"],
      "examples"    => [
        "Greet Alice for her birthday",
        "Translate 'Hello' to French",
        "Welcome the new team member Bob",
        "Say 'Good morning' in Japanese",
      ],
    },
  ],
}

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message.respond_to?(:parts) ? message.parts : (message["parts"] || [])
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
}

# ─── LLM Router (Brute-powered) ──────────────────────────────────────

router_llm = Brute::Agent.new(
  provider: Brute.provider,
  model:    ENV.fetch("MODEL", "claude-sonnet-4-20250514"),
  tools:    [],
) do
  use Brute::Middleware::ToolResultLoop
  use Brute::Middleware::MaxIterations, max_iterations: 1
  run Brute::Middleware::LLMCall.new
end

# ─── Store ────────────────────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "host.db")

# ─── Agent ────────────────────────────────────────────────────────────

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    store.create(task_id, context_id)
    store.update_state(task_id, "TASK_STATE_WORKING")

    # Step 1: Discover remote agents (lazy, cached)
    REMOTE_AGENTS.each do |name, url|
      next if remote_cards[name]
      begin
        client = A2A::Client.new(url)
        remote_cards[name] = client.agent_card
        Console.info(self) { "Discovered agent: #{remote_cards[name]["name"]} at #{url}" }
      rescue => e
        Console.warn(self, "Failed to discover #{name} at #{url}", e)
      end
    end

    # Step 2: Use LLM to decide which agent to route to
    agent_descriptions = remote_cards.map do |name, card|
      skills = (card["skills"] || []).map { |s| "  - #{s["name"]}: #{s["description"]}" }.join("\n")
      "Agent '#{name}' (#{card["name"]}): #{card["description"]}\nSkills:\n#{skills}"
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
      # No suitable agent found — respond directly
      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "response",
        "parts"      => [{ "text" => "I couldn't determine which agent should handle your request: '#{text}'. Available agents are: #{remote_cards.keys.join(", ")}." }],
      }
      store.add_artifact(task_id, artifact)
      store.complete(task_id, nil)

      task = store.get(task_id)
      respond A2A::Schema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
          "artifacts" => task[:artifacts],
        }
      )
      next
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
      remote_task = result["task"] || result
      remote_artifacts = remote_task["artifacts"] || []
      remote_text = remote_artifacts
        .flat_map { |a| a["parts"] || [] }
        .filter_map { |p| p["text"] }
        .join("\n")

      remote_text = "#{chosen_agent} agent returned no response." if remote_text.empty?

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "delegated-response",
        "description" => "Response from #{chosen_agent} agent",
        "parts"      => [{ "text" => remote_text }],
        "metadata"   => { "delegatedTo" => chosen_agent, "remoteTaskId" => remote_task["id"] },
      }
      store.add_artifact(task_id, artifact)
      store.add_message(task_id, {
        "messageId" => SecureRandom.uuid,
        "role"      => "ROLE_AGENT",
        "parts"     => [{ "text" => "[Delegated to #{chosen_agent}] #{remote_text}" }],
      })
      store.complete(task_id, nil)
    rescue => e
      Console.error(self, "Delegation to #{chosen_agent} failed", e)

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "error",
        "parts"      => [{ "text" => "Failed to delegate to #{chosen_agent}: #{e.message}" }],
      }
      store.add_artifact(task_id, artifact)
      store.fail(task_id, e.message)
    end

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

  # ── GetTask ──────────────────────────────────────────────────────────
  on "GetTask" do |request|
    id = request.id
    task = store.get(id)

    unless task
      respond nil
      @env["a2a.error"] = { code: -32001, message: "Task not found" }
      next
    end

    respond A2A::Schema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { "state" => task[:state], "timestamp" => task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history],
    )
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Host Orchestrator starting on :9294..." }
Console.info(self) { "Remote agents: #{REMOTE_AGENTS.map { |k,v| "#{k}=#{v}" }.join(", ")}" }

run app
