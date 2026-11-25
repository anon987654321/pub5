# frozen_string_literal: true

require "etc"

module Shared
  # Test-suite defaults every pub4 app shares. `require "shared/test_defaults"`
  # from an app's test_helper after `rails/test_help`.
  module TestDefaults
    def self.install!(test_case)
      # At most four workers: one per core on the 8 GB workstation starved it,
      # and CI then ran alongside other jobs at load 15 (operator, 2026-11-25).
      # PARALLEL_WORKERS still overrides, as Rails reads it before this value.
      test_case.parallelize(workers: [Etc.nprocessors, 4].min)
      test_case.fixtures :all
      # Rails.cache is process-wide and survives the transactional rollback that
      # isolates everything else, so anything cache-backed leaks between tests.
      # Shared::SessionsActions and PasswordsActions declare
      # `rate_limit to: 10, within: 3.minutes` on :create, which is exactly that:
      # once the test cache became real (:memory_store, replacing :null_store),
      # the eleventh sign-in in a suite started redirecting to /session/new and
      # an unrelated test failed. Clearing per test keeps rate limiting
      # exercisable instead of silently disabled.
      test_case.setup { Rails.cache.clear }
      # I18n.locale is per thread and survives a test that sets it, so a test
      # that switched to :en left the next one in the same worker rendering
      # English: TypingIndicatorTest got "is typing" for "skriver" and failed
      # brgen's bin/ci at random (2026-11-25). Every test starts on the default.
      test_case.setup { I18n.locale = I18n.default_locale }
      ActionDispatch::IntegrationTest.prepend(SignInWitness) if defined?(ActionDispatch::IntegrationTest)
    end

    # amber's bin/ci twice failed 10-26 signed-in tests at random with
    # "redirect to /session/new" (2026-11-25), never reproduced alone, and the
    # per-file sign_in_as helpers never check their POST. This names why a
    # sign-in was refused, on stderr, without changing any test's outcome:
    # tests that expect a refused sign-in still get exactly that.
    module SignInWitness
      def post(path, **)
        super.tap do
          back_to_sign_in = response.redirect? && response.location.to_s.end_with?("/session/new")
          next unless back_to_sign_in && path.to_s.end_with?("/session")

          warn "sign-in witness: #{name} POST #{path} refused, alert=#{flash[:alert].inspect}"
        end
      end
    end
  end
end
