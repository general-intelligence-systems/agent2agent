#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.9. Fetching Authenticated Extended Agent Card
# Scenario: A client discovers a public Agent Card indicating support for an authenticated
# extended card and wants to retrieve the full details.
#
# Step 1: Client fetches the public Agent Card:
#
# GET /.well-known/agent-card.json HTTP/1.1
# Host: example.com
#
# Response includes:
#
# {
#   "capabilities": {
#     "extendedAgentCard": true
#   },
#   "securitySchemes": {
#     "google": {
#       "openIdConnectSecurityScheme": {
#         "openIdConnectUrl": "https://accounts.google.com/.well-known/openid-configuration"
#       }
#     }
#   }
# }
#
# Step 2: Client obtains credentials (out-of-band OAuth 2.0 flow)
#
# Step 3: Client fetches authenticated extended Agent Card
#
# GET /extendedAgentCard HTTP/1.1
# Host: agent.example.com
# Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
#
# Response:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "name": "Extended Agent with Additional Skills",
#   "skills": [
#     /* Extended skills available to authenticated users */
#   ]
# }
