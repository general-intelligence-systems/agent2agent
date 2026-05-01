# frozen_string_literal: true

require "async"
require "async/queue"

module A2A
  module Store
    # Fiber-safe pub/sub for task update streaming.
    #
    # Following the gospel (async-job / protocol-http):
    #   - Async::Queue is fiber-safe (no locks needed)
    #   - enqueue/dequeue yield the fiber cooperatively
    #   - nil sentinel signals end of stream
    #
    # Each subscriber gets an Async::Queue. State mutations push events
    # to all subscribers for the affected task. Terminal states close
    # all subscribers for that task.
    #
    # Usage:
    #
    #   pub_sub = A2A::Store::PubSub.new
    #
    #   # Subscribe (returns an Async::Queue)
    #   queue = pub_sub.subscribe("task-123")
    #
    #   # In another fiber, consume events:
    #   Async do
    #     while event = queue.dequeue
    #       process(event)
    #     end
    #   end
    #
    #   # Publish an event to all subscribers:
    #   pub_sub.notify("task-123", { type: :status, data: { ... } })
    #
    #   # Close all subscribers for a task (terminal state):
    #   pub_sub.close("task-123")
    #
    class PubSub
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
      end

      # Subscribe to updates for a task.
      # Returns an Async::Queue that will receive events.
      # A nil sentinel signals end of stream.
      def subscribe(task_id)
        queue = Async::Queue.new
        @subscribers[task_id] << queue
        queue
      end

      # Remove a specific subscriber queue.
      def unsubscribe(task_id, queue)
        @subscribers[task_id].delete(queue)
        @subscribers.delete(task_id) if @subscribers[task_id].empty?
      end

      # Push an event to all subscribers for a task.
      #
      # @param task_id [String]
      # @param event [Hash] e.g. { type: :status, data: { ... } }
      #
      def notify(task_id, event)
        @subscribers[task_id].each do |queue|
          queue.enqueue(event)
        end
      end

      # Close all subscribers for a task.
      # Sends nil sentinel and removes all subscriptions.
      def close(task_id)
        @subscribers[task_id].each do |queue|
          queue.enqueue(nil) # sentinel: end of stream
        end
        @subscribers.delete(task_id)
      end

      # Number of active subscribers for a task.
      def subscriber_count(task_id)
        @subscribers[task_id].size
      end

      # Total number of tasks with active subscribers.
      def task_count
        @subscribers.size
      end
    end
  end
end

test do
  require "async"

  describe "A2A::Store::PubSub" do
    it "subscribe returns an Async::Queue" do
      ps = A2A::Store::PubSub.new
      q = ps.subscribe("t1")
      q.is_a?(Async::Queue).should == true
    end

    it "notify pushes events to all subscribers" do
      ps = A2A::Store::PubSub.new
      q1 = ps.subscribe("t1")
      q2 = ps.subscribe("t1")

      ps.notify("t1", { type: :status, data: "hello" })

      Sync do
        q1.dequeue.should == { type: :status, data: "hello" }
        q2.dequeue.should == { type: :status, data: "hello" }
      end
    end

    it "close sends nil sentinel and removes subscriptions" do
      ps = A2A::Store::PubSub.new
      q = ps.subscribe("t1")

      ps.close("t1")

      Sync do
        q.dequeue.should.be.nil
      end
      ps.subscriber_count("t1").should == 0
    end

    it "unsubscribe removes a single subscriber" do
      ps = A2A::Store::PubSub.new
      q1 = ps.subscribe("t1")
      q2 = ps.subscribe("t1")

      ps.unsubscribe("t1", q1)
      ps.subscriber_count("t1").should == 1

      ps.notify("t1", { data: "only q2" })

      Sync do
        q2.dequeue[:data].should == "only q2"
      end
    end

    it "does not leak when all subscribers unsubscribed" do
      ps = A2A::Store::PubSub.new
      q = ps.subscribe("t1")
      ps.unsubscribe("t1", q)
      ps.task_count.should == 0
    end
  end
end
