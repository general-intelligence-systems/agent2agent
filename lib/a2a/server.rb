# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "rack"
require "json"
require "securerandom"
require "net/http"
require "uri"

module A2A
  # Rack app that exposes a Brute::Agent over the A2A JSON-RPC binding.
  #
  # Responsibilities (server-side, NOT agent-side):
  #   - Receive inbound JSON-RPC at POST /a2a
  #   - For message/send: spawn the agent in a background thread,
  #     return a Task object immediately, post the result to the
  #     client's webhook when the agent returns.
  #   - For tasks/get, tasks/cancel, etc: serve from the task store.
  #   - Serve the Agent Card at /.well-known/agent-card.json
  #
  class Server
    def initialize(agent:, agent_card:, store: TaskStore.new)
      @agent      = agent
      @agent_card = agent_card
      @store      = store
    end

    def call(rack_env)
      req = Rack::Request.new(rack_env)

      case [req.request_method, req.path_info]
      when ["GET",  "/.well-known/agent-card.json"] then agent_card_response
      when ["POST", "/a2a"]                         then dispatch(JSON.parse(req.body.read))
      else [404, { "content-type" => "application/json" }, [%({"error":"not found"})]]
      end
    end

    private

      def agent_card_response
        [200, { "content-type" => "application/json" }, [JSON.generate(@agent_card)]]
      end

      # Route JSON-RPC method to a handler. Each handler returns the
      # `result` field; we wrap it in the JSON-RPC envelope here.
      def dispatch(rpc)
        result = case rpc["method"]
                 when "message/send"                       then handle_send(rpc["params"])
                 when "tasks/get"                          then handle_get(rpc["params"])
                 when "tasks/list"                         then handle_list(rpc["params"])
                 when "tasks/cancel"                       then handle_cancel(rpc["params"])
                 when "tasks/pushNotificationConfig/set"   then handle_push_set(rpc["params"])
                 when "tasks/pushNotificationConfig/get"   then handle_push_get(rpc["params"])
                 when "tasks/pushNotificationConfig/list"  then handle_push_list(rpc["params"])
                 when "tasks/pushNotificationConfig/delete" then handle_push_delete(rpc["params"])
                 else return rpc_error(rpc["id"], -32601, "method not found")
                 end

        rpc_ok(rpc["id"], result)
      end

      # --- handlers ----------------------------------------------------

      def handle_send(params)
        task_id    = "task-#{SecureRandom.hex(8)}"
        context_id = params.dig("message", "contextId") || "ctx-#{SecureRandom.hex(8)}"
        push_cfg   = params.dig("configuration", "pushNotificationConfig")
        text       = params.dig("message", "parts").map { |p| p["text"] }.compact.join("\n")

        task = @store.create(task_id, context_id, push_cfg)

        Thread.new { run_agent(task, text) }

        { id: task_id, contextId: context_id, status: { state: "submitted" }, kind: "task" }
      end

      def handle_get(params)
        @store.get(params["id"]) || (raise "task not found")
      end

      def handle_list(params)
        @store.list(context_id: params["contextId"], state: params["state"])
      end

      def handle_cancel(params)
        @store.cancel(params["id"])
        @store.get(params["id"])
      end

      def handle_push_set(params)
        @store.set_push_config(params["taskId"], params["pushNotificationConfig"])
        { taskId: params["taskId"], pushNotificationConfig: params["pushNotificationConfig"] }
      end

      def handle_push_get(params)    = @store.get_push_config(params["taskId"], params["pushNotificationConfigId"])
      def handle_push_list(params)   = @store.list_push_configs(params["taskId"])
      def handle_push_delete(params) = @store.delete_push_config(params["taskId"], params["pushNotificationConfigId"])

      # --- the actual agent run ----------------------------------------

      def run_agent(task, text)
        session = Brute::Session.new
        session.user(text)
        @store.update_state(task.id, "working")

        @agent.call(session)

        last = session.reverse_each.find { |m| m.role == :assistant && m.content.to_s != "" }
        @store.complete(task.id, last&.content)
        notify(task, "completed")
      rescue => e
        @store.fail(task.id, e.message)
        notify(task, "failed")
      end

      def notify(task, state)
        cfg = task.push_config
        return unless cfg && cfg["url"]

        uri = URI.parse(cfg["url"])
        req = Net::HTTP::Post.new(uri, "content-type" => "application/json")
        if (auth = cfg["authentication"])
          req["authorization"] = "#{auth["schemes"].first} #{auth["credentials"]}"
        end
        req["x-a2a-notification-token"] = cfg["token"] if cfg["token"]
        req.body = JSON.generate(
          taskId:    task.id,
          contextId: task.context_id,
          status:    { state: state, timestamp: Time.now.utc.iso8601 },
        )
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |h| h.request(req) }
      rescue => e
        warn "[a2a] push notification to #{cfg["url"]} failed: #{e.message}"
      end

      # --- JSON-RPC envelope helpers -----------------------------------

      def rpc_ok(id, result)
        [200, { "content-type" => "application/json" },
         [JSON.generate(jsonrpc: "2.0", id: id, result: result)]]
      end

      def rpc_error(id, code, message)
        [200, { "content-type" => "application/json" },
         [JSON.generate(jsonrpc: "2.0", id: id, error: { code: code, message: message })]]
      end
  end
end
