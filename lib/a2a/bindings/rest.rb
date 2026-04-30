# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Bindings
    # Rack middleware implementing the A2A HTTP+JSON/REST protocol binding.
    #
    # Extracts the HTTP verb, path, and request body/params into env keys.
    # Calls downstream. On return, wraps env["a2a.result"] into a REST
    # response with content-type application/a2a+json.
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

        @app.call(env)

        result = env["a2a.result"]
        success_response(result)
      end

      private

        def success_response(result)
          body = result.respond_to?(:to_h) ? result.to_h : (result || {})
          [200, { "content-type" => "application/a2a+json" },
           [JSON.generate(body)]]
        end

        def error_response(status, message)
          [status, { "content-type" => "application/a2a+json" },
           [JSON.generate(error: { code: status, message: message })]]
        end
    end
  end
end

test do
  server = A2A::Server.new(agent_card: { "name" => "Test" })
  rack   = Rack::MockRequest.new(server)

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
