# frozen_string_literal: true

module Master
  module Ground
    # Inside an OpenHands sandbox the agent server exposes its own OpenAI-compatible
    # endpoint at OH_INTERNAL_SERVER_URL, authenticated with the session key. That
    # lane is always reachable and costs nothing, so MASTER wires it as the optional
    # `gateway` lane at boot when no operator has set MASTER_LLM_GATEWAY_URL. This
    # keeps a keyless sandbox from falling through to the remote free tier (llm7,
    # kilo, ovh) for every turn.
    #
    # The endpoint caps the system role at 32 KiB, so the fold is enabled too.
    module OpenhandsSandbox
      # The agent server refuses a system message over 32 KiB (verified against
      # OH_INTERNAL_SERVER_URL: 32768 bytes accepted, 33000 refused) and accepts
      # the same text as a user turn. FoldLongSystem needs the flag set.
      FOLD_SYSTEM = "1"

      module_function

      # Exports MASTER_LLM_GATEWAY_URL / _KEY / _FOLD_SYSTEM from the sandbox
      # environment when the operator has not chosen a gateway. Returns the base
      # URL it wired, or nil when the sandbox is not detected, a gateway already
      # exists, or auto-wiring is disabled.
      #
      # MASTER_NO_SANDBOX_GATEWAY=1 is the explicit opt-out. MASTER_NO_ENV_FILES=1
      # (the suite's "route against empty state of its own") disables it too: a
      # discovered sandbox endpoint is machine state, like a key in
      # ~/.config/master/env, and must not decide which lane a test sees.
      def wire!(env = ENV)
        return nil if disabled?(env)
        return nil if env["MASTER_LLM_GATEWAY_URL"].to_s.strip != ""

        base = env["OH_INTERNAL_SERVER_URL"].to_s.strip
        key = env["SESSION_API_KEY"].to_s.strip
        return nil if base.empty? || key.empty?

        env["MASTER_LLM_GATEWAY_URL"] = "#{base.chomp('/')}/v1"
        env["MASTER_LLM_GATEWAY_KEY"] = key
        env["MASTER_LLM_GATEWAY_FOLD_SYSTEM"] ||= FOLD_SYSTEM
        env["MASTER_LLM_GATEWAY_URL"]
      end

      def disabled?(env)
        env["MASTER_NO_SANDBOX_GATEWAY"].to_s != "" || env["MASTER_NO_ENV_FILES"].to_s == "1"
      end
    end
  end
end
