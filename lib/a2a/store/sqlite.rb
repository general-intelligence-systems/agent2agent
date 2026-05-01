# frozen_string_literal: true

require "sqlite3"
require "json"
require "securerandom"
require "console"

require_relative "pub_sub"
require_relative "webhooks"

module A2A
  module Store
    # SQLite-backed task store with async pub/sub and webhook delivery.
    #
    # This is the enlightened replacement for the in-memory TaskStore.
    # Follows the gospel:
    #   - async-job's schema patterns (indexed by state, updated_at DESC)
    #   - async-job's duck-typed delegate protocol (#call, #start, #stop)
    #   - Async::Queue-based pub/sub (fiber-safe, no threads)
    #   - Async::HTTP::Internet for webhook delivery (no Net::HTTP)
    #
    # The store composes three concerns:
    #   1. SQLite — persistent CRUD for tasks, push configs
    #   2. PubSub — in-process streaming subscriptions
    #   3. Webhooks — push notification delivery
    #
    # SQLite is safe for fiber-based concurrency within a single process
    # because Ruby fibers are cooperatively scheduled — only one fiber
    # runs at a time, so no concurrent writes can collide.
    #
    class SQLite
      TERMINAL_STATES = %w[
        TASK_STATE_COMPLETED TASK_STATE_FAILED
        TASK_STATE_CANCELED TASK_STATE_REJECTED
      ].freeze

      attr_reader :pub_sub, :webhooks

      # @param path [String] path to SQLite database file (":memory:" for in-memory)
      #
      def initialize(path: ":memory:")
        @db = ::SQLite3::Database.new(path)
        @db.results_as_hash = true
        @db.execute("PRAGMA journal_mode = WAL")
        @db.execute("PRAGMA synchronous = NORMAL")
        @db.execute("PRAGMA foreign_keys = ON")

        @pub_sub  = PubSub.new
        @webhooks = Webhooks.new

        create_tables
      end

      # ── Task CRUD ──────────────────────────────────────────────────────

      def create(id, context_id, push_config = nil)
        now = now_ts

        @db.execute(<<~SQL, [id, context_id, "TASK_STATE_SUBMITTED", "[]", "[]", now, now])
          INSERT INTO tasks (id, context_id, state, artifacts, history, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        SQL

        if push_config
          cfg_id = push_config["id"] || SecureRandom.uuid
          push_config = push_config.merge("id" => cfg_id, "taskId" => id)
          insert_push_config(id, push_config)
        end

        get(id)
      end

      def get(id)
        row = @db.get_first_row("SELECT * FROM tasks WHERE id = ?", [id])
        return nil unless row
        row_to_task(row)
      end

      def update_state(id, state, message: nil)
        now = now_ts
        @db.execute("UPDATE tasks SET state = ?, updated_at = ? WHERE id = ?", [state, now, id])

        task = get(id)
        return nil unless task

        event = build_status_event(task, message)
        @pub_sub.notify(id, { type: :status, data: event })
        @webhooks.deliver(list_push_configs(id), { "statusUpdate" => event })

        if TERMINAL_STATES.include?(state)
          @pub_sub.close(id)
        end

        task
      end

      def complete(id, result)
        now = now_ts
        result_json = result ? JSON.generate(result) : nil
        @db.execute(
          "UPDATE tasks SET state = ?, result = ?, updated_at = ? WHERE id = ?",
          ["TASK_STATE_COMPLETED", result_json, now, id]
        )

        task = get(id)
        return nil unless task

        event = build_status_event(task)
        @pub_sub.notify(id, { type: :status, data: event })
        @webhooks.deliver(list_push_configs(id), { "statusUpdate" => event })
        @pub_sub.close(id)

        task
      end

      def fail(id, msg)
        now = now_ts
        result_json = msg ? JSON.generate(msg) : nil
        @db.execute(
          "UPDATE tasks SET state = ?, result = ?, updated_at = ? WHERE id = ?",
          ["TASK_STATE_FAILED", result_json, now, id]
        )

        task = get(id)
        return nil unless task

        event = build_status_event(task)
        @pub_sub.notify(id, { type: :status, data: event })
        @webhooks.deliver(list_push_configs(id), { "statusUpdate" => event })
        @pub_sub.close(id)

        task
      end

      def cancel(id)
        update_state(id, "TASK_STATE_CANCELED")
      end

      def terminal?(id)
        task = get(id)
        task && TERMINAL_STATES.include?(task[:state])
      end

      # ── Artifacts ──────────────────────────────────────────────────────

      def add_artifact(id, artifact)
        task = get(id)
        return nil unless task

        artifacts = task[:artifacts]
        artifacts << artifact
        now = now_ts

        @db.execute(
          "UPDATE tasks SET artifacts = ?, updated_at = ? WHERE id = ?",
          [JSON.generate(artifacts), now, id]
        )

        event = {
          "taskId"    => id,
          "contextId" => task[:context_id],
          "artifact"  => artifact,
          "append"    => false,
          "lastChunk" => true,
        }
        @pub_sub.notify(id, { type: :artifact, data: event })
        @webhooks.deliver(list_push_configs(id), { "artifactUpdate" => event })

        get(id)
      end

      # ── History ────────────────────────────────────────────────────────

      def add_message(id, msg)
        task = get(id)
        return nil unless task

        history = task[:history]
        history << msg

        @db.execute(
          "UPDATE tasks SET history = ?, updated_at = ? WHERE id = ?",
          [JSON.generate(history), now_ts, id]
        )

        get(id)
      end

      # ── Listing ────────────────────────────────────────────────────────

      def list(context_id: nil, state: nil)
        conditions = []
        params = []

        if context_id
          conditions << "context_id = ?"
          params << context_id
        end

        if state
          conditions << "state = ?"
          params << state
        end

        where = conditions.empty? ? "" : "WHERE #{conditions.join(" AND ")}"
        sql = "SELECT * FROM tasks #{where} ORDER BY updated_at DESC"

        @db.execute(sql, params).map { |row| row_to_task(row) }
      end

      # ── Push Notification Config CRUD ──────────────────────────────────

      def create_push_config(task_id, config)
        task = get(task_id)
        return nil unless task

        cfg_id = config["id"] || SecureRandom.uuid
        config = config.merge("id" => cfg_id, "taskId" => task_id)
        insert_push_config(task_id, config)
        config
      end

      def get_push_config(task_id, config_id)
        row = @db.get_first_row(
          "SELECT * FROM push_configs WHERE task_id = ? AND id = ?",
          [task_id, config_id]
        )
        return nil unless row
        row_to_push_config(row)
      end

      def list_push_configs(task_id)
        @db.execute(
          "SELECT * FROM push_configs WHERE task_id = ? ORDER BY created_at",
          [task_id]
        ).map { |row| row_to_push_config(row) }
      end

      def delete_push_config(task_id, config_id)
        @db.execute(
          "DELETE FROM push_configs WHERE task_id = ? AND id = ?",
          [task_id, config_id]
        )
      end

      # ── Streaming / Pub-Sub ────────────────────────────────────────────

      def subscribe(task_id)
        task = get(task_id)
        return nil unless task
        @pub_sub.subscribe(task_id)
      end

      def unsubscribe(task_id, queue)
        @pub_sub.unsubscribe(task_id, queue)
      end

      # ── Lifecycle (async-job duck-type) ────────────────────────────────

      def start
        # No-op for now. Could start background cleanup tasks.
      end

      def stop
        @db.close if @db
      end

      private

        def create_tables
          @db.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS tasks (
              id TEXT PRIMARY KEY,
              context_id TEXT NOT NULL,
              state TEXT NOT NULL DEFAULT 'TASK_STATE_SUBMITTED',
              result TEXT,
              artifacts TEXT NOT NULL DEFAULT '[]',
              history TEXT NOT NULL DEFAULT '[]',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_tasks_context
              ON tasks(context_id);
            CREATE INDEX IF NOT EXISTS idx_tasks_state
              ON tasks(state);
            CREATE INDEX IF NOT EXISTS idx_tasks_updated
              ON tasks(updated_at DESC);

            CREATE TABLE IF NOT EXISTS push_configs (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
              url TEXT NOT NULL,
              token TEXT,
              auth_scheme TEXT,
              auth_credentials TEXT,
              created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_push_configs_task
              ON push_configs(task_id);
          SQL
        end

        def now_ts
          Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
        end

        def row_to_task(row)
          {
            id:           row["id"],
            context_id:   row["context_id"],
            state:        row["state"],
            result:       row["result"] ? JSON.parse(row["result"]) : nil,
            artifacts:    JSON.parse(row["artifacts"] || "[]"),
            history:      JSON.parse(row["history"] || "[]"),
            created_at:   row["created_at"],
            updated_at:   row["updated_at"],
          }
        end

        def row_to_push_config(row)
          config = {
            "id"     => row["id"],
            "taskId" => row["task_id"],
            "url"    => row["url"],
          }
          config["token"] = row["token"] if row["token"]
          if row["auth_scheme"]
            config["authentication"] = {
              "scheme"      => row["auth_scheme"],
              "credentials" => row["auth_credentials"],
            }
          end
          config
        end

        def insert_push_config(task_id, config)
          auth = config["authentication"] || {}
          params = [
            config["id"], task_id, config["url"],
            config["token"],
            auth["scheme"], auth["credentials"],
            now_ts
          ]
          @db.execute(<<~SQL, params)
            INSERT INTO push_configs (id, task_id, url, token, auth_scheme, auth_credentials, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          SQL
        end

        def build_status_event(task, message = nil)
          event = {
            "taskId"    => task[:id],
            "contextId" => task[:context_id],
            "status"    => {
              "state"     => task[:state],
              "timestamp" => task[:updated_at],
            },
          }
          event["status"]["message"] = message if message
          event
        end
    end
  end
end

test do
  describe "A2A::Store::SQLite" do
    it "creates and retrieves tasks" do
      store = A2A::Store::SQLite.new
      task = store.create("t1", "ctx1")

      task[:id].should == "t1"
      task[:context_id].should == "ctx1"
      task[:state].should == "TASK_STATE_SUBMITTED"
      task[:artifacts].should == []
      task[:history].should == []

      fetched = store.get("t1")
      fetched[:id].should == "t1"
    end

    it "returns nil for missing tasks" do
      store = A2A::Store::SQLite.new
      store.get("nonexistent").should.be.nil
    end

    it "updates task state" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      store.update_state("t1", "TASK_STATE_WORKING")
      task = store.get("t1")
      task[:state].should == "TASK_STATE_WORKING"
    end

    it "completes tasks" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      store.complete("t1", { "answer" => 42 })
      task = store.get("t1")
      task[:state].should == "TASK_STATE_COMPLETED"
      task[:result].should == { "answer" => 42 }
    end

    it "fails tasks" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      store.fail("t1", "something broke")
      task = store.get("t1")
      task[:state].should == "TASK_STATE_FAILED"
    end

    it "cancels tasks" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      store.cancel("t1")
      task = store.get("t1")
      task[:state].should == "TASK_STATE_CANCELED"
    end

    it "detects terminal states" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      store.terminal?("t1").should == false
      store.complete("t1", nil)
      store.terminal?("t1").should == true
    end

    it "adds artifacts" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      artifact = { "artifactId" => "a1", "parts" => [{ "text" => "hello" }] }
      store.add_artifact("t1", artifact)

      task = store.get("t1")
      task[:artifacts].length.should == 1
      task[:artifacts].first["artifactId"].should == "a1"
    end

    it "adds messages to history" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      msg = { "messageId" => "m1", "role" => "ROLE_USER", "parts" => [{ "text" => "hi" }] }
      store.add_message("t1", msg)

      task = store.get("t1")
      task[:history].length.should == 1
      task[:history].first["messageId"].should == "m1"
    end

    it "lists tasks with filtering" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")
      store.create("t2", "ctx1")
      store.create("t3", "ctx2")
      store.complete("t2", nil)

      # All tasks
      store.list.length.should == 3

      # By context
      store.list(context_id: "ctx1").length.should == 2

      # By state
      store.list(state: "TASK_STATE_COMPLETED").length.should == 1
      store.list(state: "TASK_STATE_COMPLETED").first[:id].should == "t2"

      # Both filters
      store.list(context_id: "ctx1", state: "TASK_STATE_SUBMITTED").length.should == 1
    end

    it "manages push notification configs" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      config = store.create_push_config("t1", {
        "url"   => "https://example.com/hook",
        "token" => "secret",
        "authentication" => { "scheme" => "Bearer", "credentials" => "abc123" },
      })

      config["url"].should == "https://example.com/hook"
      config["token"].should == "secret"
      config["id"].should.not.be.nil

      # Get
      fetched = store.get_push_config("t1", config["id"])
      fetched["url"].should == "https://example.com/hook"
      fetched["authentication"]["scheme"].should == "Bearer"

      # List
      store.list_push_configs("t1").length.should == 1

      # Delete
      store.delete_push_config("t1", config["id"])
      store.list_push_configs("t1").length.should == 0
    end

    it "creates tasks with inline push config" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1", {
        "url"   => "https://example.com/hook",
        "token" => "tok",
      })

      configs = store.list_push_configs("t1")
      configs.length.should == 1
      configs.first["url"].should == "https://example.com/hook"
    end

    it "provides pub/sub subscriptions" do
      store = A2A::Store::SQLite.new
      store.create("t1", "ctx1")

      queue = store.subscribe("t1")
      queue.should.not.be.nil
      queue.is_a?(Async::Queue).should == true
    end

    it "returns nil subscribing to nonexistent task" do
      store = A2A::Store::SQLite.new
      store.subscribe("nonexistent").should.be.nil
    end
  end
end
