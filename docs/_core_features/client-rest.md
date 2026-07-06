---
layout: default
title: Client — REST Binding
nav_order: 2
description: 'client = A2A::Client.new("http://localhost:9292", binding: :rest)'
---

# Client — REST Binding

```ruby
client = A2A::Client.new("http://localhost:9292", binding: :rest)
```

## agent_card

```ruby
card = client.agent_card
card.name    # => "Echo Agent"
card.version # => "1.0.0"
```

```
GET /.well-known/agent-card.json HTTP/1.1
```

## send_message

```ruby
result = client.send_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "Hello" }] }
)
```

```
POST /rest/message:send HTTP/1.1
Content-Type: application/a2a+json

{
  "message": {
    "messageId": "msg-1",
    "role": "ROLE_USER",
    "parts": [{"text": "Hello"}]
  }
}
```

## send_streaming_message

```ruby
client.send_streaming_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "Hello" }] }
) do |event|
  # each SSE event parsed into a "Stream Response" schema object
end
```

```
POST /rest/message:stream HTTP/1.1
Content-Type: application/a2a+json
Accept: text/event-stream

{
  "message": {
    "messageId": "msg-1",
    "role": "ROLE_USER",
    "parts": [{"text": "Hello"}]
  }
}
```

## get_task

```ruby
task = client.get_task(id: "task-123")
```

```
GET /rest/tasks/task-123 HTTP/1.1
```

## list_tasks

```ruby
result = client.list_tasks
result = client.list_tasks(context_id: "ctx-1")
```

```
GET /rest/tasks HTTP/1.1
```

## cancel_task

```ruby
task = client.cancel_task(id: "task-123")
```

```
POST /rest/tasks/task-123:cancel HTTP/1.1
Content-Type: application/a2a+json
```

## subscribe_to_task

```ruby
client.subscribe_to_task(id: "task-123") do |event|
end
```

```
GET /rest/tasks/task-123:subscribe HTTP/1.1
Accept: text/event-stream
```

## create_task_push_notification_config

```ruby
config = client.create_task_push_notification_config(
  task_id: "task-123", url: "https://example.com/webhook"
)
```

```
POST /rest/tasks/task-123/pushNotificationConfigs HTTP/1.1
Content-Type: application/a2a+json

{
  "url": "https://example.com/webhook"
}
```

## get_task_push_notification_config

```ruby
config = client.get_task_push_notification_config(id: "config-1", task_id: "task-123")
```

```
GET /rest/tasks/task-123/pushNotificationConfigs/config-1 HTTP/1.1
```

## list_task_push_notification_configs

```ruby
result = client.list_task_push_notification_configs(task_id: "task-123")
```

```
GET /rest/tasks/task-123/pushNotificationConfigs HTTP/1.1
```

## delete_task_push_notification_config

```ruby
client.delete_task_push_notification_config(id: "config-1", task_id: "task-123")
```

```
DELETE /rest/tasks/task-123/pushNotificationConfigs/config-1 HTTP/1.1
```

## get_extended_agent_card

```ruby
card = client.get_extended_agent_card
```

```
GET /rest/extendedAgentCard HTTP/1.1
```
