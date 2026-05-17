# frozen_string_literal: true

# A2A Protocol Error Types
#
# Reference: A2A Specification v1.0
#   - Section 3.3.2 Error Handling (error categories & A2A-specific errors)
#   - Section 5.4   Error Code Mappings (JSON-RPC / gRPC / HTTP mappings)
#
# Source: refs/A2A/docs/specification.md
#
# Error Code Mappings (Section 5.4):
#
#   A2A Error Type                      | JSON-RPC | gRPC                | HTTP
#   ------------------------------------|----------|---------------------|-----
#   TaskNotFoundError                   | -32001   | NOT_FOUND           | 404
#   TaskNotCancelableError              | -32002   | FAILED_PRECONDITION | 400
#   PushNotificationNotSupportedError   | -32003   | FAILED_PRECONDITION | 400
#   UnsupportedOperationError           | -32004   | FAILED_PRECONDITION | 400
#   ContentTypeNotSupportedError        | -32005   | INVALID_ARGUMENT    | 400
#   InvalidAgentResponseError           | -32006   | INTERNAL            | 500
#   ExtendedAgentCardNotConfiguredError | -32007   | FAILED_PRECONDITION | 400
#   ExtensionSupportRequiredError       | -32008   | FAILED_PRECONDITION | 400
#   VersionNotSupportedError            | -32009   | FAILED_PRECONDITION | 400
#
# Additionally, JSON-RPC standard -32602 is used for validation errors (InvalidParamsError).

require "bundler/setup"
require "a2a"

module A2A
  # Base error class for A2A protocol errors.
  #
  # Each subclass carries its own JSON-RPC error code, HTTP status,
  # and structured error data. The handler layer rescues these and
  # calls #to_h to populate env["a2a.error"] for the binding layer.
  #
  class Error < StandardError
    attr_reader :code, :http_status

    def initialize(message, code:, http_status: 400)
      @code        = code
      @http_status = http_status
      super(message)
    end

    def error_data = nil

    def to_h
      h = { code: code, http_status: http_status, message: message }
      h[:data] = error_data if error_data
      h
    end
  end

  # The specified task ID does not correspond to an existing or accessible task.
  # It might be invalid, expired, or already completed and purged.
  class TaskNotFoundError < Error
    def initialize(task_id, message: "Task not found")
      @task_id = task_id
      super(message, code: -32001, http_status: 404)
    end

    def error_data
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "TASK_NOT_FOUND",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "taskId" => @task_id.to_s },
      }]
    end
  end

  # An attempt was made to cancel a task that is not in a cancelable state
  # (e.g., it has already reached a terminal state like completed, failed, or canceled).
  class TaskNotCancelableError < Error
    def initialize(task_id, state:, message: "Task is not cancelable")
      @task_id = task_id
      @state   = state
      super(message, code: -32002, http_status: 400)
    end

    def error_data
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "TASK_NOT_CANCELABLE",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "taskId" => @task_id.to_s, "state" => @state.to_s },
      }]
    end
  end

  # Client attempted to use push notification features but the server agent
  # does not support them (i.e., AgentCard.capabilities.pushNotifications is false).
  class PushNotificationNotSupportedError < Error
    def initialize(message: "Push notifications are not supported")
      super(message, code: -32003, http_status: 400)
    end

    def error_data
      [{
        "@type"  => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason" => "PUSH_NOTIFICATION_NOT_SUPPORTED",
        "domain" => "a2a-protocol.org",
      }]
    end
  end

  # The requested operation or a specific aspect of it is not supported
  # by this server agent implementation.
  class UnsupportedOperationError < Error
    def initialize(message: "Unsupported operation")
      super(message, code: -32004, http_status: 400)
    end

    def error_data
      [{
        "@type"  => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason" => "UNSUPPORTED_OPERATION",
        "domain" => "a2a-protocol.org",
      }]
    end
  end

  # A Media Type provided in the request's message parts or implied for an artifact
  # is not supported by the agent or the specific skill being invoked.
  class ContentTypeNotSupportedError < Error
    def initialize(content_type = nil, message: "Content type not supported")
      @content_type = content_type
      super(message, code: -32005, http_status: 400)
    end

    def error_data
      meta = {}
      meta["contentType"] = @content_type.to_s if @content_type
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "CONTENT_TYPE_NOT_SUPPORTED",
        "domain"   => "a2a-protocol.org",
        "metadata" => meta,
      }]
    end
  end

  # An agent returned a response that does not conform to the specification
  # for the current method.
  class InvalidAgentResponseError < Error
    def initialize(message: "Invalid agent response")
      super(message, code: -32006, http_status: 500)
    end

    def error_data
      [{
        "@type"  => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason" => "INVALID_AGENT_RESPONSE",
        "domain" => "a2a-protocol.org",
      }]
    end
  end

  # The agent does not have an extended agent card configured when one is
  # required for the requested operation.
  class ExtendedAgentCardNotConfiguredError < Error
    def initialize(message: "Extended agent card is not configured")
      super(message, code: -32007, http_status: 400)
    end

    def error_data
      [{
        "@type"  => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason" => "EXTENDED_AGENT_CARD_NOT_CONFIGURED",
        "domain" => "a2a-protocol.org",
      }]
    end
  end

  # Server requested use of an extension marked as required: true in the
  # Agent Card but the client did not declare support for it in the request.
  class ExtensionSupportRequiredError < Error
    def initialize(extension = nil, message: "Extension support required")
      @extension = extension
      super(message, code: -32008, http_status: 400)
    end

    def error_data
      meta = {}
      meta["extension"] = @extension.to_s if @extension
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "EXTENSION_SUPPORT_REQUIRED",
        "domain"   => "a2a-protocol.org",
        "metadata" => meta,
      }]
    end
  end

  # The A2A protocol version specified in the request (via A2A-Version service
  # parameter) is not supported by the agent.
  class VersionNotSupportedError < Error
    def initialize(version = nil, message: "Version not supported")
      @version = version
      super(message, code: -32009, http_status: 400)
    end

    def error_data
      meta = {}
      meta["version"] = @version.to_s if @version
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "VERSION_NOT_SUPPORTED",
        "domain"   => "a2a-protocol.org",
        "metadata" => meta,
      }]
    end
  end

  # Validation error for invalid input parameters or message format.
  # Maps to JSON-RPC standard code -32602 (Invalid params).
  class InvalidParamsError < Error
    def initialize(message, fields: nil)
      @fields = fields
      super(message, code: -32602, http_status: 400)
    end

    def error_data
      return nil unless @fields
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "INVALID_PARAMS",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "fields" => Array(@fields).join(", ") },
      }]
    end
  end

  # Internal (non-spec) errors used by this library's implementation.
  module Internal
    module Errors
      # Raised when a specific push notification config cannot be found by ID.
      # This is an implementation detail — the spec does not define this error.
      class PushNotificationConfigNotFoundError < A2A::Error
        def initialize(task_id, config_id, message: "Push notification config not found")
          @task_id   = task_id
          @config_id = config_id
          super(message, code: -32001, http_status: 404)
        end

        def error_data
          [{
            "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
            "reason"   => "TASK_NOT_FOUND",
            "domain"   => "a2a-protocol.org",
            "metadata" => { "taskId" => @task_id.to_s, "configId" => @config_id.to_s },
          }]
        end
      end
    end
  end
