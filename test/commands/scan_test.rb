# frozen_string_literal: true

require_relative "../fix/fix_helper"
require "stringio"
require_relative "../../master/commands/scan"

# `bin/master scan` over a fixture repository: the boot reports the finding
# as a device census, the dry run attaches fix0, and the scan's only write
# is the cache at tmp/fix/scan.json.
class ScanCommandTest < Minitest::Test
  include FixHelper

  VERBS = Core::Registry.load(:commands).fetch("commands").fetch("scan").fetch("verbs")

  def scan(root, *argv)
    out = StringIO.new
    code = Commands::Scan.new(world: world(root, VERBS, protected_paths: [], name: "scan"),
                              context: "pipe", out:).call(argv)
    [code, out.string]
  end

  def fixture
    repo do |root|
      commit_all(root)
      put(root, "lib/broken.rb", "x = 1      ")
      yield root
    end
  end

  def test_scan_boots_the_census_and_ends_on_the_cache_root
    fixture do |root|
      code, out = scan(root)
      assert_equal 0, code
      assert_match(/\AOpenBSD pub5 \(GENERIC\) #0: [A-Z][a-z]{2} /, out)
      assert_match(/^    root@fix:/, out)
      assert_match(/mainbus0 \(root\): #{File.basename(root)}/, out)
      assert_match(/cpu0 at mainbus0: \d+ laws/, out)
      assert_match(/space0 at mainbus0: TRAILING_WHITESPACE\nspace0: 1 findings in 1 files/, out)
      assert_match(/total findings = \d+\nfiles scanned = \d+\nfiles dirty = 1/, out)
      assert_match(/root on scan\.json\n\z/, out)
      assert File.file?(File.join(root, "tmp/fix/scan.json"))
      assert_equal %w[.git .gitignore lib log tmp], Dir.children(root).sort
    end
  end

  def test_dry_run_attaches_fix0_which_counts_but_writes_nothing
    fixture do |root|
      code, out = scan(root, "--dry-run")
      assert_equal 0, code
      assert_match(/fix0 at mainbus0: dry-run/, out)
      assert_match(/fix0: 1 files would be repaired/, out)
      assert_match(/fix0: nothing written outside tmp\/fix/, out)
      assert_match(/fix0: \d+ findings left to the review lane|fix0: vendor and high-complexity left not configured/, out)
    end
  end

  def test_a_missing_scope_is_a_usage_error
    fixture do |root|
      code, out = scan(root, "nope")
      assert_equal 64, code
      assert_match(/\Ausage: bin\/master scan/, out)
    end
  end
end
