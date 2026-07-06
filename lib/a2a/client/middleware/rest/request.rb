# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"

module A2A
  class Client
    module Middleware
      module REST
        # Faraday request middleware that rewrites the request for the
        # A2A HTTP+JSON/REST protocol binding.
        #
        # Reads env.request.context[:a2a_operation] to determine the
        # HTTP verb and path. Interpolates path parameters from the
        # request body (e.g. {id=*} placeholders) and prefixes the
        # /rest mount point. For GET/DELETE operations, remaining
        # params become query string parameters.
        #
        # Sets Content-Type to application/a2a+json for POST requests.
        #
        class Request < ::Faraday::Middleware
          def on_request(env)
            operation = env.request.context&.dig(:a2a_operation)
            return unless operation

            params = env.body || {}
            path = interpolate_path(operation.rest_path, params)
            remaining = remove_path_params(operation.rest_path, params)

            # Prefix /rest under the base path, so servers mounted at a
            # subpath (e.g. "/agent1") keep working.
            env.url.path = "#{env.url.path.chomp("/")}/rest#{path}"
            env.method = operation.rest_verb.to_sym

            if [:get, :delete].include?(env.method)
              env.params ||= {}
              remaining.each { |k, v| env.params[k.to_s] = v }
              env.body = nil
            else
              # Serialize to JSON here rather than relying on Faraday's
              # built-in :json middleware, which only recognizes
              # application/json and application/vnd.*+json content types.
              env.body = remaining.is_a?(String) ? remaining : JSON.generate(remaining)
              env.request_headers["content-type"] = "application/a2a+json"
            end
          end

          private

            # Extract {name=*} placeholder names from a path pattern.
            def path_param_names(pattern)
              pattern.scan(/\{(\w+)(?:=[^}]*)?\}/).flatten
            end

            # Substitute {name=*} placeholders with values from params.
            # Pattern names are snake_case (e.g. task_id) but Schema#to_h
            # produces camelCase keys (e.g. taskId), so we check both.
            def interpolate_path(pattern, params)
              pattern.gsub(/\{(\w+)(?:=[^}]*)?\}/) do
                name = $1
                camel = snake_to_camel(name)
                params[name] || params[name.to_sym] ||
                  params[camel] || params[camel.to_sym] || ""
              end
            end

            # Return params with path-interpolated keys removed.
            def remove_path_params(pattern, params)
              names = path_param_names(pattern)
              camel_names = names.map { |n| snake_to_camel(n) }
              all_names = (names + camel_names).to_a
              params.reject { |k, _| all_names.include?(k.to_s) }
            end

            # "task_id" => "taskId"
            def snake_to_camel(str)
              str.gsub(/_([a-z])/) { $1.upcase }
            end
        end
      end
    end
  end
end

::Faraday::Request.register_middleware(a2a_rest: A2A::Client::Middleware::REST::Request)

__END__
describe "A2A::Client::Middleware::REST::Request" do
  middleware = A2A::Client::Middleware::REST::Request

  it "rewrites POST operation with correct path, verb, and content-type" do
    operation = A2A::Protocol::Protobuf.operation("SendMessage")
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "message" => { "role" => "ROLE_USER" } }
    env.params = {}
    env.request_headers = {}
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_request(env)

    env.url.path.should == "/rest/message:send"
    env.method.should == :post
    JSON.parse(env.body).should == { "message" => { "role" => "ROLE_USER" } }
    env.request_headers["content-type"].should == "application/a2a+json"
  end

  it "rewrites GET operation with path interpolation and query params" do
    operation = A2A::Protocol::Protobuf.operation("GetTask")
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "id" => "task-123", "historyLength" => "5" }
    env.params = {}
    env.request_headers = {}
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_request(env)

    env.url.path.should == "/rest/tasks/task-123"
    env.method.should == :get
    env.body.should.be.nil
    env.params["historyLength"].should == "5"
  end

  it "rewrites DELETE operation with multi-param path interpolation" do
    operation = A2A::Protocol::Protobuf.operation("DeleteTaskPushNotificationConfig")
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "taskId" => "task-123", "id" => "config-1" }
    env.params = {}
    env.request_headers = {}
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_request(env)

    env.url.path.should == "/rest/tasks/task-123/pushNotificationConfigs/config-1"
    env.method.should == :delete
    env.body.should.be.nil
  end

  it "rewrites POST cancel with path interpolation" do
    operation = A2A::Protocol::Protobuf.operation("CancelTask")
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "id" => "task-123", "metadata" => { "key" => "val" } }
    env.params = {}
    env.request_headers = {}
    env.request = ::Faraday::RequestOptions.new
    env.request.context = { a2a_operation: operation }

    middleware.new(nil).on_request(env)

    env.url.path.should == "/rest/tasks/task-123:cancel"
    env.method.should == :post
    JSON.parse(env.body).should == { "metadata" => { "key" => "val" } }
  end

  it "passes through when no operation is set" do
    env = ::Faraday::Env.new
    env.url = URI.parse("http://localhost:9292/")
    env.body = { "foo" => "bar" }
    env.params = {}
    env.request_headers = {}
    env.request = ::Faraday::RequestOptions.new

    middleware.new(nil).on_request(env)

    env.body.should == { "foo" => "bar" }
  end
end
