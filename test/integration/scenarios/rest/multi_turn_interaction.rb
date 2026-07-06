#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.3. Multi-Turn Interaction
# Scenario: Agent requires additional input to complete a task.
#
# Initial Request:
#
# POST /rest/message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [{"text": "Book me a flight"}],
#     "messageId": "msg-1"
#   }
# }
#
# Response (Input Required):
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "task": {
#     "id": "task-uuid",
#     "status": {
#       "state": "TASK_STATE_INPUT_REQUIRED",
#       "message": {
#         "role": "ROLE_AGENT",
#         "parts": [{"text": "I need more details. Where would you like to fly from and to?"}]
#       }
#     }
#   }
# }
#
# Follow-up Request:
#
# POST /rest/message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "taskId": "task-uuid",
#     "role": "ROLE_USER",
#     "parts": [{"text": "From San Francisco to New York"}],
#     "messageId": "msg-2"
#   }
# }
