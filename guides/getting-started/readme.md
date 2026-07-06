# Getting Started

This guide walks you through installing agent2agent, building a minimal agent, and calling it from both curl and Ruby.

## Installation

```ruby
gem "agent2agent"
```

Requires Ruby >= 3.2.

## Minimal Agent

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

```bash
bundle exec falcon serve --bind http://0.0.0.0:9292
```

The server exposes three endpoint groups automatically:

| Path | Purpose |
|------|---------|
| `/.well-known/agent-card.json` | Agent card discovery |
| `/` | JSON-RPC 2.0 binding |
| `/rest/*` | HTTP+JSON/REST binding |
| `/grpc` | gRPC binding (reserved, not yet implemented) |

## Calling It

```bash
# Discover
curl http://localhost:9292/.well-known/agent-card.json

# JSON-RPC
curl -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello"}]}}}'

# REST
curl -X POST http://localhost:9292/rest/message:send \
  -H "Content-Type: application/json" \
  -d '{"message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello"}]}}'
```

## Client

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
