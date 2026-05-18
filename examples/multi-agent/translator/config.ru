# frozen_string_literal: true

require "bundler/setup"
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
  parts = message.parts || []
  parts.filter_map { |p| p.text }.join("\n")
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
  on "SendMessage" do
    respond_with -> (env) {
      request = env["a2a.request"]
      msg = request.message
      text = extract_text.(msg)

      context_id = msg.context_id
      context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
      task_id    = SecureRandom.uuid

      sqlite_store.create(task_id, context_id)

      # Call the LLM via Brute
      session = Brute::Session.new
      session.system("You are a translator. Given a translation request, produce the translation. Output only the translated text, nothing else. If no target language is specified, translate to Spanish.")
      session.user(text)

      begin
        env = llm.call(session)
        response_text = session.last&.content || text
      rescue => e
        Console.error(self, "LLM call failed", e)
        response_text = "[Translation unavailable] #{text}"
      end

      artifact = {
        "artifactId" => SecureRandom.uuid,
        "name"       => "translation",
        "parts"      => [{ "text" => response_text }],
      }
      sqlite_store.add_artifact(task_id, artifact)
      sqlite_store.complete(task_id, nil)

      task = sqlite_store.get(task_id)
      A2A::Schema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
          "artifacts" => task[:artifacts],
        }
      )
    }
  end
end

# ─── Boot ──────────────────────────────────────────────────────────────

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Translator Agent starting on :9293..." }

run app