end

# Specification excerpt: refs/A2A/docs/specification.md, Section 3.3.2 Error Handling
#
# All operations may return errors in the following categories. Servers MUST return appropriate
# errors and SHOULD provide actionable information to help clients resolve issues.
#
# Error Categories and Server Requirements:
#
# - Authentication Errors: Invalid or missing credentials
#   - Servers MUST reject requests with invalid or missing authentication credentials
#   - Servers SHOULD include authentication challenge information in the error response
#   - Servers SHOULD specify which authentication scheme is required
#   - Example error codes: HTTP 401 Unauthorized, gRPC UNAUTHENTICATED, JSON-RPC custom error
#   - Example scenarios: Missing bearer token, expired API key, invalid OAuth token
#
# - Authorization Errors: Insufficient permissions for requested operation
#   - Servers MUST return an authorization error when the authenticated client lacks required permissions
#   - Servers SHOULD indicate what permission or scope is missing (without leaking sensitive information
#     about resources the client cannot access)
#   - Servers MUST NOT reveal the existence of resources the client is not authorized to access
#   - Example error codes: HTTP 403 Forbidden, gRPC PERMISSION_DENIED, JSON-RPC custom error
#   - Example scenarios: Attempting to access a task created by another user, insufficient OAuth scopes
#
# - Validation Errors: Invalid input parameters or message format
#   - Servers MUST validate all input parameters before processing
#   - Servers SHOULD specify which parameter(s) failed validation and why
#   - Servers SHOULD provide guidance on valid parameter values or formats
#   - Example error codes: HTTP 400 Bad Request, gRPC INVALID_ARGUMENT, JSON-RPC -32602 Invalid params
#   - Example scenarios: Invalid task ID format, missing required message parts, unsupported content type
#
# - Resource Errors: Requested task not found or not accessible
#   - Servers MUST return a not found error when a requested resource does not exist or is not accessible
#     to the authenticated client
#   - Servers SHOULD NOT distinguish between "does not exist" and "not authorized" to prevent
#     information leakage
#   - Example error codes: HTTP 404 Not Found, gRPC NOT_FOUND, JSON-RPC custom error
#     (see A2A-specific errors)
#   - Example scenarios: Task ID does not exist, task has been deleted, configuration not found
#
# - System Errors: Internal agent failures or temporary unavailability
#   - Servers SHOULD return appropriate error codes for temporary failures vs. permanent errors
#   - Servers MAY include retry guidance (e.g., Retry-After header in HTTP)
#   - Servers SHOULD log system errors for diagnostic purposes
#   - Example error codes: HTTP 500 Internal Server Error or 503 Service Unavailable, gRPC INTERNAL or
#     UNAVAILABLE, JSON-RPC -32603 Internal error
#   - Example scenarios: Database connection failure, downstream service timeout, rate limit exceeded
#
# Error Payload Structure:
#
# All error responses in the A2A protocol, regardless of binding, MUST convey the following information:
#
# 1. Error Code: A machine-readable identifier for the error type (e.g., string code, numeric code, or
#    protocol-specific status)
# 2. Error Message: A human-readable description of the error
# 3. Error Details (optional): An array of objects providing additional structured information about the
#    error. Each object in the array MUST include a @type key that identifies the object's type (using
#    ProtoJSON Any representation). Well-known types from the google.rpc error model (e.g., ErrorInfo,
#    BadRequest) SHOULD be used where applicable. Error details may be used for:
#    - Affected fields or parameters
#    - Contextual information (e.g., task ID, timestamp)
#    - Suggestions for resolution
#
# Protocol bindings MUST map these elements to their native error representations while preserving
# semantic meaning.
#
# A2A-Specific Errors:
#
# | Error Name                            | Description
# | ------------------------------------- | ---------------------------------------------------------------------------
# | TaskNotFoundError                     | The specified task ID does not correspond to an existing or accessible task.
# | TaskNotCancelableError                | An attempt was made to cancel a task that is not in a cancelable state.
# | PushNotificationNotSupportedError     | Client attempted to use unsupported push notification features.
# | UnsupportedOperationError             | The requested operation or aspect is unsupported by this server agent.
# | ContentTypeNotSupportedError          | A Media Type in request parts or artifacts is unsupported.
# | InvalidAgentResponseError             | An agent returned a response that does not conform to the specification.
# | ExtendedAgentCardNotConfiguredError   | The agent lacks a configured extended agent card when required.
# | ExtensionSupportRequiredError         | A required extension was not declared as supported by the client.
# | VersionNotSupportedError              | The requested A2A-Version is not supported by the agent.
test do
  describe "A2A::Error" do
    it "has code, http_status, and message" do
      err = A2A::Error.new("boom", code: -32000, http_status: 500)
      err.code.should == -32000
      err.http_status.should == 500
      err.message.should == "boom"
    end

    it "serializes to_h without data when error_data is nil" do
      err = A2A::Error.new("boom", code: -32000, http_status: 500)
      h = err.to_h
      h[:code].should == -32000
      h[:http_status].should == 500
      h[:message].should == "boom"
      h.key?(:data).should == false
    end
  end

  describe "A2A::TaskNotFoundError" do
    it "has correct code and http_status" do
      err = A2A::TaskNotFoundError.new("task-123")
      err.code.should == -32001
      err.http_status.should == 404
      err.message.should == "Task not found"
    end

    it "serializes to_h with structured error_data" do
      err = A2A::TaskNotFoundError.new("task-123")
      h = err.to_h
      h[:data].first["reason"].should == "TASK_NOT_FOUND"
      h[:data].first["metadata"]["taskId"].should == "task-123"
    end

    it "accepts a custom message" do
      err = A2A::TaskNotFoundError.new("task-123", message: "No such task")
      err.message.should == "No such task"
    end
  end

  describe "A2A::TaskNotCancelableError" do
    it "has correct code and http_status" do
      err = A2A::TaskNotCancelableError.new("task-123", state: "TASK_STATE_COMPLETED")
      err.code.should == -32002
      err.http_status.should == 400
    end

    it "includes task and state in error_data" do
      err = A2A::TaskNotCancelableError.new("task-123", state: "TASK_STATE_COMPLETED")
      h = err.to_h
      h[:data].first["reason"].should == "TASK_NOT_CANCELABLE"
      h[:data].first["metadata"]["taskId"].should == "task-123"
      h[:data].first["metadata"]["state"].should == "TASK_STATE_COMPLETED"
    end
  end

  describe "A2A::PushNotificationNotSupportedError" do
    it "has correct code and http_status" do
      err = A2A::PushNotificationNotSupportedError.new
      err.code.should == -32003
      err.http_status.should == 400
    end

    it "has PUSH_NOTIFICATION_NOT_SUPPORTED in error_data" do
      err = A2A::PushNotificationNotSupportedError.new
      err.to_h[:data].first["reason"].should == "PUSH_NOTIFICATION_NOT_SUPPORTED"
      err.to_h[:data].first["domain"].should == "a2a-protocol.org"
    end
  end

  describe "A2A::UnsupportedOperationError" do
    it "has correct code and http_status" do
      err = A2A::UnsupportedOperationError.new
      err.code.should == -32004
      err.http_status.should == 400
    end

    it "accepts a custom message" do
      err = A2A::UnsupportedOperationError.new(message: "Streaming not supported")
      err.message.should == "Streaming not supported"
    end

    it "has UNSUPPORTED_OPERATION in error_data" do
      err = A2A::UnsupportedOperationError.new
      err.to_h[:data].first["reason"].should == "UNSUPPORTED_OPERATION"
    end
  end

  describe "A2A::ContentTypeNotSupportedError" do
    it "has correct code and http_status" do
      err = A2A::ContentTypeNotSupportedError.new("image/bmp")
      err.code.should == -32005
      err.http_status.should == 400
    end

    it "includes content type in metadata" do
      err = A2A::ContentTypeNotSupportedError.new("image/bmp")
      err.to_h[:data].first["reason"].should == "CONTENT_TYPE_NOT_SUPPORTED"
      err.to_h[:data].first["metadata"]["contentType"].should == "image/bmp"
    end
  end

  describe "A2A::InvalidAgentResponseError" do
    it "has correct code and http_status" do
      err = A2A::InvalidAgentResponseError.new
      err.code.should == -32006
      err.http_status.should == 500
    end

    it "has INVALID_AGENT_RESPONSE in error_data" do
      err = A2A::InvalidAgentResponseError.new
      err.to_h[:data].first["reason"].should == "INVALID_AGENT_RESPONSE"
    end
  end

  describe "A2A::ExtendedAgentCardNotConfiguredError" do
    it "has correct code and http_status" do
      err = A2A::ExtendedAgentCardNotConfiguredError.new
      err.code.should == -32007
      err.http_status.should == 400
    end

    it "has EXTENDED_AGENT_CARD_NOT_CONFIGURED in error_data" do
      err = A2A::ExtendedAgentCardNotConfiguredError.new
      err.to_h[:data].first["reason"].should == "EXTENDED_AGENT_CARD_NOT_CONFIGURED"
    end
  end

  describe "A2A::ExtensionSupportRequiredError" do
    it "has correct code and http_status" do
      err = A2A::ExtensionSupportRequiredError.new("my-extension")
      err.code.should == -32008
      err.http_status.should == 400
    end

    it "includes extension in metadata" do
      err = A2A::ExtensionSupportRequiredError.new("my-extension")
      err.to_h[:data].first["reason"].should == "EXTENSION_SUPPORT_REQUIRED"
      err.to_h[:data].first["metadata"]["extension"].should == "my-extension"
    end
  end

  describe "A2A::VersionNotSupportedError" do
    it "has correct code and http_status" do
      err = A2A::VersionNotSupportedError.new("0.5")
      err.code.should == -32009
      err.http_status.should == 400
    end

    it "includes version in metadata" do
      err = A2A::VersionNotSupportedError.new("0.5")
      err.to_h[:data].first["reason"].should == "VERSION_NOT_SUPPORTED"
      err.to_h[:data].first["metadata"]["version"].should == "0.5"
    end
  end

  describe "A2A::InvalidParamsError" do
    it "has correct code and http_status" do
      err = A2A::InvalidParamsError.new("topic is required")
      err.code.should == -32602
      err.http_status.should == 400
      err.message.should == "topic is required"
    end

    it "has no error_data when fields not provided" do
      err = A2A::InvalidParamsError.new("bad params")
      err.to_h.key?(:data).should == false
    end

    it "includes fields in error_data when provided" do
      err = A2A::InvalidParamsError.new("invalid fields", fields: ["topic", "message"])
      err.to_h[:data].first["reason"].should == "INVALID_PARAMS"
      err.to_h[:data].first["metadata"]["fields"].should == "topic, message"
    end
  end

  describe "A2A::Internal::Errors::PushNotificationConfigNotFoundError" do
    it "has correct code and http_status" do
      err = A2A::Internal::Errors::PushNotificationConfigNotFoundError.new("task-123", "config-456")
      err.code.should == -32001
      err.http_status.should == 404
    end

    it "includes task and config in error_data" do
      err = A2A::Internal::Errors::PushNotificationConfigNotFoundError.new("task-123", "config-456")
      h = err.to_h
      h[:data].first["metadata"]["taskId"].should == "task-123"
      h[:data].first["metadata"]["configId"].should == "config-456"
    end

    it "is a subclass of A2A::Error" do
      err = A2A::Internal::Errors::PushNotificationConfigNotFoundError.new("t", "c")
      err.is_a?(A2A::Error).should == true
    end
  end
end
