---
layout: default
title: Rails & Rack Hosts
nav_order: 7
description: A2A.agent returns a plain Rack app — mount it in Rails routes, combine
  several agents in one host, and test them over a real HTTP server.
---

# Rails & Rack Hosts

`A2A.agent` returns a plain Rack app, so an agent doesn't need its own process or `config.ru` — it mounts anywhere Rack apps do. The most common host is Rails.

## Mounting in Rails Routes

Mount agents directly in `config/routes.rb`. Each mount point gets the full A2A surface — agent card discovery, both protocol bindings, and SSE streaming — under its own path prefix:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  streaming_agent = ->(name) do
    A2A.agent(agent_card: { "name" => name }) do |env|
      case env["a2a.operation"]
      in "SendStreamingMessage"
        task_id    = SecureRandom.uuid
        context_id = SecureRandom.uuid

        env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
          s.task(status: { state: "TASK_STATE_WORKING", timestamp: Time.now.utc.iso8601 })

          3.times do |i|
            s.artifact_update(
              artifact: {
                artifact_id: "artifact-1",
                name:        "greeting.txt",
                parts:       [{ text: "chunk #{i + 1} " }],
              },
              append:     i.positive?,
              last_chunk: i == 2,
            )
          end

          s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: Time.now.utc.iso8601 })
        end
      in "SendMessage"
        A2A::Protocol::JsonSchema["Send Message Response"].new({})
      in "GetTask"
        A2A::Protocol::JsonSchema["Task"].new(
          "id"        => env["a2a.request"].id,
          "contextId" => "ctx-1",
          "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => Time.now.utc.iso8601 },
        )
      end
    end
  end

  mount streaming_agent.("Agent One"), at: "/agent1", as: :agent1
  mount streaming_agent.("Agent Two"), at: "/agent2", as: :agent2
end
```

Each agent is now discoverable and callable under its mount point:

```
GET  /agent1/.well-known/agent-card.json
POST /agent1/                              # JSON-RPC binding
POST /agent1/rest/message:send             # REST binding
```

Load the gem via your Gemfile — `require: "a2a"` makes it available before routes are drawn:

```ruby
gem "agent2agent", require: "a2a"
```

## Use Falcon

SSE streaming is built on `Protocol::HTTP::Body::Writable` and Async fibers, so the host app must run on [Falcon](https://github.com/socketry/falcon). For Rails, use [falcon-rails](https://github.com/socketry/falcon-rails):

```ruby
gem "falcon-rails"
```

Non-streaming operations work on any Rack server, but under a threaded server like Puma the streaming operations (`SendStreamingMessage`, `SubscribeToTask`) won't deliver events incrementally.

## Calling Mounted Agents

`A2A::Client` doesn't care how the agent is hosted — point it at the mount point:

```ruby
client = A2A::Client.new("https://myapp.example.com/agent1")                 # JSON-RPC
client = A2A::Client.new("https://myapp.example.com/agent1", binding: :rest) # REST

card = client.agent_card
card.name # => "Agent One"

response = client.send_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }
)

events = []
client.send_streaming_message(
  message: { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }
) { |event| events << event }

chunks = events.filter_map { |e| e.artifact_update&.artifact&.parts&.first&.text }
# => ["chunk 1 ", "chunk 2 ", "chunk 3 "]
events.last.status_update&.status&.state
# => "TASK_STATE_COMPLETED"
```

Operations the agent doesn't handle raise the binding's error class:

```ruby
begin
  client.cancel_task(id: "task-abc")
rescue A2A::JsonRpcError, A2A::RestError => e
  e.message # => "Operation not supported: CancelTask"
end
```

## Testing Agents Over Real HTTP

The client's SSE streaming needs a live async server — `Rack::MockRequest` can't exercise it. Serve the whole app inside the test's async reactor with `Async::HTTP::Server` and run the client against it:

```ruby
require "socket"
require "async"
require "async/http/server"
require "async/http/endpoint"
require "protocol/rack"

class A2AClientTest < ActiveSupport::TestCase
  MESSAGE = { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }.freeze

  %i[json_rpc rest].each do |binding|
    test "agent1 over #{binding}" do
      serve do |base|
        client = A2A::Client.new("#{base}/agent1", binding: binding)

        assert_equal "Agent One", client.agent_card.name

        events = []
        client.send_streaming_message(message: MESSAGE) { |event| events << event }
        assert_equal "TASK_STATE_COMPLETED", events.last.status_update&.status&.state
      end
    end
  end

  private

    # Serves the full Rails app over real HTTP inside the test's async reactor.
    def serve
      Sync do
        socket = TCPServer.new("127.0.0.1", 0)
        port = socket.addr[1]
        socket.close

        endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}")
        adapter = Protocol::Rack::Adapter.new(Rails.application)
        server_task = Async { Async::HTTP::Server.new(adapter, endpoint).run }

        begin
          yield "http://127.0.0.1:#{port}"
        ensure
          server_task.stop
        end
      end
    end
end
```

This runs the same middleware stack production sees, over both bindings, including streaming — no mocks.

## Other Rack Hosts

The same pattern works in any Rack host. With `Rack::URLMap` in a plain `config.ru`:

```ruby
require "a2a"

run Rack::URLMap.new(
  "/greeter"    => A2A.agent(agent_card: { "name" => "Greeter" })    { |env| ... },
  "/translator" => A2A.agent(agent_card: { "name" => "Translator" }) { |env| ... },
)
```
