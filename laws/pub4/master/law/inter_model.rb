# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/inter_model.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b0889992e2f5a8d2
require_relative "../lib/master"

# Detect direct council calls that bypass the shared request/response adapter.
# The detector is deliberately limited to call sites whose argument is named
# prompt, a heredoc prompt, or a prompt: keyword. Calls using the adapter's
# outbound envelope are allowed; their argument is named outbound/request.



























