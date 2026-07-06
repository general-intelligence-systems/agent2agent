---
layout: default
title: Error Handling
nav_order: 8
description: Raising every A2A protocol error from your handler, what each looks
  like on the wire, and rescuing every client-side error class.
---

# Error Handling

Every error the protocol defines, from both sides: raising each one in a server handler, what it looks like on the wire, and rescuing each error class in the client.

## The Error Boundary

Your handler block runs inside an error boundary (`A2A::Agent`):

- **Unmatched operation** — a `case ... in` with no matching branch raises `NoMatchingPatternError`, which becomes `A2A::UnsupportedOperationError` (`-32004`). You never need an `else` branch.
- **`A2A::Error` raised (or returned)** — formatted by the binding layer into the spec-compliant error response. Raising and returning are equivalent; raise from deep in helper code, return when it reads better.
- **Anything else raised** — logged and returned as a JSON-RPC internal error (`-32603`, HTTP 500). The exception details never leak to the client.

## Raising Every Protocol Error

Each spec error is an `A2A::Error` subclass carrying its JSON-RPC code, HTTP status (for the REST binding), and structured `google.rpc.ErrorInfo` detail data. In handler context:

### TaskNotFoundError — `-32001` / HTTP 404

The task ID doesn't correspond to an existing or accessible task:

```ruby
in "GetTask"
  id   = env["a2a.request"].id
  task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)
```

### TaskNotCancelableError — `-32002` / HTTP 400

The task is already in a terminal state:

```ruby
in "CancelTask"
  id   = env["a2a.request"].id
  task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)

  if TERMINAL_STATES.include?(task[:state])
    raise A2A::TaskNotCancelableError.new(id, state: task[:state])
  end
```

### PushNotificationNotSupportedError — `-32003` / HTTP 400

The client used push notification operations but your agent card declares `capabilities.pushNotifications: false`:

```ruby
in "CreateTaskPushNotificationConfig"
  unless env["a2a.agent_card"].dig("capabilities", "pushNotifications")
    raise A2A::PushNotificationNotSupportedError.new
  end
```

### UnsupportedOperationError — `-32004` / HTTP 400

Returned automatically for any operation your `case` doesn't match. Raise it explicitly to refuse a *variant* of an operation you otherwise support:

```ruby
in "SendMessage"
  msg = env["a2a.request"].message
  if msg.task_id && TERMINAL_STATES.include?(TASKS[msg.task_id]&.dig(:state))
    raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state")
  end
```

### ContentTypeNotSupportedError — `-32005` / HTTP 400

A media type in the request's message parts isn't supported by the agent:

```ruby
in "SendMessage"
  env["a2a.request"].message.parts.each do |part|
    media_type = part.media_type
    next if media_type.to_s.empty? || media_type == "text/plain"

    raise A2A::ContentTypeNotSupportedError.new(media_type)
  end
```

### InvalidAgentResponseError — `-32006` / HTTP 500

A downstream agent returned something that doesn't conform to the spec — typically raised by orchestrators that delegate over `A2A::Client`:

```ruby
in "SendMessage"
  result = A2A::Client.new(REMOTE_AGENT_URL).send_message(message: forwarded)
  task = result.task or raise A2A::InvalidAgentResponseError.new(
    message: "Remote agent returned no task"
  )
```

### ExtendedAgentCardNotConfiguredError — `-32007` / HTTP 400

`GetExtendedAgentCard` was called but you don't provide one:

```ruby
in "GetExtendedAgentCard"
  raise A2A::ExtendedAgentCardNotConfiguredError.new unless EXTENDED_CARD
  A2A::Protocol::JsonSchema["Agent Card"].new(EXTENDED_CARD)
```

### ExtensionSupportRequiredError — `-32008` / HTTP 400

Your agent card marks an extension `required: true` but the client didn't declare support for it:

```ruby
in "SendMessage"
  declared = env["a2a.request"].message&.extensions || []
  unless declared.include?("https://example.com/ext/geo-coordinates/v1")
    raise A2A::ExtensionSupportRequiredError.new("https://example.com/ext/geo-coordinates/v1")
  end
```

### VersionNotSupportedError — `-32009` / HTTP 400

The client requested a protocol version (via the `A2A-Version` header) you don't support:

```ruby
version = env["HTTP_A2A_VERSION"]
if version && version != "1.0"
  raise A2A::VersionNotSupportedError.new(version)
end
```

### InvalidParamsError — `-32602` / HTTP 400

