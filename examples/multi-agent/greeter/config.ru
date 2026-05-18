# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/store"
require "brute"
require "console"
require "securerandom"
require "yaml"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message["parts"] || []
  parts.filter_map { |p| p["text"] }.join("\n")
}

# ─── Brute Agent (LLM-powered) ───────────────────────────────────────

llm = Brute::Agent.new(
  provider: Brute.provider,
  model:    ENV.fetch("MODEL", "claude-sonnet-4-20250514"),
  tools:    [],
) do
  use Brute::Middleware::ToolResultLoop
  use Brute::Middleware::MaxIterations, max_iterations: 1
  run Brute::Middleware::LLMCall.new
end

# ─── Store ────────────────────────────────────────────────────────────

sqlite_store = A2A::Store::SQLite.new(path: "greeter.db")

# ─── A2A Agent ────────────────────────────────────────────────────────

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg["contextId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    store.create(task_id, context_id)

    # Call the LLM via Brute
    session = Brute::Session.new
    session.system("You are a creative greeting generator. Given a request, produce a warm, creative greeting. Keep it to 2-3 sentences. Just output the greeting, nothing else.")
    session.user(text)

    begin
      env = llm.call(session)
      response_text = session.last&.content || "Hello there!"
    rescue => e
      Console.error(self, "LLM call failed", e)
      response_text = "Hello! (LLM unavailable, but greetings from the Greeter Agent!)"
    end

    artifact = {
      "artifactId" => SecureRandom.uuid,
      "name"       => "greeting",
      "parts"      => [{ "text" => response_text }],
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
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card, store: sqlite_store)
app.register(agent)

Console.info(self) { "Greeter Agent starting on :9292..." }

run app
