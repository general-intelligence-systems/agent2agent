# frozen_string_literal: true

require "json"
require "console"

class WebhookReceiver
  def call(env)
    req = Rack::Request.new(env)

    case [req.request_method, req.path_info]
    when ["POST", "/webhook"]
      body = req.body.read
      payload = JSON.parse(body) rescue body

      token = env["HTTP_X_A2A_NOTIFICATION_TOKEN"]
      auth  = env["HTTP_AUTHORIZATION"]

      Console.info(self) { "Webhook received!" }
      Console.info(self) { "  Token: #{token}" } if token
      Console.info(self) { "  Auth:  #{auth}" } if auth
      Console.info(self) { "  Payload: #{JSON.pretty_generate(payload)}" }

      [200, { "content-type" => "application/json" }, ['{"status":"received"}']]

    when ["GET", "/health"]
      [200, { "content-type" => "text/plain" }, ["ok"]]

    when ["GET", "/"]
      [200, { "content-type" => "text/plain" }, ["Webhook Receiver - POST to /webhook"]]

    else
      [404, { "content-type" => "text/plain" }, ["not found"]]
    end
  end
end

Console.info(self) { "Webhook Receiver starting on :9293..." }
Console.info(self) { "POST webhooks to http://receiver:9293/webhook" }

run WebhookReceiver.new
