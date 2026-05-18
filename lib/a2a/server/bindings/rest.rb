# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/sse"

module A2A
  class Server
    module Bindings
      # Rack middleware implementing the A2A HTTP+JSON/REST protocol binding.
    #
    # Extracts the HTTP verb, path, and request body/params into env keys.
    # Calls downstream. On return, wraps env["a2a.result"] into a REST
    # response with content-type application/a2a+json.
    #
    # Streaming operations:
    # When the handler sets env["a2a.stream"] to an SSE::Stream (which is
    # a Protocol::HTTP::Body::Readable), Falcon streams it natively —
    # no wrapping, no #each conversion, true async with backpressure.
    #
    class Rest
      def initialize(app)
        @app = app
      end

      def call(env)
        req = Rack::Request.new(env)

        env["a2a.verb"] = req.request_method.downcase
        env["a2a.path"] = req.path_info

        params = {}
        if req.post? || req.put? || req.patch?
          begin
            params = JSON.parse(req.body.read) rescue {}
          end
        end

        # Merge query params for GET/DELETE
        params.merge!(req.params) if req.get? || req.delete?

        env["a2a.body"] = params

        result = @app.call(env)

        # Check if the result is an error object
        if result.is_a?(A2A::Error)
          return error_response(result.http_status, result.message, result.error_data)
        end

        # Check if handler set up a streaming response.
        # The stream is an SSE::Stream (Protocol::HTTP::Body::Readable).
        if (stream = env["a2a.stream"])
          return [200, A2A::SSE::Stream.headers, stream]
        end

        success_response(result)
      end

      private

        def success_response(result)
          body = result.respond_to?(:to_h) ? result.to_h : (result || {})
          [200, { "content-type" => "application/a2a+json" },
           [JSON.generate(body)]]
        end

        def error_response(status, message, data = nil)
          body = { "type" => "error", "title" => message, "status" => status }
          body["detail"] = data if data
          [status, { "content-type" => "application/problem+json" },
           [JSON.generate(body)]]
        end
    end
    end
  end
end

test do
  require "a2a/test_helpers"

  server = A2A::Server.new(agent_card: { "name" => "Test" })
  server.register(A2A::TestHelpers.stub_agent)
  rack = Rack::MockRequest.new(server)

  A2A::Proto.operations.each do |op|
    it "#{op.rest_verb.upcase} #{op.rest_path} returns valid #{op.response_type}" do
      # Build request path, replacing {id=*} etc with a placeholder value
      path = op.rest_path.gsub(/\{[^}]+\}/, "test-id")

      input = nil
      if op.http_bindings.first.body
        input = JSON.generate({})
      end

      response = rack.request(op.rest_verb.upcase, path,
        input: input,
        "CONTENT_TYPE" => "application/a2a+json")

      parsed = JSON.parse(response.body)

      parsed["error"].should.be.nil

      if op.response_schema
        schema_obj = op.response_schema.new(parsed)
        schema_obj.valid?.should == true
      end
    end
  end
end
