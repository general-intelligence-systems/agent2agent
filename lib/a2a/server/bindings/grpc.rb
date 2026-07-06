# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    module Bindings
      # Rack middleware reserving a path prefix (default "/grpc") for the
      # A2A gRPC protocol binding. Requests under the prefix get 501 Not
      # Implemented; all other requests pass through untouched.
      #
      class Grpc
        def initialize(app, path_prefix: "/grpc")
          @app = app
          @path_prefix = path_prefix
        end

        def call(env)
          return @app.call(env) unless claims?(env["PATH_INFO"])

          body = { "type" => "error", "title" => "gRPC binding is not implemented", "status" => 501 }
          [501, { "content-type" => "application/problem+json" }, [JSON.generate(body)]]
        end

        private

          def claims?(path)
            return true if path == @path_prefix

            prefix = @path_prefix.end_with?("/") ? @path_prefix : "#{@path_prefix}/"
            path.start_with?(prefix)
          end
      end
    end
  end
end
