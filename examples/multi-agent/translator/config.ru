# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "async/semaphore"
require "brute"
require "console"
require "securerandom"
require "yaml"

# --- Agent Card ----

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

# --- Brute Agent (LLM-powered) ---

llm = Brute::Agent.new(
  provider: Brute.provider,
  model:    ENV.fetch("MODEL", "claude-sonnet-4-20250514"),
  tools:    [],
) do
  use Brute::Middleware::ToolResultLoop
  use Brute::Middleware::MaxIterations, max_iterations: 1
  run Brute::Middleware::LLMCall.new
end

# --- Store ---

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }

# --- A2A Agent ---

agent = A2A.agent do |env|
  case env["a2a.operation"]
  in "SendMessage"
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

    task = LOCK.acquire do
      TASKS[task_id][:artifacts] << artifact
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
      }
    )
  end
end

# --- Boot ---

Console.info(self) { "Translator Agent starting on :9293..." }

run A2A::Server.new(agent_card: agent_card, agent: agent)
