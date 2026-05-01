# agent2agent

A Ruby implementation of Google's [Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/) -- an open standard for interoperable communication between AI agents.

Build A2A-compliant agents that can communicate with any other A2A agent regardless of language or framework. Ships with server and client, both protocol bindings (JSON-RPC 2.0 and HTTP+JSON/REST), SSE streaming, SQLite persistence, and push notifications.

Runs on [Falcon](https://github.com/socketry/falcon) + [Async](https://github.com/socketry/async) -- pure fiber-based concurrency, no threads.

## Install

```ruby
gem "agent2agent"
```

Requires Ruby >= 3.2.

## Quick Start

### Minimal Agent

```ruby
# config.ru
require "a2a"

agent_card = {
  "name"    => "Echo Agent",
  "url"     => "http://localhost:9292",
  "version" => "1.0.0",
}

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    text = request.message.parts.first.text
    store.create(id = SecureRandom.uuid, SecureRandom.uuid)
    store.add_artifact(id, {
      "artifactId" => SecureRandom.uuid,
      "parts"      => [{ "text" => "Echo: #{text}" }],
    })
    store.complete(id, nil)
    task = store.get(id)

    respond A2A::Schema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state] },
        "artifacts" => task[:artifacts],
      }
    )
  end
end

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)
run app
```

```sh
bundle exec falcon serve --bind http://0.0.0.0:9292
```

The server exposes three endpoint groups automatically:

| Path | Purpose |
|------|---------|
| `/.well-known/agent-card.json` | Agent card discovery |
| `/a2a` | JSON-RPC 2.0 binding |
| `/*` | HTTP+JSON/REST binding |

### Calling It

```sh
# Discover
curl http://localhost:9292/.well-known/agent-card.json

# JSON-RPC
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello"}]}}}'

# REST
curl -X POST http://localhost:9292/message:send \
  -H "Content-Type: application/json" \
  -d '{"message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello"}]}}'
```

### Client

```ruby
Async do
  client = A2A::Client.new("http://localhost:9292")

  card = client.agent_card
  # => {"name"=>"Echo Agent", ...}

  result = client.send_message(
    message: {
      "messageId" => "msg-1",
      "role"      => "ROLE_USER",
      "parts"     => [{ "text" => "Hello" }],
    }
  )
  # => {"task"=>{"id"=>"...", "status"=>{"state"=>"TASK_STATE_COMPLETED"}, ...}}

  task = client.get_task(id: result.dig("task", "id"))
end
```

All 11 protocol operations are available as snake_case methods: `send_message`, `get_task`, `list_tasks`, `cancel_task`, `send_streaming_message`, `subscribe_to_task`, etc.

## Agent DSL

Handlers are registered with `on`. Inside a handler block you have access to:

| Helper | Description |
|--------|-------------|
| `request` | The validated `Schema::Definition` for this operation |
| `store` | The task store (in-memory or SQLite) |
| `agent_card` | The agent card hash |
| `respond(result)` | Set the response |
| `stream` | Create an SSE stream (auto-selects JSON-RPC or REST) |

```ruby
agent = A2A::Agent.new do
  on "SendMessage" do |request|
    # request.message, request.configuration, etc.
    respond A2A::Schema["Send Message Response"].new(task: { ... })
  end

  on "GetTask" do |request|
    task = store.get(request.id)
    respond A2A::Schema["Task"].new(id: task[:id], ...)
  end

  # Handle multiple operations with one block
  on "CancelTask" do |request|
    store.cancel(request.id)
    task = store.get(request.id)
    respond A2A::Schema["Task"].new(id: task[:id], ...)
  end
end

server = A2A::Server.new(agent_card: agent_card, store: store)
server.register(agent)
```

## Streaming

SSE streaming works natively with Falcon -- no threads, no polling. The `stream` helper auto-selects the right format based on the protocol binding.

```ruby
on "SendStreamingMessage" do |request|
  task_id = SecureRandom.uuid
  store.create(task_id, SecureRandom.uuid)
  s = stream

  Async do
    # Status update
    s.event({
      "task" => {
        "id"     => task_id,
        "status" => { "state" => "TASK_STATE_WORKING" },
      },
    })

    # Stream artifacts in chunks
    s.event({
      "artifactUpdate" => {
        "taskId"   => task_id,
        "artifact" => { "artifactId" => "a1", "name" => "output.txt",
                        "parts" => [{ "text" => "chunk 1..." }] },
        "append"    => false,
        "lastChunk" => false,
      },
    })

    s.event({
      "artifactUpdate" => {
        "taskId"   => task_id,
        "artifact" => { "artifactId" => "a1",
                        "parts" => [{ "text" => "chunk 2..." }] },
        "append"    => true,
        "lastChunk" => true,
      },
    })

    # Complete
    s.event({
      "statusUpdate" => {
        "taskId" => task_id,
        "status" => { "state" => "TASK_STATE_COMPLETED" },
      },
    })

    s.finish
  end
end
```

### Subscribe to Task Updates

Relay live updates from the store's pub/sub to an SSE stream:

```ruby
on "SubscribeToTask" do |request|
  task = store.get(request.id)
  sub_queue = store.subscribe(request.id)
  s = stream

  Async do
    # Initial snapshot
    s.event({ "task" => { "id" => task[:id], "status" => { "state" => task[:state] } } })

    # Relay live events
    while (event = sub_queue.dequeue)
      case event[:type]
      when :status  then s.event({ "statusUpdate" => event[:data] })
      when :artifact then s.event({ "artifactUpdate" => event[:data] })
      end

      state = event[:data].dig("status", "state")
      break if A2A::Store::SQLite::TERMINAL_STATES.include?(state)
    end

    s.finish
    store.unsubscribe(request.id, sub_queue)
  end
end
```

## Multi-Turn Conversations

Use `TASK_STATE_INPUT_REQUIRED` to pause execution and wait for user input:

```ruby
on "SendMessage" do |request|
  text = extract_text.(request.message)
  task_id = request.message.task_id

  if task_id
    # Continuation -- user is responding
    if text.downcase.include?("go ahead")
      store.update_state(task_id, "TASK_STATE_WORKING")
      # ... do the work ...
      store.complete(task_id, nil)
    else
      # Re-ask
      store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED",
        message: { "role" => "ROLE_AGENT",
                   "parts" => [{ "text" => "Please confirm." }] })
    end
  else
    # New task -- ask for confirmation
    task_id = SecureRandom.uuid
    store.create(task_id, SecureRandom.uuid)
    store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED",
      message: { "role" => "ROLE_AGENT",
                 "parts" => [{ "text" => "Here's my plan. Say 'go ahead' to proceed." }] })
  end

  task = store.get(task_id)
  respond A2A::Schema["Send Message Response"].new(task: { ... })
end
```

## Async Background Jobs

Use `Store::Processor` for non-blocking background work with `returnImmediately`:

```ruby
processor = A2A::Store::Processor.new

on "SendMessage" do |request|
  task_id = SecureRandom.uuid
  store.create(task_id, SecureRandom.uuid)

  return_immediately = request.configuration&.return_immediately

  work = proc do
    store.update_state(task_id, "TASK_STATE_WORKING")
    # ... long-running work ...
    store.complete(task_id, nil)
  end

  if return_immediately
    processor.call(&work)  # fire and forget
    task = store.get(task_id)
    respond A2A::Schema["Send Message Response"].new(
      task: { "id" => task_id, "status" => { "state" => "TASK_STATE_SUBMITTED" } }
    )
  else
    work.call  # blocking
    task = store.get(task_id)
    respond A2A::Schema["Send Message Response"].new(task: { ... })
  end
end
```

The client can then poll with `get_task` or subscribe with `subscribe_to_task` to track progress.

## Task Stores

### In-Memory (development)

```ruby
store = A2A::TaskStore.new
server = A2A::Server.new(agent_card: card, store: store)
```

### SQLite (production)

```ruby
require "a2a/store"

store = A2A::Store::SQLite.new(path: "agent.db")
server = A2A::Server.new(agent_card: card, store: store)
```

Both stores share the same interface:

```ruby
store.create(task_id, context_id)
store.get(task_id)                              # => Hash or nil
store.update_state(task_id, "TASK_STATE_WORKING", message: { ... })
store.add_artifact(task_id, { "artifactId" => "...", "parts" => [...] })
store.add_message(task_id, { "role" => "ROLE_AGENT", "parts" => [...] })
store.complete(task_id, result)
store.fail(task_id, "something went wrong")
store.cancel(task_id)
store.list(context_id: "ctx-1", state: "TASK_STATE_COMPLETED")

# Pub/sub (for SubscribeToTask)
queue = store.subscribe(task_id)
store.unsubscribe(task_id, queue)

# Push notification configs
store.create_push_config(task_id, config)
store.get_push_config(task_id, config_id)
store.list_push_configs(task_id)
store.delete_push_config(task_id, config_id)
```

## Schema Validation

All 47 A2A protocol types are available as validated Ruby objects via `A2A::Schema`:

```ruby
# Create validated protocol objects (accepts snake_case or camelCase)
card = A2A::Schema["Agent Card"].new(
  name: "My Agent",
  version: "1.0.0",
  capabilities: { streaming: true, push_notifications: false },
)
card.valid?              # => true
card.name                # => "My Agent"
card.capabilities        # => nested Definition
card.to_h                # => {"name"=>"My Agent", "version"=>"1.0.0", "capabilities"=>{"streaming"=>true, "pushNotifications"=>false}}

# Validation errors
bad = A2A::Schema["Agent Card"].new({})
bad.valid?               # => false
bad.valid!               # raises A2A::Schema::ValidationError with detailed messages

# List all available types
A2A::Schema.list_definitions
# => ["Agent Card", "Task", "Message", "Artifact", "Send Message Request", ...]
```

## Protocol Operations

All 11 A2A operations are derived from the proto definition:

| Operation | REST | Streaming |
|-----------|------|-----------|
| SendMessage | `POST /message:send` | No |
| SendStreamingMessage | `POST /message:stream` | Yes |
| GetTask | `GET /tasks/{id}` | No |
| ListTasks | `GET /tasks` | No |
| CancelTask | `POST /tasks/{id}:cancel` | No |
| SubscribeToTask | `GET /tasks/{id}:subscribe` | Yes |
| CreateTaskPushNotificationConfig | `POST /tasks/{task_id}/pushNotificationConfigs` | No |
| GetTaskPushNotificationConfig | `GET /tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| ListTaskPushNotificationConfigs | `GET /tasks/{task_id}/pushNotificationConfigs` | No |
| DeleteTaskPushNotificationConfig | `DELETE /tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| GetExtendedAgentCard | `GET /extendedAgentCard` | No |

```ruby
# Inspect operations programmatically
A2A::Proto.operations.each do |op|
  puts "#{op.name}: #{op.rest_verb.upcase} #{op.rest_path}"
  puts "  request:  #{op.request_type}"
  puts "  response: #{op.response_type}"
  puts "  streaming: #{op.server_streaming?}"
end
```

## Task States

```
TASK_STATE_SUBMITTED        # Acknowledged
TASK_STATE_WORKING          # Actively processing
TASK_STATE_INPUT_REQUIRED   # Needs more user input
TASK_STATE_AUTH_REQUIRED     # Needs authentication
TASK_STATE_COMPLETED        # Done (terminal)
TASK_STATE_FAILED           # Error (terminal)
TASK_STATE_CANCELED         # Canceled (terminal)
TASK_STATE_REJECTED         # Refused (terminal)
```

## Examples

Each example includes a `config.ru`, `Gemfile`, `Dockerfile`, and `docker-compose.yml`.

| Example | What it shows |
|---------|---------------|
| [`basic/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/basic) | Minimal echo agent, 2 operations |
| [`full/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/full) | All 11 operations, SQLite, SSE, push notifications |
| [`streaming-artifacts/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/streaming-artifacts) | Chunked artifact streaming with `append`/`lastChunk` |
| [`multi-turn/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-turn) | `INPUT_REQUIRED` for confirmation-gated conversations |
| [`async-jobs/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs) | Background processing with `returnImmediately` + polling/SSE |
| [`push-notifications/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/push-notifications) | Webhook delivery (2-service Docker setup) |
| [`multi-agent/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-agent) | LLM-powered orchestration routing to remote agents via `A2A::Client` |

Run any example:

```sh
cd examples/basic
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292

# or with Docker
docker compose up --build
```

## Development

```sh
bin/setup         # bundle install
bin/console       # IRB with A2A loaded
bin/test          # run inline tests (scampi)
bin/integration   # full protocol test against both bindings (requires Docker)
```

## License

MIT
