# frozen_string_literal: true

module Shared
  # Test-suite defaults every pub4 app shares. `require "shared/test_defaults"`
  # from an app's test_helper after `rails/test_help`.
  module TestDefaults
    def self.install!(test_case)
      test_case.parallelize(workers: :number_of_processors)
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
    end
  end
end
