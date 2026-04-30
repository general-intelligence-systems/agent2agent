# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server"

module A2A
  module Bindings
    # Rack middleware implementing the A2A JSON-RPC 2.0 protocol binding.
    #
    # Parses the JSON-RPC envelope, sets env["a2a.operation"] and
    # env["a2a.params"], calls downstream, reads env["a2a.result"]
    # (a Schema::Definition), and wraps it in the JSON-RPC response.
    #
    # Passes through to @app for non-JSON-RPC requests.
    #
    class JsonRpc
      def initialize(app)
        @app = app
      end

      def call(env)
        # If another binding already identified the operation, pass through.
        return @app.call(env) if env["a2a.operation"]

        req = Rack::Request.new(env)
        return @app.call(env) unless req.post?

        body = req.body.read
        req.body.rewind

        begin
          rpc = JSON.parse(body)
        rescue JSON::ParserError
          return @app.call(env)
        end

        return @app.call(env) unless rpc.is_a?(Hash) && rpc["jsonrpc"]

        id     = rpc["id"]
        method = rpc["method"]
        params = rpc["params"] || {}

        op = Proto.operation(method)
        return error_response(id, -32601, "Method not found") unless op

        env["a2a.operation"] = op.name
        env["a2a.params"]    = params

        @app.call(env)

        result = env["a2a.result"]
        success_response(id, result)
      end

      private

        def success_response(id, result)
          body = result.respond_to?(:to_h) ? result.to_h : (result || {})
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, result: body)]]
        end

        def error_response(id, code, message)
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, error: { code: code, message: message })]]
        end
    end
  end
end

test do
  server = A2A::Server.new
  rack   = Rack::MockRequest.new(server)

  A2A::Proto.operations.each do |op|
    it "#{op.json_rpc_method} returns valid #{op.response_type}" do
      body = JSON.generate({
        jsonrpc: "2.0",
        id: 1,
        method: op.json_rpc_method,
        params: {}
      })

      response = rack.post("/", input: body, "CONTENT_TYPE" => "application/json")
      parsed   = JSON.parse(response.body)

      if parsed["error"]
        parsed["error"].should.be.nil
      end

      next unless op.response_schema

      result = parsed["result"]
      schema_obj = op.response_schema.new(result)
      schema_obj.valid?.should == true
    end
  end
end
