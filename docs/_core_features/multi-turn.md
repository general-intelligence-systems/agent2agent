---
layout: default
title: Multi-Turn Conversations
nav_order: 5
description: This guide covers using TASK_STATE_INPUT_REQUIRED to build confirmation-gated
  and multi-step conversations.
---

# Multi-Turn Conversations

This guide covers using `TASK_STATE_INPUT_REQUIRED` to build confirmation-gated and multi-step conversations.

## Input Required

Use `TASK_STATE_INPUT_REQUIRED` to pause execution and wait for user input. A continuation arrives as another `SendMessage` whose message carries the `taskId` — match on it with a tuple pattern:

```ruby
run A2A.agent(agent_card: agent_card) do |env|
  case [env["a2a.operation"], env["a2a.request"]]

  in ["SendMessage", { message: { task_id: String => task_id } }] if !task_id.empty?
    # -- Continuation: user is responding to INPUT_REQUIRED ---
    task = TASKS[task_id] or raise A2A::TaskNotFoundError.new(task_id)

    if env["a2a.message"].downcase.include?("go ahead")
      task[:state] = "TASK_STATE_WORKING"
      # ... do the work, add artifacts ...
      task[:state] = "TASK_STATE_COMPLETED"

      A2A::Protocol::JsonSchema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => { "state" => task[:state] },
          "artifacts" => task[:artifacts],
        }
      )
    else
      # Re-ask
      task[:state] = "TASK_STATE_INPUT_REQUIRED"

      A2A::Protocol::JsonSchema["Send Message Response"].new(
        task: {
          "id"        => task[:id],
          "contextId" => task[:context_id],
          "status"    => {
            "state"   => task[:state],
            "message" => { "role"  => "ROLE_AGENT",
                           "parts" => [{ "text" => "Please confirm." }] },
          },
        }
      )
    end

  in ["SendMessage", _]
    # -- New task: ask for confirmation ---
    task_id = SecureRandom.uuid
    TASKS[task_id] = {
      id: task_id, context_id: SecureRandom.uuid,
      state: "TASK_STATE_INPUT_REQUIRED", artifacts: [],
    }

    A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: {
        "id"        => task_id,
        "contextId" => TASKS[task_id][:context_id],
        "status"    => {
          "state"   => "TASK_STATE_INPUT_REQUIRED",
          "message" => { "role"  => "ROLE_AGENT",
                         "parts" => [{ "text" => "Here's my plan. Say 'go ahead' to proceed." }] },
        },
      }
    )
  end
end
```

The agent's question travels in `status.message`; the task ID in the response is what the client sends back as `message.taskId` on the next turn.

For a complete runnable version — including history tracking and terminal-state guards — see the [multi-turn example]({% link _examples/examples-multi-turn.md %}).
