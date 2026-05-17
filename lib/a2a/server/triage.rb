# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    # Rack middleware that resolves which A2A operation a request targets.
    #
    # Reads the raw protocol data left in env by the binding middleware
    # (JSON-RPC method name or HTTP verb + path), looks up the matching
    # Proto::Operation, wraps the request body into a Schema::Definition,
    # and sets env keys for downstream consumption by the Dispatcher.
    #
    # Env keys read:
    #   "a2a.json_rpc_method" — set by Bindings::JsonRpc
    #   "a2a.verb"            — set by Bindings::Rest
    #   "a2a.path"            — set by Bindings::Rest
    #   "a2a.body"            — set by either binding
    #
    # Env keys set:
    #   "a2a.operation"       — operation name string (e.g. "SendMessage")
    #   "a2a.proto_operation" — Proto::Operation instance
    #   "a2a.request"         — Schema::Definition instance (validated request)
    #
    class Triage
      def initialize(app)
        @app = app
      end

      def call(env)
        Console.info(self) { "Triaging: #{env}" }
        op = resolve_operation(env)

        unless op
          return A2A::UnsupportedOperationError.new(message: "Unknown operation")
        end

        env["a2a.operation"]       = op.name
        env["a2a.proto_operation"] = op

        body = env["a2a.body"] || {}

        # For REST, merge extracted path params into the body.
        if env["a2a.path"]
          path_params = extract_path_params(op.rest_path, env["a2a.path"])
          body = body.merge(path_params)
        end

        if op.request_schema
          env["a2a.request"] = op.request_schema.new(body)
        end

        @app.call(env)
      end

      private

        def resolve_operation(env)
          if env["a2a.json_rpc_method"]
            Proto.operation(env["a2a.json_rpc_method"])
          elsif env["a2a.verb"] && env["a2a.path"]
            match_rest_operation(env["a2a.verb"], env["a2a.path"])
          end
        end

        def match_rest_operation(verb, path)
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
    end
  end
end
