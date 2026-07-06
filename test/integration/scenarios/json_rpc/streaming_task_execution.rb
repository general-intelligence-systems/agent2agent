#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.2. Streaming Task Execution
# Scenario: Client requests a long-running task with real-time updates.
#
# Request:
#
# POST /rest/message:stream HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [{"text": "Write a detailed report on climate change"}],
#     "messageId": "msg-uuid"
#   }
# }
#
# SSE Response Stream:
#
# HTTP/1.1 200 OK
# Content-Type: text/event-stream
#
# data: {"task": {"id": "task-uuid", "status": {"state": "TASK_STATE_WORKING"}}}
#
# data: {"artifactUpdate": {"taskId": "task-uuid", "artifact": {"parts": [{"text": "# Climate Change Report\n\n"}]}}}
#
# data: {"statusUpdate": {"taskId": "task-uuid", "status": {"state": "TASK_STATE_COMPLETED"}}}
