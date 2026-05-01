# frozen_string_literal: true

# Translator Agent
#
# A simple agent that translates text into different languages using Brute (LLM-powered).
# Part of the multi-agent example demonstrating agent-to-agent orchestration.
#
# Runs on port 9293 inside Docker (http://translator:9293).

require "bundler/setup"
require "scampi"
require "a2a"
require "a2a/store"
require "brute"
require "console"
require "securerandom"

# ─── Agent Card ────────────────────────────────────────────────────────

agent_card = {
  "name"               => "Translator Agent",
  "description"        => "Translates text into different languages.",
  "version"            => "1.0.0",
  "supportedInterfaces" => [
    {
      "url"             => "http://translator:9293/a2a",
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
      "id"          => "translate",
      "name"        => "Language Translator",
      "description" => "Translates text into a specified language. Provide the text and target language.",
      "tags"        => ["translation", "language", "i18n"],
      "examples"    => ["Translate 'Hello world' to Spanish", "Say 'Good morning' in Japanese", "Translate this to French: I love programming"],
    },
  ],
}

# ─── Helpers ──────────────────────────────────────────────────────────

extract_text = ->(message) {
  parts = message.respond_to?(:parts) ? message.parts : (message["parts"] || [])
  parts.filter_map { |p| p.respond_to?(:text) ? p.text : p["text"] }.join("\n")
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

sqlite_store = A2A::Store::SQLite.new(path: "translator.db")

# ─── A2A Agent ────────────────────────────────────────────────────────

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    msg = request.message
    text = extract_text.(msg)

    context_id = msg.respond_to?(:context_id) ? msg.context_id : msg["contextId"]
    context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
    task_id    = SecureRandom.uuid

    store.create(task_id, context_id)

    # Call the LLM via Brute
    session = Brute::Session.new
    session.system("You are a translator. Given a translation request, produce the translation. Output only the translated text, nothing else. If no target language is specified, translate to Spanish.")
    session.user(text)

    begin
      env = llm.call(session)
      response_text = session.last&.content || text
    rescue => e
      Console.error(self) { "LLM call failed: #{e.message}" }
      response_text = "[Translation unavailable] #{text}"
    end

    artifact = {
      "artifactId" => SecureRandom.uuid,
      "name"       => "translation",
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

Console.info(self) { "Translator Agent starting on :9293..." }

run app
