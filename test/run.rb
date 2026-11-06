# frozen_string_literal: true

# Runs every suite under test/ in one process: `ruby test/run.rb`. Both
# naming styles count (foo_test.rb and test_foo.rb).
(Dir[File.join(__dir__, "**", "*_test.rb")] + Dir[File.join(__dir__, "**", "test_*.rb")]).uniq.sort.each { |file| require file }
