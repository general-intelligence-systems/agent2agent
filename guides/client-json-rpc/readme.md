# Client — JSON-RPC Binding

```ruby
client = A2A::Client.new("http://localhost:9292")
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
  message: { "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }] }
)
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "SendMessage",
  "params": {
    "message": {
      "messageId": "msg-1",
      "role": "ROLE_USER",
      "parts": [{"text": "Hello"}]
    }
  }
}
```

## send_streaming_message

```ruby
client.send_streaming_message(
  message: { "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }] }
) do |chunk, env|
end
```

```
POST / HTTP/1.1
Content-Type: application/json
Accept: text/event-stream

{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "SendStreamingMessage",
  "params": {
    "message": {
      "messageId": "msg-1",
      "role": "ROLE_USER",
      "parts": [{"text": "Hello"}]
    }
  }
}
```

## get_task

```ruby
task = client.get_task(id: "task-123")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "GetTask",
  "params": {"id": "task-123"}
}
```

## list_tasks

```ruby
result = client.list_tasks
result = client.list_tasks(context_id: "ctx-1")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "ListTasks",
  "params": {}
}
```

## cancel_task

```ruby
task = client.cancel_task(id: "task-123")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "CancelTask",
  "params": {"id": "task-123"}
}
```

## subscribe_to_task

```ruby
client.subscribe_to_task(id: "task-123") do |chunk, env|
end
```

```
POST / HTTP/1.1
Content-Type: application/json
Accept: text/event-stream

{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "SubscribeToTask",
  "params": {"id": "task-123"}
}
```

## create_task_push_notification_config

```ruby
config = client.create_task_push_notification_config(
  task_id: "task-123", url: "https://example.com/webhook"
)
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "CreateTaskPushNotificationConfig",
  "params": {
    "taskId": "task-123",
    "url": "https://example.com/webhook"
  }
}
```

## get_task_push_notification_config

```ruby
config = client.get_task_push_notification_config(id: "config-1", task_id: "task-123")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "GetTaskPushNotificationConfig",
  "params": {"id": "config-1", "taskId": "task-123"}
}
```

## list_task_push_notification_configs

```ruby
result = client.list_task_push_notification_configs(task_id: "task-123")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "ListTaskPushNotificationConfigs",
  "params": {"taskId": "task-123"}
}
```

## delete_task_push_notification_config

```ruby
client.delete_task_push_notification_config(id: "config-1", task_id: "task-123")
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 10,
  "method": "DeleteTaskPushNotificationConfig",
  "params": {"id": "config-1", "taskId": "task-123"}
}
```

## get_extended_agent_card

```ruby
card = client.get_extended_agent_card
```

```
POST / HTTP/1.1
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 11,
  "method": "GetExtendedAgentCard",
  "params": {}
}
```
