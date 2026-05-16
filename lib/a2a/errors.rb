# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # Base error class for A2A protocol errors.
  #
  # Each subclass carries its own JSON-RPC error code, HTTP status,
  # and structured error data. The handler layer rescues these and
  # calls #to_h to populate env["a2a.error"] for the binding layer.
  #
  #   raise A2A::TaskNotFoundError.new("abc-123")
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

  # Raised when a task or push notification config cannot be found.
  #
  #   raise A2A::TaskNotFoundError.new(task_id)
  #
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

  # Raised when a task is in a terminal state and cannot be canceled.
  #
  #   raise A2A::TaskNotCancelableError.new(task_id, state: task[:state])
  #
  class TaskNotCancelableError < Error
    def initialize(task_id, state:, message: "Task is not cancelable")
      @task_id = task_id
      @state   = state
      super(message, code: -32002, http_status: 409)
    end

    def error_data
      [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "TASK_NOT_CANCELABLE",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "taskId" => @task_id.to_s, "state" => @state },
      }]
    end
  end

  # Raised when an operation is not supported (e.g. subscribing to
  # a terminal task, extended agent card not available).
  #
  #   raise A2A::UnsupportedOperationError.new
  #   raise A2A::UnsupportedOperationError.new(message: "Extended agent card is not supported")
  #
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

  # Raised when required parameters are missing or invalid.
  #
  #   raise A2A::InvalidParamsError.new("topic is required")
  #
  class InvalidParamsError < Error
    def initialize(message)
      super(message, code: -32602, http_status: 422)
    end
  end

  # Raised when a push notification config cannot be found.
  #
  #   raise A2A::PushNotificationConfigNotFoundError.new(task_id, config_id)
  #
  class PushNotificationConfigNotFoundError < Error
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
      err.http_status.should == 409
    end

    it "includes task and state in error_data" do
      err = A2A::TaskNotCancelableError.new("task-123", state: "TASK_STATE_COMPLETED")
      h = err.to_h
      h[:data].first["reason"].should == "TASK_NOT_CANCELABLE"
      h[:data].first["metadata"]["taskId"].should == "task-123"
      h[:data].first["metadata"]["state"].should == "TASK_STATE_COMPLETED"
    end
  end

  describe "A2A::UnsupportedOperationError" do
    it "has correct code and http_status" do
      err = A2A::UnsupportedOperationError.new
      err.code.should == -32004
      err.http_status.should == 400
    end

    it "accepts a custom message" do
      err = A2A::UnsupportedOperationError.new(message: "Extended agent card is not supported")
      err.message.should == "Extended agent card is not supported"
    end

    it "has UNSUPPORTED_OPERATION in error_data" do
      err = A2A::UnsupportedOperationError.new
      err.to_h[:data].first["reason"].should == "UNSUPPORTED_OPERATION"
    end
  end

  describe "A2A::InvalidParamsError" do
    it "has correct code and http_status" do
      err = A2A::InvalidParamsError.new("topic is required")
      err.code.should == -32602
      err.http_status.should == 422
      err.message.should == "topic is required"
    end

    it "has no error_data" do
      err = A2A::InvalidParamsError.new("bad params")
      err.to_h.key?(:data).should == false
    end
  end

  describe "A2A::PushNotificationConfigNotFoundError" do
    it "has correct code and http_status" do
      err = A2A::PushNotificationConfigNotFoundError.new("task-123", "config-456")
      err.code.should == -32001
      err.http_status.should == 404
    end

    it "includes task and config in error_data" do
      err = A2A::PushNotificationConfigNotFoundError.new("task-123", "config-456")
      h = err.to_h
      h[:data].first["metadata"]["taskId"].should == "task-123"
      h[:data].first["metadata"]["configId"].should == "config-456"
    end
  end
end
