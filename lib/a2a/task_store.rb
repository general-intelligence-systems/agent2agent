# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "securerandom"
require "net/http"
require "uri"
require "json"

module A2A
  Task = Struct.new(
    :id, :context_id, :state, :result, :artifacts, :history,
    :push_configs, :subscribers, :created_at, :updated_at,
    keyword_init: true
  )

  # In-memory task registry with pub/sub for streaming and webhook delivery.
  # Swap for a DB-backed implementation in production --
  # if the server crashes, in-memory tasks vanish and the client never gets notified.
  class TaskStore
    TERMINAL_STATES = %w[
      TASK_STATE_COMPLETED TASK_STATE_FAILED
      TASK_STATE_CANCELED TASK_STATE_REJECTED
    ].freeze

    def initialize
      @tasks = {}
      @mutex = Mutex.new
    end

    # ── Task CRUD ──────────────────────────────────────────────────────

    def create(id, context_id, push_config = nil)
      @mutex.synchronize do
        now = Time.now.utc
        configs = {}
        if push_config
          cfg_id = push_config["id"] || SecureRandom.uuid
          push_config["id"] = cfg_id
          configs[cfg_id] = push_config
        end

        @tasks[id] = Task.new(
          id:           id,
          context_id:   context_id,
          state:        "TASK_STATE_SUBMITTED",
          result:       nil,
          artifacts:    [],
          history:      [],
          push_configs: configs,
          subscribers:  [],
          created_at:   now,
          updated_at:   now,
        )
      end
    end

    def get(id)
      @mutex.synchronize { @tasks[id] }
    end

    def update_state(id, state, message: nil)
      task = nil
      @mutex.synchronize do
        task = @tasks[id]
        return nil unless task
        task.state = state
        task.updated_at = Time.now.utc
      end
      if task
        event = build_status_event(task, message)
        notify_subscribers(task, event)
        deliver_webhooks(task, { "statusUpdate" => event })
      end
      task
    end

    def complete(id, result)
      task = nil
      @mutex.synchronize do
        task = @tasks[id]
        return nil unless task
        task.state  = "TASK_STATE_COMPLETED"
        task.result = result
        task.updated_at = Time.now.utc
      end
      if task
        event = build_status_event(task)
        notify_subscribers(task, event)
        deliver_webhooks(task, { "statusUpdate" => event })
        close_subscribers(task)
      end
      task
    end

    def fail(id, msg)
      task = nil
      @mutex.synchronize do
        task = @tasks[id]
        return nil unless task
        task.state  = "TASK_STATE_FAILED"
        task.result = msg
        task.updated_at = Time.now.utc
      end
      if task
        event = build_status_event(task)
        notify_subscribers(task, event)
        deliver_webhooks(task, { "statusUpdate" => event })
        close_subscribers(task)
      end
      task
    end

    def cancel(id)
      update_state(id, "TASK_STATE_CANCELED")
      task = get(id)
      close_subscribers(task) if task
      task
    end

    def terminal?(id)
      task = get(id)
      task && TERMINAL_STATES.include?(task.state)
    end

    # ── Artifacts ──────────────────────────────────────────────────────

    def add_artifact(id, artifact)
      task = nil
      @mutex.synchronize do
        task = @tasks[id]
        return nil unless task
        task.artifacts << artifact
        task.updated_at = Time.now.utc
      end
      if task
        event = {
          "taskId"    => task.id,
          "contextId" => task.context_id,
          "artifact"  => artifact,
          "append"    => false,
          "lastChunk" => true,
        }
        notify_subscribers(task, event, type: :artifact)
        deliver_webhooks(task, { "artifactUpdate" => event })
      end
      task
    end

    # ── History ────────────────────────────────────────────────────────

    def add_message(id, msg)
      @mutex.synchronize do
        task = @tasks[id]
        return nil unless task
        task.history << msg
        task.updated_at = Time.now.utc
        task
      end
    end

    # ── Listing ────────────────────────────────────────────────────────

    def list(context_id: nil, state: nil)
      @mutex.synchronize do
        @tasks.values
              .select { |t| context_id.nil? || t.context_id == context_id }
              .select { |t| state.nil?      || t.state == state }
              .sort_by { |t| t.updated_at }
              .reverse
      end
    end

    # ── Push Notification Config CRUD ──────────────────────────────────

    def create_push_config(task_id, config)
      @mutex.synchronize do
        task = @tasks[task_id]
        return nil unless task
        cfg_id = config["id"] || SecureRandom.uuid
        config["id"] = cfg_id
        config["taskId"] = task_id
        task.push_configs[cfg_id] = config
        task.updated_at = Time.now.utc
        config
      end
    end

    def get_push_config(task_id, config_id)
      @mutex.synchronize do
        task = @tasks[task_id]
        return nil unless task
        task.push_configs[config_id]
      end
    end

    def list_push_configs(task_id)
      @mutex.synchronize do
        task = @tasks[task_id]
        return [] unless task
        task.push_configs.values
      end
    end

    def delete_push_config(task_id, config_id)
      @mutex.synchronize do
        task = @tasks[task_id]
        return nil unless task
        task.push_configs.delete(config_id)
        task.updated_at = Time.now.utc
      end
    end

    # ── Streaming / Pub-Sub ────────────────────────────────────────────

    # Subscribe to task updates. Returns a Queue that will receive events.
    # Each event is a Hash: { type: :status|:artifact, data: Hash }
    # A nil sentinel signals stream end.
    def subscribe(task_id)
      queue = Thread::Queue.new
      @mutex.synchronize do
        task = @tasks[task_id]
        return nil unless task
        task.subscribers << queue
      end
      queue
    end

    def unsubscribe(task_id, queue)
      @mutex.synchronize do
        task = @tasks[task_id]
        return unless task
        task.subscribers.delete(queue)
      end
    end

    private

      def build_status_event(task, message = nil)
        event = {
          "taskId"    => task.id,
          "contextId" => task.context_id,
          "status"    => {
            "state"     => task.state,
            "timestamp" => task.updated_at.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
          },
        }
        event["status"]["message"] = message if message
        event
      end

      def notify_subscribers(task, event, type: :status)
        subs = @mutex.synchronize { task.subscribers.dup }
        subs.each do |queue|
          queue << { type: type, data: event }
        rescue ClosedQueueError
          # subscriber disconnected
        end
      end

      def close_subscribers(task)
        subs = @mutex.synchronize { task.subscribers.dup }
        subs.each do |queue|
          queue << nil # sentinel
          queue.close
        rescue ClosedQueueError
          # already closed
        end
        @mutex.synchronize { task.subscribers.clear }
      end

      def deliver_webhooks(task, payload)
        configs = @mutex.synchronize { task.push_configs.values.dup }
        return if configs.empty?

        configs.each do |config|
          Thread.new do
            deliver_single_webhook(config, payload)
          rescue => e
            # Log but don't fail
            $stderr.puts "[A2A::TaskStore] Webhook delivery failed for #{config["url"]}: #{e.message}"
          end
        end
      end

      def deliver_single_webhook(config, payload)
        url = config["url"]
        return unless url && !url.empty?

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/a2a+json"

        # Authentication
        if (auth = config["authentication"])
          scheme = auth["scheme"] || "Bearer"
          creds  = auth["credentials"] || ""
          request["Authorization"] = "#{scheme} #{creds}"
        end

        # Token header
        if (token = config["token"])
          request["X-A2A-Notification-Token"] = token
        end

        request.body = JSON.generate(payload)
        http.request(request)
      end
  end
end
