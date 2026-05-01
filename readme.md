# agent2agent

A Ruby implementation of Google's [Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/) -- an open standard for interoperable communication between AI agents.

Build A2A-compliant agents that can communicate with any other A2A agent regardless of language or framework. Ships with server and client, both protocol bindings (JSON-RPC 2.0 and HTTP+JSON/REST), SSE streaming, SQLite persistence, and push notifications.

Runs on [Falcon](https://github.com/socketry/falcon) + [Async](https://github.com/socketry/async) -- pure fiber-based concurrency, no threads.

## Usage

Please see the [project documentation](https://general-intelligence-systems.github.io/agent2agent/) for more details.

  - [Getting Started](https://general-intelligence-systems.github.io/agent2agent/guides/getting-started/index) - This guide walks you through installing agent2agent, building a minimal agent, and calling it from both curl and Ruby.

  - [Agent DSL](https://general-intelligence-systems.github.io/agent2agent/guides/agent-dsl/index) - This guide covers the handler DSL for building agents.

  - [Streaming](https://general-intelligence-systems.github.io/agent2agent/guides/streaming/index) - This guide covers SSE streaming for real-time task updates and chunked artifact delivery.

  - [Multi-Turn Conversations](https://general-intelligence-systems.github.io/agent2agent/guides/multi-turn/index) - This guide covers using `TASK_STATE_INPUT_REQUIRED` to build confirmation-gated and multi-step conversations.

  - [Async Background Jobs](https://general-intelligence-systems.github.io/agent2agent/guides/async-jobs/index) - This guide covers non-blocking background work with `returnImmediately` and `Store::Processor`.

  - [Task Stores](https://general-intelligence-systems.github.io/agent2agent/guides/task-stores/index) - This guide covers the in-memory and SQLite task stores and their shared interface.

  - [Schema Validation](https://general-intelligence-systems.github.io/agent2agent/guides/schema-validation/index) - This guide covers the 47 A2A protocol types available as validated Ruby objects.

  - [Protocol Operations](https://general-intelligence-systems.github.io/agent2agent/guides/protocol-operations/index) - This guide covers all 11 A2A operations and task state lifecycle.

## Examples

Each example includes a `config.ru`, `Gemfile`, `Dockerfile`, and `docker-compose.yml`.

| Example | What it shows |
|---------|---------------|
| [`basic/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/basic) | Minimal echo agent, 2 operations |
| [`full/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/full) | All 11 operations, SQLite, SSE, push notifications |
| [`streaming-artifacts/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/streaming-artifacts) | Chunked artifact streaming with `append`/`lastChunk` |
| [`multi-turn/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-turn) | `INPUT_REQUIRED` for confirmation-gated conversations |
| [`async-jobs/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs) | Background processing with `returnImmediately` + polling/SSE |
| [`push-notifications/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/push-notifications) | Webhook delivery (2-service Docker setup) |
| [`multi-agent/`](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-agent) | LLM-powered orchestration routing to remote agents via `A2A::Client` |

## Development

```sh
bin/setup         # bundle install
bin/console       # IRB with A2A loaded
bin/test          # run inline tests (scampi)
bin/integration   # full protocol test against both bindings (requires Docker)
```

## License

MIT
