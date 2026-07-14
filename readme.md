# agent2agent

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/general-intelligence-systems/agent2agent)

A Ruby implementation of Google's [Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/) -- an open standard for interoperable communication between AI agents.

Build A2A-compliant agents that can communicate with any other A2A agent regardless of language or framework. Ships with server and client, both protocol bindings (JSON-RPC 2.0 and HTTP+JSON/REST), and SSE streaming.

Runs on [Falcon](https://github.com/socketry/falcon) + [Async](https://github.com/socketry/async) -- pure fiber-based concurrency, no threads.

An agent is a single `A2A.agent` call: the block receives the Rack env and routes operations with pattern matching, and the return value is a complete Rack app. In `config.ru`:

```ruby
require "a2a"

run A2A.agent(agent_card: { "name" => "Echo Agent", "url" => "http://localhost:9292", "version" => "1.0.0" }) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    A2A::Protocol::JsonSchema["Send Message Response"].new({})
  in "GetTask"
    A2A::Protocol::JsonSchema["Task"].new({})
  end
end
```

Operations the block doesn't match automatically return `UnsupportedOperationError`.

Because the return value is a plain Rack app, agents also mount directly inside a host application — e.g. `mount agent, at: "/agent1"` in Rails routes.

## Usage

Please see the [project documentation](https://general-intelligence-systems.github.io/agent2agent/) for more details.

  - [Getting Started](https://general-intelligence-systems.github.io/agent2agent/getting-started/) - This guide walks you through installing agent2agent, building a minimal agent, and calling it from both curl and Ruby.

  - [Client — JSON-RPC Binding](https://general-intelligence-systems.github.io/agent2agent/client-json-rpc/) - This guide covers all 11 protocol operations using the default JSON-RPC binding of `A2A::Client`.

  - [Client — REST Binding](https://general-intelligence-systems.github.io/agent2agent/client-rest/) - This guide covers all 11 protocol operations using the HTTP+JSON/REST binding of `A2A::Client`.

  - [Agent Handler](https://general-intelligence-systems.github.io/agent2agent/agent-dsl/) - This guide covers the pattern-matching handler block for building agents.

  - [Streaming](https://general-intelligence-systems.github.io/agent2agent/streaming/) - This guide covers SSE streaming for real-time task updates and chunked artifact delivery.

  - [Multi-Turn Conversations](https://general-intelligence-systems.github.io/agent2agent/multi-turn/) - This guide covers using `TASK_STATE_INPUT_REQUIRED` to build confirmation-gated and multi-step conversations.

  - [Rails & Rack Hosts](https://general-intelligence-systems.github.io/agent2agent/rails-and-rack-hosts/) - This guide covers mounting agents in Rails routes (or any Rack host) and testing them over real HTTP.

  - [Async Background Jobs](https://general-intelligence-systems.github.io/agent2agent/async-jobs/) - This guide covers non-blocking background work with Async fibers and immediate SUBMITTED responses.

  - [Managing Task State](https://general-intelligence-systems.github.io/agent2agent/task-stores/) - This guide covers managing task state in your agent -- the gem ships no built-in task store, so persistence is your application's concern.

  - [Schema Validation](https://general-intelligence-systems.github.io/agent2agent/schema-validation/) - This guide covers the 47 A2A protocol types available as validated Ruby objects.

  - [Protocol Operations](https://general-intelligence-systems.github.io/agent2agent/protocol-operations/) - Server handler and client call for every one of the 11 A2A operations, plus the task state lifecycle.

  - [Error Handling](https://general-intelligence-systems.github.io/agent2agent/error-handling/) - Raising every A2A protocol error from your handler, the wire formats, and rescuing every client-side error class.

  - [Example: Echo Agent](https://general-intelligence-systems.github.io/agent2agent/examples-basic/) - A minimal A2A agent that echoes messages back.

  - [Example: Multi-Turn](https://general-intelligence-systems.github.io/agent2agent/examples-multi-turn/) - Demonstrates the INPUT_REQUIRED state for multi-turn confirmation-gated conversations.

  - [Example: Streaming Artifacts](https://general-intelligence-systems.github.io/agent2agent/examples-streaming/) - Chunked artifact streaming with append/lastChunk semantics over SSE.

  - [Example: Push Notifications](https://general-intelligence-systems.github.io/agent2agent/examples-push-notifications/) - Webhook-based push notification delivery with a two-service Docker setup.

  - [Example: Multi-Agent](https://general-intelligence-systems.github.io/agent2agent/examples-multi-agent/) - LLM-powered orchestration routing requests to remote agents via A2A::Client.

  - [Example: Full Agent](https://general-intelligence-systems.github.io/agent2agent/examples-full/) - The core A2A protocol operations in a single agent with an in-memory store and SSE streaming.

## Development

```bash
bin/setup         # bundle install
bin/console       # IRB with A2A loaded
bin/test          # run inline tests (scampi)
bin/integration   # full protocol test against both bindings (requires Docker)
```

## License

Apache 2.0
