# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # Raised by the JSON-RPC response middleware when the server returns
  # a JSON-RPC 2.0 error envelope. Preserves the wire code, message,
  # and optional structured data array.
  #
  # JSON-RPC errors are always delivered over HTTP 200 — the error
  # lives inside the JSON-RPC envelope, not the HTTP status.
  #
  class JsonRpcError < Error
    def initialize(message, code:, data: nil)
      @wire_data = data
      super(message, code: code, http_status: 200)
    end

    def error_data
      @wire_data
    end
  end
end

test do
  describe "A2A::JsonRpcError" do
    it "has correct code and message" do
      err = A2A::JsonRpcError.new("Task not found", code: -32001)
      err.code.should == -32001
      err.message.should == "Task not found"
    end

    it "always has http_status 200" do
      err = A2A::JsonRpcError.new("fail", code: -32001)
      err.http_status.should == 200
    end

    it "preserves wire data" do
      data = [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "TASK_NOT_FOUND",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "taskId" => "t-1" },
      }]
      err = A2A::JsonRpcError.new("Task not found", code: -32001, data: data)
      err.error_data.should == data
      err.error_data.first["reason"].should == "TASK_NOT_FOUND"
    end

    it "returns nil error_data when no data provided" do
      err = A2A::JsonRpcError.new("fail", code: -32600)
      err.error_data.should.be.nil
    end

    it "is a subclass of A2A::Error" do
      err = A2A::JsonRpcError.new("fail", code: -32001)
      err.is_a?(A2A::Error).should == true
    end

    it "serializes to_h with wire data" do
      data = [{ "reason" => "TASK_NOT_FOUND" }]
      err = A2A::JsonRpcError.new("Task not found", code: -32001, data: data)
      h = err.to_h
      h[:code].should == -32001
      h[:http_status].should == 200
      h[:message].should == "Task not found"
      h[:data].should == data
    end
  end
end
