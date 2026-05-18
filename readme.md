# agent2agent

A Ruby implementation of Google's [Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/) -- an open standard for interoperable communication between AI agents.

Build A2A-compliant agents that can communicate with any other A2A agent regardless of language or framework. Ships with server and client, both protocol bindings (JSON-RPC 2.0 and HTTP+JSON/REST), SSE streaming, SQLite persistence, and push notifications.

Runs on [Falcon](https://github.com/socketry/falcon) + [Async](https://github.com/socketry/async) -- pure fiber-based concurrency, no threads.

## Usage

Please see the [project documentation](https://general-intelligence-systems.github.io/agent2agent/) for more details.

  - [Getting Started](https://general-intelligence-systems.github.io/agent2agent/guides/getting-started/index) - This guide walks you through installing agent2agent, building a minimal agent, and calling it from both curl and Ruby.

  - [Client — JSON-RPC Binding](https://general-intelligence-systems.github.io/agent2agent/guides/client-json-rpc/index) - This guide covers all 11 protocol operations using the default JSON-RPC binding of `A2A::Client`.

  - [Client — REST Binding](https://general-intelligence-systems.github.io/agent2agent/guides/client-rest/index) - This guide covers all 11 protocol operations using the HTTP+JSON/REST binding of `A2A::Client`.

  - [Agent DSL](https://general-intelligence-systems.github.io/agent2agent/guides/agent-dsl/index) - This guide covers the handler DSL for building agents.

  - [Streaming](https://general-intelligence-systems.github.io/agent2agent/guides/streaming/index) - This guide covers SSE streaming for real-time task updates and chunked artifact delivery.

  - [Multi-Turn Conversations](https://general-intelligence-systems.github.io/agent2agent/guides/multi-turn/index) - This guide covers using `TASK_STATE_INPUT_REQUIRED` to build confirmation-gated and multi-step conversations.

  - [Async Background Jobs](https://general-intelligence-systems.github.io/agent2agent/guides/async-jobs/index) - This guide covers non-blocking background work with `returnImmediately` and `Store::Processor`.

  - [Task Stores](https://general-intelligence-systems.github.io/agent2agent/guides/task-stores/index) - This guide covers the in-memory and SQLite task stores and their shared interface.

  - [Schema Validation](https://general-intelligence-systems.github.io/agent2agent/guides/schema-validation/index) - This guide covers the 47 A2A protocol types available as validated Ruby objects.

  - [Protocol Operations](https://general-intelligence-systems.github.io/agent2agent/guides/protocol-operations/index) - This guide covers all 11 A2A operations and task state lifecycle.

  - [Example: Echo Agent](https://general-intelligence-systems.github.io/agent2agent/guides/examples-basic/index) - A minimal A2A agent that echoes messages back.

  - [Example: Multi-Turn](https://general-intelligence-systems.github.io/agent2agent/guides/examples-multi-turn/index) - Demonstrates the INPUT_REQUIRED state for multi-turn confirmation-gated conversations.

  - [Example: Async Jobs](https://general-intelligence-systems.github.io/agent2agent/guides/examples-async-jobs/index) - Non-blocking background processing with returnImmediately, SSE subscriptions, and polling.

  - [Example: Streaming Artifacts](https://general-intelligence-systems.github.io/agent2agent/guides/examples-streaming/index) - Chunked artifact streaming with append/lastChunk semantics over SSE.

  - [Example: Push Notifications](https://general-intelligence-systems.github.io/agent2agent/guides/examples-push-notifications/index) - Webhook-based push notification delivery with a two-service Docker setup.

  - [Example: Multi-Agent](https://general-intelligence-systems.github.io/agent2agent/guides/examples-multi-agent/index) - LLM-powered orchestration routing requests to remote agents via A2A::Client.

  - [Example: Full Agent](https://general-intelligence-systems.github.io/agent2agent/guides/examples-full/index) - All 11 A2A protocol operations in a single agent with SQLite, SSE, and push notifications.

## Development

```bash
bin/setup         # bundle install
bin/console       # IRB with A2A loaded
bin/test          # run inline tests (scampi)
bin/integration   # full protocol test against both bindings (requires Docker)
```

## License

Apache 2.0
