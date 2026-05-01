# Schema Validation

This guide covers the 47 A2A protocol types available as validated Ruby objects.

## Creating Protocol Objects

All 47 A2A protocol types are available as validated Ruby objects via `A2A::Schema`:

```ruby
# Create validated protocol objects (accepts snake_case or camelCase)
card = A2A::Schema["Agent Card"].new(
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
bad = A2A::Schema["Agent Card"].new({})
bad.valid?               # => false
bad.valid!               # raises A2A::Schema::ValidationError with detailed messages
```

## Listing Definitions

```ruby
A2A::Schema.list_definitions
# => ["Agent Card", "Task", "Message", "Artifact", "Send Message Request", ...]
```
