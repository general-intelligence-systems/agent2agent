---
layout: default
title: agent2agent
nav_order: 1
description: 'A Ruby implementation of the Agent-to-Agent (A2A) protocol. Build interoperable AI agents with JSON-RPC and REST bindings, SSE streaming, task stores, and push notifications.'
permalink: /
---

# agent2agent

A Ruby implementation of Google's [Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/) — an open standard for interoperable communication between AI agents.
{: .fs-6 .fw-300 }

<div class="hero-actions">
  <a href="{% link _getting_started/getting-started.md %}" class="btn btn-primary fs-5 mb-4 mb-md-0 mr-2">Get started</a>
  <a href="https://github.com/general-intelligence-systems/agent2agent" class="btn fs-5 mb-4 mb-md-0 mr-2">GitHub</a>
</div>

Build A2A-compliant agents that can communicate with any other A2A agent regardless of language or framework. Ships with server and client, both protocol bindings (JSON-RPC 2.0 and HTTP+JSON/REST), SSE streaming, SQLite persistence, and push notifications.

Runs on [Falcon](https://github.com/socketry/falcon) + [Async](https://github.com/socketry/async) — pure fiber-based concurrency, no threads.

## Quick start

```ruby
# config.ru
require "a2a"

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    # handle the incoming message
  end
end
```

Head to [Getting Started]({% link _getting_started/getting-started.md %}) for a complete walkthrough — installing the gem, building a minimal agent, and calling it from both curl and Ruby.

## What's here

- **Core Features** — the [JSON-RPC]({% link _core_features/client-json-rpc.md %}) and [REST]({% link _core_features/client-rest.md %}) client bindings, the [Agent DSL]({% link _core_features/agent-dsl.md %}), [streaming]({% link _core_features/streaming.md %}), [multi-turn conversations]({% link _core_features/multi-turn.md %}), and all [11 protocol operations]({% link _core_features/protocol-operations.md %}).
- **Advanced** — [async background jobs]({% link _advanced/async-jobs.md %}), [task stores]({% link _advanced/task-stores.md %}), [schema validation]({% link _advanced/schema-validation.md %}), and [distributed tracing]({% link _advanced/tracing.md %}).
- **Examples** — runnable agents from a [minimal echo agent]({% link _examples/examples-basic.md %}) up to a [full-featured agent]({% link _examples/examples-full.md %}) and [multi-agent orchestration]({% link _examples/examples-multi-agent.md %}).
