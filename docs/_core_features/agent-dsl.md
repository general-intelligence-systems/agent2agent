---
layout: default
title: Agent Handler
nav_order: 3
description: This guide covers the pattern-matching handler block for building agents.
---

# Agent Handler

An agent is a single handler block passed to `A2A.agent` (or `A2A::Server.new` — `A2A.agent` is a shorthand). The block is the terminal Rack app: it receives the Rack env, routes operations with pattern matching, and returns a schema object that the binding layer formats into HTTP.

```ruby
run A2A.agent(agent_card: { "name" => "My Agent" }) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    A2A::Protocol::JsonSchema["Send Message Response"].new(task: { ... })
  in "GetTask"
    id   = env["a2a.request"].id
    task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)
    A2A::Protocol::JsonSchema["Task"].new(task)
  end
end
```

## Server Options

```ruby
A2A.agent(
  agent_card:     { "name" => "My Agent", ... },  # served at /.well-known/agent-card.json
  history_length: 100,                            # server cap for env["a2a.history_length"]
  page_size:      100,                            # server cap for env["a2a.page_size"]
) do |env|
  # ...
end
```

## The Env

Before your block runs, the server's middleware stack enriches the Rack env:

| Env key | Description |
|---------|-------------|
| `env["a2a.operation"]` | Operation name string (e.g. `"SendMessage"`, `"GetTask"`) |
| `env["a2a.request"]` | The validated `Schema::Definition` request (supports `deconstruct_keys` for pattern matching) |
| `env["a2a.message"]` | Joined text of the request message's parts (only set when the request carries a message) |
| `env["a2a.stream"]` | SSE stream builder — call `open(task_id:, context_id:)` to stream (see [Streaming]({% link _core_features/streaming.md %})) |
| `env["a2a.history_length"]` | Effective history limit: `min(client requested, server cap)`, always an Integer |
| `env["a2a.page_size"]` | Effective page size, clamped to `[1, server cap]` |
| `env["a2a.agent_card"]` | The agent card hash |

The request object exposes snake_case readers for its schema properties:

```ruby
in "SendMessage"
  request = env["a2a.request"]  # a "Send Message Request"
  request.message               # nested Definition
  request.message.task_id
  request.configuration

in "GetTask"
  request = env["a2a.request"]  # a "Get Task Request"
  request.id
  request.history_length
```

## Matching on Request Contents

To route on request contents as well as the operation, match a tuple — `Definition` implements `deconstruct_keys`, so patterns destructure recursively:

```ruby
case [env["a2a.operation"], env["a2a.request"]]
in ["SendMessage", { message: { task_id: String => id } }] if !id.empty?
  # continuation of task `id`
in ["SendMessage", _]
  # new task
end
```

## Errors

The block runs inside an error boundary:

- **Unmatched operation** — a `case ... in` with no matching branch raises `NoMatchingPatternError`, which becomes an `A2A::UnsupportedOperationError` (JSON-RPC `-32004`). You never need an `else` branch.
- **`A2A::Error` raised (or returned)** — formatted by the binding layer into the spec-compliant error response.
- **Anything else raised** — logged and returned as a JSON-RPC internal error (`-32603`, HTTP 500).

Raise the spec error classes from your handler:

```ruby
in "GetTask"
  id = env["a2a.request"].id
  task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)

in "CancelTask"
  # ...
  raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if terminal?(task)
```

| Error class | JSON-RPC | HTTP |
|-------------|----------|------|
| `A2A::TaskNotFoundError.new(task_id)` | -32001 | 404 |
| `A2A::TaskNotCancelableError.new(task_id, state:)` | -32002 | 400 |
| `A2A::PushNotificationNotSupportedError.new` | -32003 | 400 |
| `A2A::UnsupportedOperationError.new(message: "...")` | -32004 | 400 |
| `A2A::ContentTypeNotSupportedError.new(content_type)` | -32005 | 400 |
| `A2A::InvalidAgentResponseError.new` | -32006 | 500 |
| `A2A::ExtendedAgentCardNotConfiguredError.new` | -32007 | 400 |
| `A2A::ExtensionSupportRequiredError.new(extension)` | -32008 | 400 |
| `A2A::VersionNotSupportedError.new(version)` | -32009 | 400 |
| `A2A::InvalidParamsError.new(message, fields:)` | -32602 | 400 |

## The Middleware Stack

`A2A::Server` composes a single linear stack; each middleware handles the request or passes it downstream:

```
Env                 → injects env["a2a.agent_card"]
WellKnown           → serves /.well-known/agent-card.json
Bindings::Grpc      → /grpc (reserved) → 501 Not Implemented
Bindings::Rest      → /rest (HTTP+JSON/REST)
Bindings::JsonRpc   → everything else (JSON-RPC 2.0)
SSEStream           → offers env["a2a.stream"] to the agent
Triage              → resolves the operation, validates the request
ExtractMessage      → sets env["a2a.message"] when a message is present
LimitHistoryLength  → sets env["a2a.history_length"]
LimitPaginationSize → sets env["a2a.page_size"]
Agent               → the terminal app (your block)
```
