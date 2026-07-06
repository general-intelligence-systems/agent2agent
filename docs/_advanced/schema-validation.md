---
layout: default
title: Schema Validation
nav_order: 3
description: This guide covers the 47 A2A protocol types available as validated Ruby
  objects.
---

# Schema Validation

This guide covers the 47 A2A protocol types available as validated Ruby objects.

## Creating Protocol Objects

All 47 A2A protocol types are available as validated Ruby objects via `A2A::Protocol::JsonSchema`:

```ruby
# Create validated protocol objects (accepts snake_case or camelCase)
card = A2A::Protocol::JsonSchema["Agent Card"].new(
  name: "My Agent",
  version: "1.0.0",
  capabilities: { streaming: true, push_notifications: false },
)
card.valid?              # => true
card.name                # => "My Agent"
card.capabilities        # => nested Definition
card.to_h                # => {"name"=>"My Agent", "version"=>"1.0.0", "capabilities"=>{"streaming"=>true, "pushNotifications"=>false}}
```

## Validation Errors

```ruby
bad = A2A::Protocol::JsonSchema["Agent Card"].new({})
bad.valid?               # => false
bad.valid!               # raises A2A::Protocol::JsonSchema::ValidationError with detailed messages
```

## Listing Definitions

```ruby
A2A::Protocol::JsonSchema.list_definitions
# => ["Agent Card", "Task", "Message", "Artifact", "Send Message Request", ...]
```
