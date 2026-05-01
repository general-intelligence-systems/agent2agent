# Full Echo Agent

Demonstrates all 11 A2A protocol operations in a single agent with Falcon-native SSE streaming and a SQLite-backed persistent task store.

## What it demonstrates

All 11 A2A operations:

1. **SendMessage** -- echo with task creation and continuation
2. **SendStreamingMessage** -- SSE streaming via `Protocol::HTTP::Body::Writable`
3. **GetTask** -- retrieve task by ID with optional history truncation
4. **ListTasks** -- paginated task listing with filters
5. **CancelTask** -- cancel in-progress tasks
6. **SubscribeToTask** -- real-time SSE updates via `Async::Queue` pub/sub
7. **CreateTaskPushNotificationConfig** -- register webhook configs
8. **GetTaskPushNotificationConfig** -- retrieve a specific config
9. **ListTaskPushNotificationConfigs** -- list all configs for a task
10. **DeleteTaskPushNotificationConfig** -- remove a config
11. **GetExtendedAgentCard** -- returns unsupported (demonstrates error handling)

Key features:
- Falcon-native SSE streaming (no threads, pure async fibers)
- SQLite-backed persistent task store
- Push notification config CRUD

## Running

```sh
cd examples/full
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292
```

Or with Docker:

```sh
docker compose up --build
```

## Testing

Send a message:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello, world!"}]}
  }}'
```

Stream a message (SSE):

```sh
curl -N -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendStreamingMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello, world!"}]}
  }}'
```

List tasks:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"ListTasks","params":{}}'
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | All 11 operation handlers, agent card, store setup |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
