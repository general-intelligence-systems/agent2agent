#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.4. Version Negotiation Error
# Scenario: Client requests an unsupported protocol version.
#
# Request:
#
# POST /message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
# A2A-Version: 0.5
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [{"text": "Hello"}],
#     "messageId": "msg-uuid"
#   }
# }
#
# Response:
#
# HTTP/1.1 400 Bad Request
# Content-Type: application/problem+json
#
# {
#   "type": "https://a2a-protocol.org/errors/version-not-supported",
#   "title": "Protocol Version Not Supported",
#   "status": 400,
#   "detail": "The requested A2A protocol version 0.5 is not supported by this agent",
#   "supportedVersions": ["0.3"]
# }
