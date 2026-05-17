# Agent2Agent (A2A) Protocol Specification

??? note "**Latest Released Version** [`1.0.0`](https://a2a-protocol.org/v1.0.0/specification)"

    **Previous Versions**

    - [`0.3.0`](https://a2a-protocol.org/v0.3.0/specification)
    - [`0.2.6`](https://a2a-protocol.org/v0.2.6/specification)
    - [`0.1.0`](https://a2a-protocol.org/v0.1.0/specification)

See [Release Notes](https://github.com/a2aproject/A2A/releases) for changes made between versions.


## 11. HTTP+JSON/REST Protocol Binding

The HTTP+JSON protocol binding provides a RESTful interface using standard HTTP methods and JSON payloads.

### 11.1. Protocol Requirements

- **Protocol:** HTTP(S) with JSON payloads
- **Content-Type:** application/a2a+json **SHOULD** be used for requests and responses
- **Methods:** Standard HTTP verbs (GET, POST, PUT, DELETE)
- **URL Patterns:** RESTful resource-based URLs
- **Streaming:** Server-Sent Events for real-time updates

### 11.2. Service Parameter Transmission

A2A service parameters defined in [Section 3.2.6](#326-service-parameters) **MUST** be transmitted using standard HTTP request headers.

**Service Parameter Requirements:**

- Service parameter names **MUST** be transmitted as HTTP header fields
- Service parameter keys are case-insensitive per HTTP specification (RFC 9110)
- Multiple values for the same service parameter (e.g., `A2A-Extensions`) **SHOULD** be comma-separated in a single header field

**Example Request with A2A Service Parameters:**

```http
POST /message:send HTTP/1.1
Host: agent.example.com
Content-Type: application/a2a+json
Authorization: Bearer token
A2A-Version: 0.3
A2A-Extensions: https://example.com/extensions/geolocation/v1,https://standards.org/extensions/citations/v1

{
  "message": {
    "role": "ROLE_USER",
    "parts": [{"text": "Find restaurants near me"}]
  }
}
```

### 11.3. URL Patterns and HTTP Methods

#### 11.3.1. Message Operations

- `POST /message:send` - Send message
- `POST /message:stream` - Send message with streaming (SSE response)

#### 11.3.2. Task Operations

- `GET /tasks/{id}` - Get task status
- `GET /tasks` - List tasks (with query parameters)
- `POST /tasks/{id}:cancel` - Cancel task
- `POST /tasks/{id}:subscribe` - Subscribe to task updates (SSE response, returns error for terminal tasks)

#### 11.3.3. Push Notification Configuration

- `POST /tasks/{id}/pushNotificationConfigs` - Create configuration
- `GET /tasks/{id}/pushNotificationConfigs/{configId}` - Get configuration
- `GET /tasks/{id}/pushNotificationConfigs` - List configurations
- `DELETE /tasks/{id}/pushNotificationConfigs/{configId}` - Delete configuration

#### 11.3.4. Agent Card

- `GET /extendedAgentCard` - Get authenticated extended Agent Card

### 11.4. Request/Response Format

All requests and responses use JSON objects structurally equivalent to the Protocol Buffer definitions.

**Example Send Message:**

```http
POST /message:send
Content-Type: application/a2a+json

{
  "message": {
    "messageId": "uuid",
    "role": "ROLE_USER",
    "parts": [{"text": "Hello"}]
  },
  "configuration": {
    "acceptedOutputModes": ["text/plain"]
  }
}
```

**Referenced Objects:** [`SendMessageRequest`](#321-sendmessagerequest), [`Message`](#414-message)

**Response:**

```http
HTTP/1.1 200 OK
Content-Type: application/a2a+json

{
  "task": {
    "id": "task-uuid",
    "contextId": "context-uuid",
    "status": {
      "state": "TASK_STATE_COMPLETED"
    }
  }
}
```

**Referenced Objects:** [`Task`](#411-task)

### 11.5. Query Parameter Naming for Request Parameters

HTTP methods that do not support request bodies (GET, DELETE) **MUST** transmit operation request parameters as path parameters or query parameters. This section defines how to map Protocol Buffer field names to query parameter names.

**Naming Convention:**

Query parameter names **MUST** use `camelCase` to match the JSON serialization of Protocol Buffer field names. This ensures consistency with request bodies used in POST operations.

**Example Mappings:**

| Protocol Buffer Field | Query Parameter Name | Example Usage       |
| --------------------- | -------------------- | ------------------- |
| `context_id`          | `contextId`          | `?contextId=uuid`   |
| `page_size`           | `pageSize`           | `?pageSize=50`      |
| `page_token`          | `pageToken`          | `?pageToken=cursor` |
| `task_id`             | `taskId`             | `?taskId=uuid`      |

**Usage Examples:**

List tasks with filtering:

```http
GET /tasks?contextId=uuid&status=working&pageSize=50&pageToken=cursor
```

Get task with history:

```http
GET /tasks/{id}?historyLength=10
```

**Field Type Handling:**

- **Strings**: Passed directly as query parameter values
- **Booleans**: Represented as lowercase strings (`true`, `false`)
- **Numbers**: Represented as decimal strings
- **Enums**: Represented using their string values (e.g., `status=working`)
- **Repeated Fields**: Multiple values **MAY** be passed by repeating the parameter name (e.g., `?tag=value1&tag=value2`) or as comma-separated values (e.g., `?tag=value1,value2`)
- **Nested Objects**: Not supported in query parameters; operations requiring nested objects **MUST** use POST with a request body
- **Datetimes/Timestamps**: Represented as ISO 8601 strings (e.g., `2025-11-09T10:30:00Z`)

**URL Encoding:**

All query parameter values **MUST** be properly URL-encoded per [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html).

### 11.6. Error Handling

HTTP error responses use the [google.rpc.Status](https://github.com/googleapis/googleapis/blob/master/google/rpc/status.proto) JSON representation, which maps to the generic A2A error model defined in [Section 3.3.2](#332-error-handling) as follows:

- **Error Code**: Mapped to the HTTP status code and the `error.code` field
- **Error Message**: Mapped to the `error.message` field (human-readable string)
- **Error Details**: Mapped to the `error.details` array (array of objects, each containing a `@type` key, using ProtoJSON `Any` representation)

**Error Detail Objects:**

Each object in the `details` array **MUST** include a `@type` key that identifies the object's type. Implementations **SHOULD** use well-known types such as `google.rpc.BadRequest` to attach structured data to validation errors. Additional error context **MAY** be included as further objects in the `details` array.

**A2A Error Representation:**

Since multiple A2A error types may map to the same HTTP status code (e.g., `TaskNotCancelableError` and `PushNotificationNotSupportedError` both map to `400 Bad Request`), implementations **MUST** include a `google.rpc.ErrorInfo` object in the `details` array for A2A-specific errors with:

- `@type`: Set to `"type.googleapis.com/google.rpc.ErrorInfo"`
- `reason`: The A2A error type in UPPER_SNAKE_CASE without the "Error" suffix (e.g., `TASK_NOT_FOUND`, `TASK_NOT_CANCELABLE`)
- `domain`: Set to `"a2a-protocol.org"`

For the complete mapping of A2A error types to HTTP status codes, see [Section 5.4 (Error Code Mappings)](#54-error-code-mappings).

**Error Response Example:**

```http
HTTP/1.1 404 Not Found
Content-Type: application/a2a+json

{
  "error": {
    "code": 404,
    "status": "NOT_FOUND",
    "message": "The specified task ID does not exist or is not accessible",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "TASK_NOT_FOUND",
        "domain": "a2a-protocol.org",
        "metadata": {
          "taskId": "task-123",
          "timestamp": "2025-11-09T10:30:00.000Z"
        }
      }
    ]
  }
}
```

Extension fields like `taskId` and `timestamp` provide additional context to help diagnose the error.

### 11.7. Streaming

<span id="stream-response"></span>

REST streaming uses Server-Sent Events with the `data` field containing JSON serializations of the protocol data objects:

```http
POST /message:stream
Content-Type: application/a2a+json

{ /* SendMessageRequest object */ }
```

**Referenced Objects:** [`SendMessageRequest`](#321-sendmessagerequest)

**Response:**

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream

data: { /* StreamResponse object */ }

data: { /* StreamResponse object */ }
```

**Referenced Objects:** [`StreamResponse`](#323-stream-response)
Streaming responses are simple, linearly ordered sequences: first a `Task` (or single `Message`), then zero or more status or artifact update events until the task reaches a terminal or interrupted state, at which point the stream closes. Implementations SHOULD avoid re-ordering events and MAY optionally resend a final `Task` snapshot before closing.