Structurally valid params that fail your semantic validation. (Schema validation is already done by the middleware before your block runs — this is for rules the schema can't express.)

```ruby
in "SendMessage"
  text = env["a2a.message"]
  if text.to_s.strip.empty?
    raise A2A::InvalidParamsError.new("message must contain non-empty text", fields: ["message.parts"])
  end
```

### Internal::Errors::PushNotificationConfigNotFoundError — `-32001` / HTTP 404

The task exists but the requested push config ID doesn't. Not a spec error — an implementation detail this library provides (it reports on the wire as `TASK_NOT_FOUND`):

```ruby
in "GetTaskPushNotificationConfig"
  request = env["a2a.request"]
  task    = TASKS[request.task_id] or raise A2A::TaskNotFoundError.new(request.task_id)

  config = task[:push_configs].find { |c| c["id"] == request.id }
  unless config
    raise A2A::Internal::Errors::PushNotificationConfigNotFoundError.new(request.task_id, request.id)
  end
```

### Custom Errors — base `A2A::Error`

For conditions the spec doesn't name, construct the base class with your own code and HTTP status:

```ruby
raise A2A::Error.new("Agent is overloaded, retry later", code: -32000, http_status: 503)
```

### Summary

| Error class | JSON-RPC | HTTP | Raised when |
|-------------|----------|------|-------------|
| `A2A::TaskNotFoundError.new(task_id)` | -32001 | 404 | Unknown/expired task ID |
| `A2A::TaskNotCancelableError.new(task_id, state:)` | -32002 | 400 | Cancel on a terminal-state task |
| `A2A::PushNotificationNotSupportedError.new` | -32003 | 400 | Push ops without the capability |
| `A2A::UnsupportedOperationError.new(message: "...")` | -32004 | 400 | Unmatched operation (automatic) or refused variant |
| `A2A::ContentTypeNotSupportedError.new(content_type)` | -32005 | 400 | Unsupported media type in parts |
| `A2A::InvalidAgentResponseError.new` | -32006 | 500 | Downstream agent returned junk |
| `A2A::ExtendedAgentCardNotConfiguredError.new` | -32007 | 400 | No extended card configured |
| `A2A::ExtensionSupportRequiredError.new(extension)` | -32008 | 400 | Required extension not declared |
| `A2A::VersionNotSupportedError.new(version)` | -32009 | 400 | Unsupported `A2A-Version` |
| `A2A::InvalidParamsError.new(message, fields:)` | -32602 | 400 | Semantic validation failure |
| `A2A::Internal::Errors::PushNotificationConfigNotFoundError.new(task_id, config_id)` | -32001 | 404 | Unknown push config ID |
| `A2A::Error.new(message, code:, http_status:)` | custom | custom | Anything else |

## On the Wire

The JSON-RPC binding delivers errors inside the envelope, always over HTTP 200:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "Task not found",
    "data": [{
      "@type": "type.googleapis.com/google.rpc.ErrorInfo",
      "reason": "TASK_NOT_FOUND",
      "domain": "a2a-protocol.org",
      "metadata": {"taskId": "task-123"}
    }]
  }
}
```

The REST binding uses the error's HTTP status with an `application/problem+json` body:

```json
{
  "type": "error",
  "title": "Task not found",
  "status": 404,
  "detail": [{
    "@type": "type.googleapis.com/google.rpc.ErrorInfo",
    "reason": "TASK_NOT_FOUND",
    "domain": "a2a-protocol.org",
    "metadata": {"taskId": "task-123"}
  }]
}
```

## Handling Errors Client-Side

`A2A::Client` raises one error class per binding, plus a local validation error. All three:

### A2A::JsonRpcError (JSON-RPC binding)

Raised when the server returns a JSON-RPC error envelope. `code` is the protocol code; `http_status` is always 200 (the error lives in the envelope, not the HTTP status):

```ruby
client = A2A::Client.new(url) # binding: :json_rpc is the default

begin
  client.get_task(id: "no-such-task")
rescue A2A::JsonRpcError => e
  e.code                              # => -32001
  e.message                           # => "Task not found"
  e.error_data&.first&.dig("reason")  # => "TASK_NOT_FOUND"
  e.error_data&.first&.dig("metadata", "taskId") # => "no-such-task"
end
```

### A2A::RestError (REST binding)

Raised on any HTTP 4xx/5xx with a problem+json body. `http_status` (and `code`) carry the HTTP status:

```ruby
client = A2A::Client.new(url, binding: :rest)

begin
  client.get_task(id: "no-such-task")
rescue A2A::RestError => e
  e.http_status                       # => 404
  e.message                           # => "Task not found"
  e.error_data&.first&.dig("reason")  # => "TASK_NOT_FOUND"
end
```

### Binding-Agnostic Handling

When the binding is configurable (as in the [Rails integration test]({% link _core_features/rails-and-rack-hosts.md %}#testing-agents-over-real-http)), rescue both:

```ruby
begin
  client.cancel_task(id: "task-abc")
rescue A2A::JsonRpcError, A2A::RestError => e
  e.message # => "Operation not supported: CancelTask"
end
```

Both are `A2A::Error` subclasses, so `rescue A2A::Error` also works — but that additionally catches `A2A::Protocol::JsonSchema::ValidationError` below, which usually indicates a bug in *your* code rather than a server-reported condition.

### A2A::Protocol::JsonSchema::ValidationError (local)

Raised *before anything is sent* when the request params don't validate against the operation's request schema:

```ruby
begin
  client.send_message(message: "not a hash")
rescue A2A::Protocol::JsonSchema::ValidationError => e
  e.message # describes which schema property failed
end
```

### Transport Errors

Connection refused, DNS failure, and timeouts surface as ordinary `Faraday` exceptions (e.g. `Faraday::ConnectionFailed`) — rescue them separately if the remote agent may be unreachable:

```ruby
begin
  client.agent_card
rescue Faraday::Error => e
  # remote agent down / unreachable
end
```
