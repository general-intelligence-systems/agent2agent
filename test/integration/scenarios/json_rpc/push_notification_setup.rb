#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.6. Push Notification Setup and Usage
# Scenario: Client requests a long-running report generation and wants to be notified via webhook when it's done.
#
# Initial Request with Push Notification Config:
#
# POST /message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [
#       {
#         "text": "Generate the Q1 sales report. This usually takes a while. Notify me when it's ready."
#       }
#     ],
#     "messageId": "6dbc13b5-bd57-4c2b-b503-24e381b6c8d6"
#   },
#   "configuration": {
#     "pushNotificationConfig": {
#       "url": "https://client.example.com/webhook/a2a-notifications",
#       "token": "secure-client-token-for-task-aaa",
#       "authentication": {
#         "schemes": ["Bearer"]
#       }
#     }
#   }
# }
#
# Response (Task Submitted):
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "task": {
#     "id": "43667960-d455-4453-b0cf-1bae4955270d",
#     "contextId": "c295ea44-7543-4f78-b524-7a38915ad6e4",
#     "status": {
#       "state": "submitted",
#       "timestamp": "2024-03-15T11:00:00Z"
#     }
#   }
# }
#
# Later: Server POSTs Notification to Webhook:
#
# POST /webhook/a2a-notifications HTTP/1.1
# Host: client.example.com
# Authorization: Bearer server-generated-jwt
# Content-Type: application/a2a+json
# X-A2A-Notification-Token: secure-client-token-for-task-aaa
#
# {
#   "statusUpdate": {
#     "taskId": "43667960-d455-4453-b0cf-1bae4955270d",
#     "contextId": "c295ea44-7543-4f78-b524-7a38915ad6e4",
#     "status": {
#       "state": "TASK_STATE_COMPLETED",
#       "timestamp": "2024-03-15T18:30:00Z"
#     }
#   }
# }
