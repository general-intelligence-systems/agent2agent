# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/middleware"
require "async/semaphore"
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

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

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

      LOCK.acquire do
        TASKS[task_id] = { id: task_id, context_id: context_id, state: "TASK_STATE_SUBMITTED", updated_at: NOW.(), artifacts: [], history: [] }
      end

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

      task = LOCK.acquire do
        TASKS[task_id][:artifacts] << artifact
        TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
        TASKS[task_id][:updated_at] = NOW.()
        TASKS[task_id]
      end

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
