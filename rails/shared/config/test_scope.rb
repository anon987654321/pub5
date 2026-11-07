# frozen_string_literal: true

# What brgen's suite is, said once. bin/rails test globs test/**/*_test.rb from
# the app root, which reaches none of the mountable verticals beside it, so the
# CI step (ci.rb) and the local command (brgen/config/application.rb) both widen
# Rails' DEFAULT_TEST to these roots. They were three copies of one string and
# drifted twice: ci.rb gained ../shared/test alone, and none of the copies
# reached brgen/engines/radio/playlist, brgen/engines/radio/tv or brgen/engines/marketplace/engines/takeaway,
# whose 26 tests no runner ran. Relative to the app root.
module Pub4TestScope
  ROOTS = "{test,../brgen_*/test,../brgen_*/*/test,../brgen_*/engines/*/test,../shared/test}"
  GLOB = "#{ROOTS}/**/*_test.rb".freeze
  EXCLUDE = "#{ROOTS}/{system,dummy,fixtures}/**/*_test.rb".freeze
end
