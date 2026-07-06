---
layout: default
title: Getting Started
nav_order: 1
description: This guide walks you through installing agent2agent, building a minimal
  agent, and calling it from both curl and Ruby.
---

# Getting Started

This guide walks you through installing agent2agent, building a minimal agent, and calling it from both curl and Ruby.

## Installation

```ruby
gem "agent2agent"
```

Requires Ruby >= 3.2.

## Minimal Agent

`A2A.agent` builds a complete A2A server (a Rack app) from a single handler block. The block receives the Rack env and routes operations with pattern matching. It returns a schema object (`A2A::Protocol::JsonSchema::Definition`) — the binding layer formats it into HTTP.

```ruby
# config.ru
require "a2a"
require "securerandom"

TASKS = {}

agent_card = {
  "name"    => "Echo Agent",
  "url"     => "http://localhost:9292",
  "version" => "1.0.0",
}

run A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    text    = env["a2a.message"]  # extracted text of the message parts
    task_id = SecureRandom.uuid

    TASKS[task_id] = {
      "id"        => task_id,
      "contextId" => SecureRandom.uuid,
      "status"    => { "state" => "TASK_STATE_COMPLETED" },
      "artifacts" => [{
        "artifactId" => SecureRandom.uuid,
        "parts"      => [{ "text" => "Echo: #{text}" }],
      }],
    }

    A2A::Protocol::JsonSchema["Send Message Response"].new(task: TASKS[task_id])

  in "GetTask"
    id   = env["a2a.request"].id
    task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)

    A2A::Protocol::JsonSchema["Task"].new(task)
  end
end
```

Any operation the `case` doesn't match falls out with `NoMatchingPatternError`, which the server converts to a spec-compliant `UnsupportedOperationError` (JSON-RPC code `-32004`). Raising an `A2A::Error` subclass (like `A2A::TaskNotFoundError` above) produces the corresponding protocol error response.

```bash
bundle exec falcon serve --bind http://0.0.0.0:9292
```

The server exposes these endpoint groups automatically:

| Path | Purpose |
|------|---------|
| `/.well-known/agent-card.json` | Agent card discovery |
| `/` | JSON-RPC 2.0 binding |
| `/rest/*` | HTTP+JSON/REST binding |
| `/grpc` | gRPC binding (reserved — returns 501 Not Implemented) |

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

The client validates request params against the operation's schema before sending, and returns responses as schema objects (with snake_case readers):

```ruby
require "a2a"

Async do
  client = A2A::Client.new("http://localhost:9292")

  card = client.agent_card
  card.name    # => "Echo Agent"
  card.version # => "1.0.0"

  result = client.send_message(
    message: {
      message_id: "msg-1",
      role:       "ROLE_USER",
      parts:      [{ text: "Hello" }],
    }
  )
  result.task.status.state # => "TASK_STATE_COMPLETED"

  task = client.get_task(id: result.task.id)
end
```

All 11 protocol operations are available as snake_case methods: `send_message`, `get_task`, `list_tasks`, `cancel_task`, `send_streaming_message`, `subscribe_to_task`, etc. Pass `binding: :rest` to `A2A::Client.new` to use the REST binding instead of JSON-RPC.

## Mounting in a Host App

An agent doesn't need its own process — `A2A.agent` returns a plain Rack app, so it mounts directly in Rails routes (or any Rack host):

```ruby
# config/routes.rb
Rails.application.routes.draw do
  echo_agent = A2A.agent(agent_card: { "name" => "Echo Agent" }) do |env|
    case env["a2a.operation"]
    in "SendMessage"
      A2A::Protocol::JsonSchema["Send Message Response"].new({})
    end
  end

  mount echo_agent, at: "/echo"
end
```

See [Rails & Rack Hosts]({% link _core_features/rails-and-rack-hosts.md %}) for multiple agents, streaming, and testing over real HTTP.
