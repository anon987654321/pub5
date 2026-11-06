# frozen_string_literal: true

# The check kernel lives once, in master/checks/support/check_result.rb. This path
# stays because checks and tests across rails and openbsd require it by name, and
# openbsd/lib already reads master beside it: check_runner.rb loads master/lib/io/exec.
# Both spellings resolve to one file, so a process that loads each still defines
# Deploy::CheckResult once.
require_relative "../../master/checks/support/check_result"
