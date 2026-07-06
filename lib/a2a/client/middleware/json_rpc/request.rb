# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"

module A2A
  class Client
    module Middleware
      module JsonRpc
        # Faraday request middleware that wraps the request body in a
        # JSON-RPC 2.0 envelope.
        #
        # Reads env.request.context[:a2a_operation] to determine the
        # JSON-RPC method name. If no operation is set, passes through.
        #
        class Request < ::Faraday::Middleware
          def on_request(env)
            operation = env.request.context&.dig(:a2a_operation)
            return unless operation

            # POST to the server's mount root — env.url already carries the
            # base path (e.g. "/agent1" when mounted at a subpath).
            env.method = :post

            env.body = {
              jsonrpc: "2.0",
              id:      next_id,
              method:  operation.json_rpc_method,
              params:  env.body || {},
            }
          end

          private

            def next_id
              @id_counter = (@id_counter || 0) + 1
            end
        end
      end
    end
  end
end

::Faraday::Request.register_middleware(a2a_json_rpc: A2A::Client::Middleware::JsonRpc::Request)

__END__
describe "A2A::Client::Middleware::JsonRpc::Request" do
  middleware = A2A::Client::Middleware::JsonRpc::Request
  operation = A2A::Protocol::Protobuf.operation("SendMessage")

  it "wraps body in JSON-RPC 2.0 envelope and sets path to /" do
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "message" => { "role" => "ROLE_USER" } }
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_request(env)

    env.url.path.should == "/"
    env.method.should == :post
    env.body[:jsonrpc].should == "2.0"
    env.body[:id].should == 1
    env.body[:method].should == "SendMessage"
    env.body[:params].should == { "message" => { "role" => "ROLE_USER" } }
  end

  it "increments the id" do
    mw = middleware.new(nil)

    env1 = ::Faraday::Env.new
    env1.url = URI.parse("http://localhost:9292/")
    env1.body = {}
    env1.request = ::Faraday::RequestOptions.new
    env1.request.context = { a2a_operation: operation }
    mw.on_request(env1)

    env2 = ::Faraday::Env.new
    env2.url = URI.parse("http://localhost:9292/")
    env2.body = {}
    env2.request = ::Faraday::RequestOptions.new
    env2.request.context = { a2a_operation: operation }
    mw.on_request(env2)

    env2.body[:id].should == env1.body[:id] + 1
  end

  it "passes through when no operation is set" do
    env = ::Faraday::Env.new
    env.body = { "foo" => "bar" }
    env.request = ::Faraday::RequestOptions.new

    middleware.new(nil).on_request(env)

    env.body.should == { "foo" => "bar" }
  end
end
