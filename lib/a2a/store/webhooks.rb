# frozen_string_literal: true

require "async"
require "async/http/internet"
require "json"
require "console"

module A2A
  module Store
    # Async webhook delivery for A2A push notifications.
    #
    # Following the gospel (async-http):
    #   - Uses Async::HTTP::Internet for non-blocking HTTP requests
    #   - Each delivery runs in its own Async task (fiber, not thread)
    #   - Failures are logged but do not propagate
    #
    # The A2A spec says:
    #   - Push notification payloads use StreamResponse format
    #   - Content-Type: application/a2a+json
    #   - Authentication via scheme + credentials from the config
    #   - Token header: X-A2A-Notification-Token
    #   - Delivery is at-least-once with possible retries
    #
    class Webhooks
      def initialize
        @internet = nil
      end

      # Deliver a payload to all push notification configs for a task.
      #
      # @param configs [Array<Hash>] push notification configs
      # @param payload [Hash] the StreamResponse payload
      #
      def deliver(configs, payload)
        return if configs.nil? || configs.empty?

        configs.each do |config|
          Async do
            deliver_single(config, payload)
          rescue => e
            Console.error(self) { "Webhook delivery failed for #{config["url"]}: #{e.message}" }
          end
        end
      end

      private

        def internet
          @internet ||= Async::HTTP::Internet.new
        end

        def deliver_single(config, payload)
          url = config["url"]
          return unless url && !url.empty?

          headers = {
            "content-type" => "application/a2a+json",
          }

          # Authentication
          if (auth = config["authentication"])
            scheme = auth["scheme"] || "Bearer"
            creds  = auth["credentials"] || ""
            headers["authorization"] = "#{scheme} #{creds}"
          end

          # Token header
          if (token = config["token"])
            headers["x-a2a-notification-token"] = token
          end

          body = JSON.generate(payload)

          internet.post(url, headers, [body])
        end
    end
  end
end

test do
  describe "A2A::Store::Webhooks" do
    it "can be instantiated" do
      wh = A2A::Store::Webhooks.new
      wh.should.not.be.nil
    end

    it "silently skips empty config lists" do
      wh = A2A::Store::Webhooks.new
      # Should not raise — returns nil for empty/nil configs
      wh.deliver([], { "statusUpdate" => {} }).should.be.nil
      wh.deliver(nil, { "statusUpdate" => {} }).should.be.nil
    end
  end
end
