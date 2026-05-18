# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/store"
require "a2a/middleware"
require "brute"
require "console"
require "securerandom"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

llm = Brute::Agent.new(
  provider: Brute.provider,
  model:    ENV.fetch("MODEL", "claude-sonnet-4-20250514"),
  tools:    [],
) do
  use Brute::Middleware::ToolResultLoop
  use Brute::Middleware::MaxIterations, max_iterations: 1
  run Brute::Middleware::LLMCall.new
end

sqlite_store = A2A::Store::SQLite.new(path: "greeter.db")

agent = A2A::Agent.new do
  on "SendMessage" do
    use A2A::Middleware::ExtractMessage
    respond_with -> (env) {
      request = env["a2a.request"]
      msg = request.message
      text = env["a2a.message"]

      context_id = msg.context_id
      context_id = context_id.to_s.empty? ? SecureRandom.uuid : context_id
      task_id    = SecureRandom.uuid

      sqlite_store.create(task_id, context_id)

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

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Greeter Agent starting on :9292..." }

run app
