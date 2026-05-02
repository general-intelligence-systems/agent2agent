# Tracing

This guide explains how to add distributed tracing to your A2A agents using the [`traces`](https://github.com/socketry/traces) gem.

## Overview

The `agent2agent` gem ships trace providers that instrument the request lifecycle. When a tracing backend is active, every request produces spans covering:

| Span Name | Class | Key Attributes |
|-----------|-------|----------------|
| `a2a.server.call` | `A2A::Server` | `http.method`, `http.path`, `http.status_code` |
| `a2a.server.triage.call` | `A2A::Server::Triage` | `a2a.operation`, `a2a.proto_operation` |
| `a2a.server.dispatcher.call` | `A2A::Server::Dispatcher` | `a2a.operation`, `http.status_code`, `a2a.response_type` |
| `a2a.bindings.json_rpc.call` | `A2A::Bindings::JsonRpc` | `rpc.method`, `rpc.jsonrpc.request_id`, `a2a.response_type` |
| `a2a.bindings.rest.call` | `A2A::Bindings::Rest` | `a2a.verb`, `a2a.path`, `a2a.response_type` |

When no backend is configured, tracing is a zero-cost no-op -- the provider blocks are never evaluated.

## How It Works

The `traces` gem uses a provider/backend architecture:

1. **Providers** wrap existing methods with trace spans using `Traces::Provider(SomeClass)`. They live in `lib/traces/provider/a2a/`.
2. **Backends** connect those spans to an observability system (OpenTelemetry, Datadog, console output, etc.).
3. **Config** (`config/traces.rb`) tells the `traces` gem which providers to load when a backend is active.

The activation sequence:

```
TRACES_BACKEND env var set
  -> require "traces" (happens automatically via async)
  -> backend loaded, Traces.enabled? == true
  -> config/traces.rb prepare method called
  -> providers loaded, methods wrapped with spans
```

## Enabling Tracing

### 1. Choose a Backend

Install one of the available backends:

| Backend | Gem | Purpose |
|---------|-----|---------|
| Console | (built-in) | Log spans to stdout via the `console` gem |
| Test | (built-in) | Validate tracing interface usage in tests |
| OpenTelemetry | `traces-backend-open_telemetry` | Export to any OTLP-compatible collector |
| Datadog | `traces-backend-datadog` | Export to Datadog APM |
| New Relic | `traces-backend-newrelic` | Export to New Relic |

For OpenTelemetry:

```ruby
# Gemfile
gem "traces-backend-open_telemetry"
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
```

### 2. Set the Backend Environment Variable

The `TRACES_BACKEND` environment variable **must be set before** `require "traces"` is evaluated (which happens automatically when `async` is required).

```bash
# Console backend (quick debugging)
TRACES_BACKEND=traces/backend/console bundle exec falcon serve

# OpenTelemetry backend
TRACES_BACKEND=traces/backend/open_telemetry bundle exec falcon serve
```

### 3. Load the A2A Providers

If you are running your app from the project root (where `config/traces.rb` exists), the providers are loaded automatically via the `prepare` hook.

If you are consuming `agent2agent` as an external gem in your own application, create a `config/traces.rb` in your app root:

```ruby
# config/traces.rb
def prepare
  require "traces/provider/a2a"
end
```

This tells the `traces` gem to load all A2A provider modules when a backend is active.

## OpenTelemetry Setup

A complete example with OpenTelemetry and an OTLP exporter:

```ruby
# Gemfile
gem "agent2agent"
gem "traces-backend-open_telemetry"
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
```

```ruby
# config/initializers/opentelemetry.rb (or top of config.ru)
require "opentelemetry/sdk"
require "opentelemetry-exporter-otlp"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "my-a2a-agent"
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )
end
```

```bash
TRACES_BACKEND=traces/backend/open_telemetry \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  bundle exec falcon serve
```

Spans will appear in your collector (Jaeger, Grafana Tempo, etc.) with the full request lifecycle.

## Console Backend (Quick Debugging)

For local development, the built-in console backend logs spans directly:

```bash
TRACES_BACKEND=traces/backend/console bundle exec falcon serve
```

Output:

```
0.0s     info: traces [oid=0x...] [ec=0x...] [pid=...]
             | a2a.server.call
             | {"http.method"=>"POST", "http.path"=>"/a2a", "http.status_code"=>200}
```

## Testing with Traces

Use the built-in test backend to validate spans in your test suite:

```ruby
# config/sus.rb or test_helper.rb
ENV["TRACES_BACKEND"] ||= "traces/backend/test"
```

The test backend validates that all `Traces.trace` calls use correct argument types without emitting output.

## Available Providers

To list all trace providers available across your loaded gems:

```bash
bundle exec bake traces:provider:list
```

This scans all gems for files under `traces/provider/**/*.rb` in their require paths.

## Span Reference

### `a2a.server.call`

The outermost span covering the full Rack request/response cycle.

- `http.method` -- HTTP method (GET, POST, etc.)
- `http.path` -- Request path
- `http.status_code` -- Response status code

### `a2a.server.triage.call`

Resolves which A2A operation the request maps to.

- `a2a.operation` -- Resolved operation name (e.g., `send_message`, `get_task`)
- `a2a.proto_operation` -- Protocol buffer operation name

### `a2a.server.dispatcher.call`

Dispatches the resolved operation to the agent handler.

- `a2a.operation` -- Operation being dispatched
- `http.status_code` -- Response status code
- `a2a.response_type` -- One of `stream`, `error`, or `result`

### `a2a.bindings.json_rpc.call`

Handles JSON-RPC 2.0 protocol binding.

- `http.status_code` -- Response status code
- `rpc.method` -- JSON-RPC method name
- `rpc.jsonrpc.request_id` -- JSON-RPC request ID
- `a2a.response_type` -- One of `stream`, `error`, or `result`

### `a2a.bindings.rest.call`

Handles HTTP+JSON/REST protocol binding.

- `http.status_code` -- Response status code
- `a2a.verb` -- REST verb (e.g., `send`, `get`, `cancel`)
- `a2a.path` -- Request path
- `a2a.response_type` -- One of `stream`, `error`, or `result`
