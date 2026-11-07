# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../laws/engine"

class LawCheckRunnerTest < Minitest::Test
  def test_runner_preserves_all_declared_exit_states
    assert_equal :passed, Law::CheckRunner.classify_exit(0)
    assert_equal :inconclusive, Law::CheckRunner.classify_exit(3)
    assert_equal :failed, Law::CheckRunner.classify_exit(1)
    assert_equal :failed, Law::CheckRunner.classify_exit(70)
  end

  def test_each_imported_check_law_resolves_to_one_real_pub5_instrument
    laws = Core::Registry.load(:laws).fetch("laws")
    checks = Core::Registry.yaml(File.join(Core::ROOT, "master", "checks", "checks.yml"))
    check_rows = laws.select { |_id, row| row["kind"] == "check" }
    assert_equal 68, check_rows.size

    names = check_rows.map { |_id, row| row.dig("pub4", "id") }
    assert_equal names.uniq, names
    names.each do |name|
      row = checks.fetch(name) { flunk "missing check registry row: #{name}" }
      assert_equal 1, [row["class"], row["script"]].compact.size
      if row["script"]
        assert File.file?(File.join(Core::ROOT, "master", "checks", row["script"])), "missing script for #{name}"
      end
      if row["require"]
        require_path = row["require"]
        base = require_path.start_with?("master/", "openbsd/") ? Core::ROOT : File.join(Core::ROOT, "master", "checks")
        candidates = [File.join(base, require_path), File.join(base, "#{require_path}.rb")]
        assert candidates.any? { |path| File.file?(path) }, "missing require target for #{name}: #{require_path}"
      end
    end
  end
end
