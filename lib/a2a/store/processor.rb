# frozen_string_literal: true

require "async"
require "console"

module A2A
  module Store
    # Async background task processor, modeled after async-job's Inline processor.
    #
    # The gospel (async-job) teaches:
    #   - Async::Idler schedules tasks when the event loop is idle (backpressure)
    #   - Each job runs in its own fiber (not thread)
    #   - The returned Async::Task can be .wait'd for completion notification
    #   - Errors are caught and logged, not re-raised
    #   - task.defer_stop protects critical sections from interruption
    #
    # This processor enables A2A's non-blocking mode (return_immediately: true).
    # The handler can enqueue work that executes after the HTTP response is sent.
    #
    # Usage:
    #
    #   processor = A2A::Store::Processor.new
    #
    #   # Fire and forget:
    #   processor.call { store.update_state(task_id, "WORKING"); do_work; store.complete(task_id, result) }
    #
    #   # Wait for completion:
    #   task = processor.call { do_work }
    #   task.wait
    #
    class Processor
      attr_reader :call_count, :complete_count, :failed_count

      def initialize(parent: nil)
        @parent         = parent
        @call_count     = 0
        @complete_count = 0
        @failed_count   = 0
      end

      # Execute a block asynchronously in a background fiber.
      #
      # Returns the Async::Task so callers can optionally .wait on it.
      #
      # @yield the work to perform
      # @return [Async::Task]
      #
      def call(&block)
        @call_count += 1

        parent.async do |task|
          task.defer_stop do
            yield
          end
          @complete_count += 1
        rescue => error
          @failed_count += 1
          Console.error(self) { "Background task failed: #{error.message}" }
        ensure
          @call_count -= 1
        end
      end

      def start
        # Ensure we have an async context available
      end

      def stop
        # Allow in-flight tasks to drain naturally
      end

      def status
        {
          in_flight: @call_count,
          completed: @complete_count,
          failed:    @failed_count,
        }
      end

      private

        def parent
          @parent || Async::Task.current
        end
    end
  end
end

test do
  require "async"

  describe "A2A::Store::Processor" do
    it "executes blocks asynchronously" do
      executed = false

      Sync do
        processor = A2A::Store::Processor.new
        task = processor.call { executed = true }
        task.wait
      end

      executed.should == true
    end

    it "tracks call counts" do
      Sync do
        processor = A2A::Store::Processor.new
        task = processor.call { "work" }
        task.wait

        processor.complete_count.should == 1
        processor.call_count.should == 0  # decremented after completion
      end
    end

    it "handles errors gracefully" do
      Sync do
        processor = A2A::Store::Processor.new
        task = processor.call { raise "boom" }
        task.wait rescue nil  # task may re-raise

        processor.failed_count.should == 1
      end
    end

    it "returns status" do
      Sync do
        processor = A2A::Store::Processor.new
        status = processor.status
        status[:in_flight].should == 0
        status[:completed].should == 0
        status[:failed].should == 0
      end
    end
  end
end
