# Agent DSL

This guide covers the handler DSL for building agents.

## Registering Handlers

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
