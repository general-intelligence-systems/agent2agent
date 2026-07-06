# Protocol Operations

This guide covers all 11 A2A operations and task state lifecycle.

## Operations

All 11 A2A operations are derived from the proto definition:

| Operation | REST | Streaming |
|-----------|------|-----------|
| SendMessage | `POST /rest/message:send` | No |
| SendStreamingMessage | `POST /rest/message:stream` | Yes |
| GetTask | `GET /rest/tasks/{id}` | No |
| ListTasks | `GET /rest/tasks` | No |
| CancelTask | `POST /rest/tasks/{id}:cancel` | No |
| SubscribeToTask | `GET /rest/tasks/{id}:subscribe` | Yes |
| CreateTaskPushNotificationConfig | `POST /rest/tasks/{task_id}/pushNotificationConfigs` | No |
| GetTaskPushNotificationConfig | `GET /rest/tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| ListTaskPushNotificationConfigs | `GET /rest/tasks/{task_id}/pushNotificationConfigs` | No |
| DeleteTaskPushNotificationConfig | `DELETE /rest/tasks/{task_id}/pushNotificationConfigs/{id}` | No |
| GetExtendedAgentCard | `GET /rest/extendedAgentCard` | No |

## Inspecting Operations

```ruby
A2A::Proto.operations.each do |op|
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
TASK_STATE_AUTH_REQUIRED     # Needs authentication
TASK_STATE_COMPLETED        # Done (terminal)
TASK_STATE_FAILED           # Error (terminal)
TASK_STATE_CANCELED         # Canceled (terminal)
TASK_STATE_REJECTED         # Refused (terminal)
```
