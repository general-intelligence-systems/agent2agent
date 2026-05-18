# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"
require "json"

module A2A
  module Faraday
    module Middleware
      module REST
        # Faraday response middleware for the A2A HTTP+JSON/REST binding.
        #
        # Unlike the JSON-RPC binding, REST responses have no envelope —
        # the body IS the result directly. Errors are signaled via HTTP
        # status codes with application/problem+json bodies.
        #
        # Reads env.request.context[:a2a_operation] to determine which
        # Schema class to instantiate. If no operation is set, passes through.
        #
        class Response < ::Faraday::Middleware
          def on_complete(env)
            operation = env.request.context&.dig(:a2a_operation)
            return unless operation

            if env.status >= 400
              parsed = env.body
              if parsed.is_a?(Hash)
                message = parsed["title"] || parsed["message"] || parsed.to_s
                data    = parsed["detail"]
              else
                message = parsed.to_s
                data    = nil
              end
              raise A2A::RestError.new(message, http_status: env.status, data: data)
            end

            parsed = env.body
            return if parsed.nil?

            if parsed.is_a?(String)
              return if parsed.empty?
              parsed = JSON.parse(parsed)
            end

            schema_class = operation.response_schema
            unless schema_class
              env.body = parsed
              return
            end

            env.body = schema_class.new(parsed)
          rescue JSON::ParserError
            # Leave body as-is if JSON parsing fails
          end
        end
      end
    end
  end
end

::Faraday::Response.register_middleware(a2a_rest: A2A::Faraday::Middleware::REST::Response)

test do
  middleware = A2A::Faraday::Middleware::REST::Response
  operation = A2A::Proto.operation("GetTask")

  it "wraps response body in Schema object directly (no envelope)" do
    env = ::Faraday::Env.new
    env.status = 200
    env.body = {
      "id" => "task-123", "contextId" => "ctx-456",
      "status" => { "state" => "TASK_STATE_SUBMITTED" }
    }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_complete(env)

    env.body.should.be.kind_of(A2A::Schema::Definition)
    env.body.id.should == "task-123"
    env.body.context_id.should == "ctx-456"
  end

  it "returns raw hash when response_schema is nil" do
    op = A2A::Proto.operation("DeleteTaskPushNotificationConfig")
    env = ::Faraday::Env.new
    env.status = 200
    env.body = {}
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: op }

    middleware.new(nil).on_complete(env)

    env.body.should == {}
  end

  it "raises on HTTP 4xx error" do
    env = ::Faraday::Env.new
    env.status = 400
    env.body = { "type" => "error", "title" => "Bad Request", "status" => 400 }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    lambda { middleware.new(nil).on_complete(env) }.should.raise(A2A::RestError)
  end

  it "raises on HTTP 5xx error" do
    env = ::Faraday::Env.new
    env.status = 500
    env.body = { "type" => "error", "title" => "Internal Server Error", "status" => 500 }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    lambda { middleware.new(nil).on_complete(env) }.should.raise(A2A::RestError)
  end

  it "passes through when no operation is set" do
    env = ::Faraday::Env.new
    env.status = 200
    env.body = { "foo" => "bar" }
    env.request = ::Faraday::RequestOptions.new

    middleware.new(nil).on_complete(env)

    env.body.should == { "foo" => "bar" }
  end

  it "handles string body" do
    env = ::Faraday::Env.new
    env.status = 200
    env.body = JSON.generate({
      "id" => "task-1", "contextId" => "ctx-1",
      "status" => { "state" => "TASK_STATE_COMPLETED" }
    })
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_complete(env)

    env.body.should.be.kind_of(A2A::Schema::Definition)
    env.body.id.should == "task-1"
  end
end
