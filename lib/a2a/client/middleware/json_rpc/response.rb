# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"
require "json"

module A2A
  class Client
    module Middleware
      module JsonRpc
        # Faraday response middleware that unwraps JSON-RPC 2.0 responses
        # and converts the result into A2A::Protocol::JsonSchema::Definition objects.
        #
        # Reads env.request.context[:a2a_operation] to determine which
        # Schema class to instantiate. If no operation is set, passes through.
        #
        # Raises on JSON-RPC error responses.
        #
        class Response < ::Faraday::Middleware
          def on_complete(env)
            operation = env.request.context&.dig(:a2a_operation)
            return unless operation

            parsed = env.body
            return if parsed.nil?

            # Handle string bodies (if JSON response middleware hasn't run)
            if parsed.is_a?(String)
              return if parsed.empty?
              parsed = JSON.parse(parsed)
            end

            # Handle JSON-RPC error responses
            if parsed.is_a?(Hash) && (err = parsed["error"])
              raise A2A::JsonRpcError.new(err["message"], code: err["code"], data: err["data"])
            end

            # Extract result from JSON-RPC envelope
            result = parsed.is_a?(Hash) && parsed.key?("result") ? parsed["result"] : parsed

            schema_class = operation.response_schema
            unless schema_class
              env.body = result
              return
            end

            env.body = schema_class.new(result)
          rescue JSON::ParserError
            # Leave body as-is if JSON parsing fails
          end
        end
      end
    end
  end
end

::Faraday::Response.register_middleware(a2a_json_rpc: A2A::Client::Middleware::JsonRpc::Response)

__END__
describe "A2A::Client::Middleware::JsonRpc::Response" do
  middleware = A2A::Client::Middleware::JsonRpc::Response
  operation = A2A::Protocol::Protobuf.operation("GetTask")

  it "unwraps JSON-RPC result into Schema object" do
    env = ::Faraday::Env.new
    env.body = {
      "jsonrpc" => "2.0", "id" => 1,
      "result" => {
        "id" => "task-123", "contextId" => "ctx-456",
        "status" => { "state" => "TASK_STATE_SUBMITTED" }
      }
    }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_complete(env)

    env.body.should.be.kind_of(A2A::Protocol::JsonSchema::Definition)
    env.body.id.should == "task-123"
    env.body.context_id.should == "ctx-456"
  end

  it "raises on JSON-RPC error" do
    env = ::Faraday::Env.new
    env.body = {
      "jsonrpc" => "2.0", "id" => 1,
      "error" => { "code" => -32600, "message" => "Invalid Request" }
    }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    lambda { middleware.new(nil).on_complete(env) }.should.raise(A2A::JsonRpcError)
  end

  it "returns raw hash when response_schema is nil" do
    op = A2A::Protocol::Protobuf.operation("DeleteTaskPushNotificationConfig")
    env = ::Faraday::Env.new
    env.body = { "jsonrpc" => "2.0", "id" => 1, "result" => {} }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: op }

    middleware.new(nil).on_complete(env)

    env.body.should == {}
  end

  it "passes through when no operation is set" do
    env = ::Faraday::Env.new
    env.body = { "foo" => "bar" }
    env.request = ::Faraday::RequestOptions.new

    middleware.new(nil).on_complete(env)

    env.body.should == { "foo" => "bar" }
  end

  it "handles string body" do
    env = ::Faraday::Env.new
    env.body = JSON.generate({
      "jsonrpc" => "2.0", "id" => 1,
      "result" => { "id" => "task-1", "contextId" => "ctx-1", "status" => { "state" => "TASK_STATE_COMPLETED" } }
    })
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_complete(env)

    env.body.should.be.kind_of(A2A::Protocol::JsonSchema::Definition)
    env.body.id.should == "task-1"
  end
end
