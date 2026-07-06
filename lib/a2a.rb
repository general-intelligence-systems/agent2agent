# frozen_string_literal: true

require "bundler/setup"
require "json"
require "json_schemer"
require "async"
require "async/http/internet"
require "uri"
require "rack"

module A2A
end

require "a2a/errors"
require "a2a/protocol"
require "a2a/server/sse"
require "a2a/agent"

require "a2a/server"

require "a2a/client/middleware/schema_request"
require "a2a/client/middleware/json_rpc/request"
require "a2a/client/middleware/json_rpc/response"
require "a2a/client/middleware/rest/request"
require "a2a/client/middleware/rest/response"
require "a2a/client"
