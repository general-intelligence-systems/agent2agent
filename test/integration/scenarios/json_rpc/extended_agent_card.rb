#!/usr/bin/env ruby
# frozen_string_literal: true

# Scenario 6.9: Fetching Authenticated Extended Agent Card (JSON-RPC binding)
# ===========================================================================
#
# A client discovers a public Agent Card, learns it supports an extended
# card, authenticates, and retrieves the full agent details.
#
# Note: Agent Card discovery is inherently HTTP-based (GET requests to
# well-known URLs). The JSON-RPC binding may use a JSON-RPC method for
# fetching the extended card, or it may fall back to the same HTTP
# endpoints as the REST binding for discovery.
#
# Steps:
#   1. Fetch the public Agent Card
#      - GET /.well-known/agent-card.json (HTTP, same as REST)
#      - No authentication required
#   2. Check if the agent supports an extended card
#      - Response includes capabilities.extendedAgentCard == true
#      - Response includes securitySchemes with authentication details
#   3. Obtain credentials (out-of-band OAuth 2.0 / OIDC flow)
#   4. Fetch the authenticated extended Agent Card
#      - May use GET /rest/extendedAgentCard (HTTP) or a JSON-RPC method
#      - Include Authorization header with bearer token from step 3
#   5. Receive the extended Agent Card with additional skills and details
#
# Expected behavior:
#   Step 1 (public card):
#   - Response status is 200
#   - Response is valid JSON
#   - capabilities.extendedAgentCard == true
#   - securitySchemes is present and non-empty
#
#   Step 4 (extended card):
#   - If via HTTP: Response status is 200, Content-Type is application/a2a+json
#   - If via JSON-RPC: Response has no error, result contains agent details
#   - Response contains agent name
#   - Response contains "skills" array with extended skills
#   - Extended skills are not present in the public card
#
#   Error case (no auth):
#   - Request without Authorization
#   - Should return 401 Unauthorized (HTTP) or JSON-RPC auth error
#
# Example Step 1 - Public Agent Card:
#   GET /.well-known/agent-card.json HTTP/1.1
#   Host: example.com
#
#   Response:
#   {
#     "capabilities": {
#       "extendedAgentCard": true
#     },
#     "securitySchemes": {
#       "google": {
#         "openIdConnectSecurityScheme": {
#           "openIdConnectUrl": "https://accounts.google.com/.well-known/openid-configuration"
#         }
#       }
#     }
#   }
#
# Example Step 4 - Extended Agent Card:
#   GET /rest/extendedAgentCard HTTP/1.1
#   Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
#
#   Response:
#   {
#     "name": "Extended Agent with Additional Skills",
#     "skills": [
#       /* Extended skills available to authenticated users */
#     ]
#   }
