# frozen_string_literal: true

# Auto-loaded by the traces gem when a backend is enabled.
# Requires all A2A trace providers so that key methods are
# instrumented transparently.

def prepare
  require "traces/provider/a2a"
end
