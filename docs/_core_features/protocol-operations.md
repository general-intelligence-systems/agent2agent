---
layout: default
title: Protocol Operations
nav_order: 6
description: Server handler and client call for every one of the 11 A2A protocol
  operations, plus the task state lifecycle.
---

# Protocol Operations

Every A2A operation, with a server handler branch and the matching client call. The 11 operations are derived from the proto definition:

| Operation | REST | Streaming |
|-----------|------|-----------|
| [SendMessage](#sendmessage) | `POST /rest/message:send` | No |
| [SendStreamingMessage](#sendstreamingmessage) | `POST /rest/message:stream` | Yes |
| [GetTask](#gettask) | `GET /rest/tasks/{id}` | No |
| [ListTasks](#listtasks) | `GET /rest/tasks` | No |
| [CancelTask](#canceltask) | `POST /rest/tasks/{id}:cancel` | No |
| [SubscribeToTask](#subscribetotask) | `GET /rest/tasks/{id}:subscribe` | Yes |
| [CreateTaskPushNotificationConfig](#createtaskpushnotificationconfig) | `POST /rest/tasks/{task_id}/pushNotificationConfigs` | No |
| [GetTaskPushNotificationConfig](#gettaskpushnotificationconfig) | `GET /rest/tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| [ListTaskPushNotificationConfigs](#listtaskpushnotificationconfigs) | `GET /rest/tasks/{task_id}/pushNotificationConfigs` | No |
| [DeleteTaskPushNotificationConfig](#deletetaskpushnotificationconfig) | `DELETE /rest/tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| [GetExtendedAgentCard](#getextendedagentcard) | `GET /rest/extendedAgentCard` | No |

The JSON-RPC binding sends every operation as `POST /` with the operation name as the JSON-RPC `method`. Full wire formats are in the [JSON-RPC]({% link _core_features/client-json-rpc.md %}) and [REST]({% link _core_features/client-rest.md %}) client guides. Every error your handlers can raise is covered in [Error Handling]({% link _core_features/error-handling.md %}).

The snippets below share a minimal in-memory store:

```ruby
TASKS = {}   # task_id => { id:, context_id:, state:, updated_at:, artifacts:, history:, push_configs: }
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.iso8601(3) }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze
```

## SendMessage

Send a message to the agent; the response carries a `task` (or a direct `message`).

Server:

```ruby
in "SendMessage"
  text    = env["a2a.message"]        # joined text of the message parts
  msg     = env["a2a.request"].message
  task_id = SecureRandom.uuid

  task = LOCK.acquire do
    TASKS[task_id] = {
      id: task_id, context_id: msg.context_id.to_s.empty? ? SecureRandom.uuid : msg.context_id,
      state: "TASK_STATE_COMPLETED", updated_at: NOW.(),
      artifacts: [{ "artifactId" => SecureRandom.uuid, "parts" => [{ "text" => "Echo: #{text}" }] }],
      history: [], push_configs: [],
    }
  end

  A2A::Protocol::JsonSchema["Send Message Response"].new(
    task: {
      "id"        => task[:id],
      "contextId" => task[:context_id],
      "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
      "artifacts" => task[:artifacts],
    }
  )
```

Client:

```ruby
response = client.send_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }
)
response.task.status.state # => "TASK_STATE_COMPLETED"
```

## SendStreamingMessage

Like SendMessage, but results arrive as SSE events. Open `env["a2a.stream"]` instead of returning a response object — see [Streaming]({% link _core_features/streaming.md %}).

Server:

```ruby
in "SendStreamingMessage"
  task_id    = SecureRandom.uuid
  context_id = SecureRandom.uuid

  env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
    s.task(status: { state: "TASK_STATE_WORKING", timestamp: NOW.() })
    s.artifact_update(
      artifact: { artifact_id: "a-1", parts: [{ text: "Echo: #{env["a2a.message"]}" }] },
      append: false, last_chunk: true,
    )
    s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: NOW.() })
  end
```

Client — the block receives each event as a `"Stream Response"` schema object:

```ruby
client.send_streaming_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }
) do |event|
  event.task            # initial snapshot events
  event.artifact_update # artifact chunks
  event.status_update   # state transitions
end
```

## GetTask

Fetch a task by ID. Honor `env["a2a.history_length"]` — the effective history cap (client requested, clamped to the server cap).

Server:

```ruby
in "GetTask"
  id    = env["a2a.request"].id
  limit = env["a2a.history_length"]

  task = LOCK.acquire { TASKS[id] }
  raise A2A::TaskNotFoundError.new(id) unless task

  A2A::Protocol::JsonSchema["Task"].new(
    id:         task[:id],
    context_id: task[:context_id],
    status:     { state: task[:state], timestamp: task[:updated_at] },
    artifacts:  task[:artifacts],
    history:    task[:history]&.last(limit),
  )
```

Client:

```ruby
task = client.get_task(id: "task-123")
task = client.get_task(id: "task-123", history_length: 5)
task.status.state # => "TASK_STATE_COMPLETED"
```

## ListTasks

List tasks with optional filters and pagination. Honor `env["a2a.page_size"]` and the request's `page_token`.

Server:

```ruby
in "ListTasks"
  request   = env["a2a.request"]
  page_size = env["a2a.page_size"]

  all = LOCK.acquire do
    TASKS.values.select do |t|
      (request.context_id.to_s.empty? || t[:context_id] == request.context_id) &&
      (request.status.to_s.empty?     || t[:state] == request.status)
    end
  end

  # Cursor pagination: page_token is the last task ID of the previous page
  if !request.page_token.to_s.empty?
    idx = all.index { |t| t[:id] == request.page_token }
    all = idx ? all[(idx + 1)..] : []
  end

  page = all.first(page_size)
  next_token = page.size == page_size && page.size < all.size ? page.last[:id] : ""

  A2A::Protocol::JsonSchema["List Tasks Response"].new(
    tasks: page.map { |t|
      { "id" => t[:id], "contextId" => t[:context_id],
        "status" => { "state" => t[:state], "timestamp" => t[:updated_at] } }
    },
    next_page_token: next_token,
    page_size:       page_size,
    total_size:      all.size,
  )
```

Client:

```ruby
result = client.list_tasks
result = client.list_tasks(context_id: "ctx-1", status: "TASK_STATE_WORKING")
result = client.list_tasks(page_size: 10, page_token: result.next_page_token)
result.tasks.map(&:id)
```

## CancelTask

Cancel a running task. Tasks in a terminal state are not cancelable.

Server:

```ruby
in "CancelTask"
  id   = env["a2a.request"].id
  task = LOCK.acquire { TASKS[id] }

  raise A2A::TaskNotFoundError.new(id) unless task
  raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if TERMINAL_STATES.include?(task[:state])

  task = LOCK.acquire do
    TASKS[id][:state] = "TASK_STATE_CANCELLED"
    TASKS[id][:updated_at] = NOW.()
    TASKS[id]
  end

  A2A::Protocol::JsonSchema["Task"].new(
    id:         task[:id],
    context_id: task[:context_id],
    status:     { state: task[:state], timestamp: task[:updated_at] },
  )
```

Client:

```ruby
task = client.cancel_task(id: "task-123")
task.status.state # => "TASK_STATE_CANCELLED"
```

## SubscribeToTask

Re-attach to a running task's event stream (e.g. after a dropped `SendStreamingMessage` connection). Streams the task's current snapshot, then subsequent updates.

Server:

```ruby
in "SubscribeToTask"
  id   = env["a2a.request"].id
  task = LOCK.acquire { TASKS[id] }
  raise A2A::TaskNotFoundError.new(id) unless task

  env["a2a.stream"].open(task_id: id, context_id: task[:context_id]) do |s|
    s.task(status: { state: task[:state], timestamp: task[:updated_at] })

    # Replay/relay updates until the task reaches a terminal state,
    # e.g. from a queue the background worker publishes to.
    until TERMINAL_STATES.include?(TASKS[id][:state])
      sleep 0.1
    end
    s.status_update(status: { state: TASKS[id][:state], timestamp: TASKS[id][:updated_at] })
  end
```

Client:

```ruby
client.subscribe_to_task(id: "task-123") do |event|
  event.status_update&.status&.state
end
```

## CreateTaskPushNotificationConfig

Register a webhook to be notified of task updates. The server is responsible for POSTing to the registered URL on state changes — the gem stores and returns configs; delivery is your handler's job (see the [push notifications example]({% link _examples/examples-push-notifications.md %})).

Server:

```ruby
in "CreateTaskPushNotificationConfig"
  request = env["a2a.request"]
  task    = LOCK.acquire { TASKS[request.task_id] }
  raise A2A::TaskNotFoundError.new(request.task_id) unless task

  config = request.to_h
  config.delete("taskId")
  config["id"] ||= SecureRandom.uuid

  LOCK.acquire { task[:push_configs] << config }

  A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)
```

Client:

```ruby
config = client.create_task_push_notification_config(
  task_id: "task-123",
  url:     "https://example.com/webhook",
  token:   "shared-secret",
)
config.id # => server-assigned config ID
```

## GetTaskPushNotificationConfig

Fetch a registered webhook config by ID.

Server:

```ruby
in "GetTaskPushNotificationConfig"
  request = env["a2a.request"]
  task    = LOCK.acquire { TASKS[request.task_id] }
  raise A2A::TaskNotFoundError.new(request.task_id) unless task

  config = task[:push_configs].find { |c| c["id"] == request.id }
  raise A2A::Internal::Errors::PushNotificationConfigNotFoundError.new(request.task_id, request.id) unless config

  A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)
```

Client:

```ruby
config = client.get_task_push_notification_config(id: "config-1", task_id: "task-123")
config.url # => "https://example.com/webhook"
```

## ListTaskPushNotificationConfigs

List all webhook configs registered for a task.

Server:

```ruby
in "ListTaskPushNotificationConfigs"
  request = env["a2a.request"]
  task    = LOCK.acquire { TASKS[request.task_id] }
  raise A2A::TaskNotFoundError.new(request.task_id) unless task

  A2A::Protocol::JsonSchema["List Task Push Notification Configs Response"].new(
    configs:         task[:push_configs],
    next_page_token: "",
  )
```

Client:

```ruby
result = client.list_task_push_notification_configs(task_id: "task-123")
result.configs.map(&:url)
```

## DeleteTaskPushNotificationConfig

Remove a webhook config. Return `nil` for the empty response.

Server:

```ruby
in "DeleteTaskPushNotificationConfig"
  request = env["a2a.request"]
  task    = LOCK.acquire { TASKS[request.task_id] }
  raise A2A::TaskNotFoundError.new(request.task_id) unless task

  LOCK.acquire { task[:push_configs].reject! { |c| c["id"] == request.id } }
  nil
```

Client:

```ruby
client.delete_task_push_notification_config(id: "config-1", task_id: "task-123")
# => {} (empty response)
```

## GetExtendedAgentCard

Serve a richer agent card to authenticated callers (the public card at `/.well-known/agent-card.json` is served by the gem automatically — this operation is only for the *extended* variant). Raise `ExtendedAgentCardNotConfiguredError` if you don't provide one.

Server:

```ruby
in "GetExtendedAgentCard"
  raise A2A::ExtendedAgentCardNotConfiguredError.new unless EXTENDED_CARD

  A2A::Protocol::JsonSchema["Agent Card"].new(EXTENDED_CARD)
```

Client:

```ruby
card = client.get_extended_agent_card
card.name
card.capabilities.extended_agent_card # => true
```

## Inspecting Operations

The operation table above is generated from the proto definition, which you can introspect at runtime:

```ruby
A2A::Protocol::Protobuf.operations.each do |op|
  puts "#{op.name}: #{op.rest_verb.upcase} #{op.rest_path}"
  puts "  request:  #{op.request_type}"
  puts "  response: #{op.response_type}"
  puts "  streaming: #{op.server_streaming?}"
end
```

## Task States

```ruby
TASK_STATE_SUBMITTED        # Acknowledged
TASK_STATE_WORKING          # Actively processing
TASK_STATE_INPUT_REQUIRED   # Needs more user input
TASK_STATE_AUTH_REQUIRED    # Needs authentication
TASK_STATE_COMPLETED        # Done (terminal)
TASK_STATE_FAILED           # Error (terminal)
TASK_STATE_CANCELED         # Canceled (terminal)
TASK_STATE_REJECTED         # Refused (terminal)
```
