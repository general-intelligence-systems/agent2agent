# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Bindings
    # Rack middleware implementing the A2A HTTP+JSON/REST protocol binding.
    #
    # Matches the request verb + path against Proto.operations HTTP
    # annotations. Sets env["a2a.operation"] and env["a2a.params"],
    # calls downstream, reads env["a2a.result"] (a Schema::Definition),
    # and formats the REST response.
    #
    # Passes through to @app for non-matching requests.
    #
    class Rest
      def initialize(app)
        @app = app
      end

      def call(env)
        req  = Rack::Request.new(env)
        verb = req.request_method.downcase
        path = req.path_info

        op = match_operation(verb, path)
        return @app.call(env) unless op

        params = {}
        if req.post? || req.put? || req.patch?
          begin
            params = JSON.parse(req.body.read) rescue {}
          end
        end

        # Merge path params (e.g. {id}, {task_id}) into params
        path_params = extract_path_params(op.rest_path, path)
        params.merge!(path_params)

        # Merge query params for GET/DELETE
        params.merge!(req.params) if req.get? || req.delete?

        env["a2a.operation"] = op.name
        env["a2a.params"]    = params

        @app.call(env)

        result = env["a2a.result"]
        success_response(result)
      end

      private

        def match_operation(verb, path)
          Proto.operations.find do |op|
            op.http_bindings.any? do |b|
              b.verb == verb && path_matches?(b.path, path)
            end
          end
        end

        # Match a proto path pattern like "/tasks/{id=*}" against
        # an actual request path like "/tasks/abc-123".
        def path_matches?(pattern, path)
          regex = pattern_to_regex(pattern)
          path.match?(regex)
        end

        def pattern_to_regex(pattern)
          re = pattern.gsub(/\{[^}]+\}/, '([^/]+)')
          /\A#{re}\z/
        end

        def extract_path_params(pattern, path)
          names = pattern.scan(/\{(\w+)(?:=[^}]*)?\}/).flatten
          regex = pattern_to_regex(pattern)
          match = path.match(regex)
          return {} unless match

          names.zip(match.captures).to_h
        end

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
  server = A2A::Server.new
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

      if parsed["error"]
        parsed["error"].should.be.nil
      end

      next unless op.response_schema

      schema_obj = op.response_schema.new(parsed)
      schema_obj.valid?.should == true
    end
  end
end
