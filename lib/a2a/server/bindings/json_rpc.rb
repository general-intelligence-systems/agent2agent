# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server/sse"

module A2A
  class Server
    module Bindings
      # Rack middleware implementing the A2A JSON-RPC 2.0 protocol binding.
    #
    # Claims requests under its path prefix (default "/", i.e. everything)
    # that were not already claimed by a binding earlier in the stack
    # (env["a2a.body"] unset); all other requests pass through untouched.
    #
    # Strips the JSON-RPC envelope from the inbound request, setting
    # env keys for the method name, request id, and parsed params.
    # Calls downstream. On return, wraps env["a2a.result"] back into
    # a JSON-RPC response envelope.
    #
    # Streaming operations (SendStreamingMessage, SubscribeToTask):
    # When the handler sets env["a2a.stream"] to an SSE::Stream (which is
    # a Protocol::HTTP::Body::Writable, which is a Readable), Falcon's
    # protocol-rack passes it through untouched. True async streaming
    # with backpressure — no Thread::Queue, no #each polling.
    #
    class JsonRpc
      def initialize(app, path_prefix: "/")
        @app = app
        @path_prefix = path_prefix
      end

      def call(env)
        return @app.call(env) if env.key?("a2a.body")

        req = Rack::Request.new(env)
        return @app.call(env) unless claims?(req.path_info)

        body = req.body.read
        req.body.rewind

        begin
          rpc = JSON.parse(body)
        rescue JSON::ParserError
          return error_response(nil, -32700, "Parse error")
        end

        unless rpc.is_a?(Hash) && rpc["jsonrpc"] == "2.0"
          return error_response(nil, -32600, "Invalid Request")
        end

        id     = rpc["id"]
        method = rpc["method"]
        params = rpc["params"] || {}

        env["a2a.json_rpc_id"]     = id
        env["a2a.json_rpc_method"] = method
        env["a2a.body"]            = params

        result = @app.call(env)

        # Check if the result is an error object
        if result.is_a?(A2A::Error)
          return error_response(id, result.code, result.message, result.error_data)
        end

        # Check if handler set up a streaming response.
        # The stream is an SSE::Stream (Protocol::HTTP::Body::Readable).
        if (stream = env["a2a.stream"])
          return [200, A2A::Server::SSE::Stream.headers, stream]
        end

        success_response(id, result)
      end

      private

        def claims?(path)
          # A request to the exact mount point of a mounted app (e.g. Rails
          # `mount server, at: "/agent1"`) arrives with an empty PATH_INFO.
          path = "/" if path.to_s.empty?

          return true if path == @path_prefix

          prefix = @path_prefix.end_with?("/") ? @path_prefix : "#{@path_prefix}/"
          path.start_with?(prefix)
        end

        def success_response(id, result)
          body = result.respond_to?(:to_h) ? result.to_h : (result || {})
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, result: body)]]
        end

        def error_response(id, code, message, data = nil)
          err = { code: code, message: message }
          err[:data] = data if data
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, error: err)]]
        end
    end
    end
  end
end

__END__
describe "A2A::Server::Bindings::JsonRpc" do
  require "a2a/test_helpers"

  server = A2A::Server.new(agent_card: { "name" => "Test" })
  server.register(A2A::TestHelpers.stub_agent)
  rack = Rack::MockRequest.new(server)

  A2A::Protocol::Protobuf.operations.each do |op|
    it "#{op.json_rpc_method} returns valid #{op.response_type}" do
      body = JSON.generate({
        jsonrpc: "2.0",
        id: 1,
        method: op.json_rpc_method,
        params: {}
      })

      response = rack.post("/", input: body, "CONTENT_TYPE" => "application/json")
      parsed   = JSON.parse(response.body)

      parsed["error"].should.be.nil

      if op.response_schema
        result = parsed["result"]
        schema_obj = op.response_schema.new(result)
        schema_obj.valid?.should == true
      end
    end
  end
end
