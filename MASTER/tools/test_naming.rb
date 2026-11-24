# frozen_string_literal: true

# MASTER names tests test_<subject>.rb. Check nested suites too; a root-only
# glob let non-canonical names hide under test/voice or test/operator.

root = File.expand_path("..", __dir__)
dir = File.expand_path(ENV.fetch("MASTER_TEST_ROOT", File.join(root, "test")))
fixtures = File.join(dir, "fixtures") + File::SEPARATOR
included = lambda { |path| !path.start_with?(fixtures) }

wrong = Dir.glob(File.join(dir, "**", "*_test.rb")).select(&included)
          .reject { |path| File.basename(path).start_with?("test_") }
ok = Dir.glob(File.join(dir, "**", "test_*.rb")).select(&included)

if wrong.empty?
  puts "test_naming: #{ok.size} test_*.rb, 0 non-canonical *_test.rb"
  exit 0
end

wrong.each { |path| puts "  #{path.delete_prefix("#{dir}/")}" }
abort "test_naming: #{wrong.size} file(s) use *_test.rb - MASTER's convention is test_*.rb"
