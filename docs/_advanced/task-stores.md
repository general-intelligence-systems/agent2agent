---
layout: default
title: Task Stores
nav_order: 2
description: This guide covers the in-memory and SQLite task stores and their shared
  interface.
---

# Task Stores

This guide covers the in-memory and SQLite task stores and their shared interface.

## In-Memory (development)

```ruby
store = A2A::TaskStore.new
server = A2A::Server.new(agent_card: card, store: store)
```

## SQLite (production)

```ruby
require "a2a/store"

store = A2A::Store::SQLite.new(path: "agent.db")
server = A2A::Server.new(agent_card: card, store: store)
```

## Store Interface

Both stores share the same interface:

```ruby
store.create(task_id, context_id)
store.get(task_id)                              # => Hash or nil
store.update_state(task_id, "TASK_STATE_WORKING", message: { ... })
store.add_artifact(task_id, { "artifactId" => "...", "parts" => [...] })
store.add_message(task_id, { "role" => "ROLE_AGENT", "parts" => [...] })
store.complete(task_id, result)
store.fail(task_id, "something went wrong")
store.cancel(task_id)
store.list(context_id: "ctx-1", state: "TASK_STATE_COMPLETED")

# Pub/sub (for SubscribeToTask)
queue = store.subscribe(task_id)
store.unsubscribe(task_id, queue)

# Push notification configs
store.create_push_config(task_id, config)
store.get_push_config(task_id, config_id)
store.list_push_configs(task_id)
store.delete_push_config(task_id, config_id)
```
