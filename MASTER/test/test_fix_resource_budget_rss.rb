# frozen_string_literal: true

require_relative "test_helper"

# The RSS limit sheds /fix's model work. It was a flat 768 MB, sized for vm23's
# 1 GB, so on a laptop pass 1 alone crossed it and no model fix ever ran. It now
# scales with the machine and keeps the old figures as its floor.
class TestFixResourceBudgetRss < Minitest::Test
  def budget(memory_mb:, config: {})
    Master::Fix::ResourceBudget.new(root: Dir.pwd, config:, memory_mb:)
  end

  def limits(budget) = [budget.send(:rss_limit, "warn"), budget.send(:rss_limit, "crit")]

  def test_a_one_gigabyte_server_keeps_the_original_figures
    assert_equal [384, 640], limits(budget(memory_mb: 1000))
  end

  def test_a_laptop_gets_a_share_of_its_memory
    assert_equal [1638, 3277], limits(budget(memory_mb: 16_384))
  end

  def test_the_floor_holds_on_a_machine_smaller_than_the_server
    assert_equal [384, 640], limits(budget(memory_mb: 256))
  end

  def test_configuration_still_wins
    config = { "load" => { "master_rss_mb" => { "warn" => 300, "crit" => 900 } } }

    assert_equal [300, 900], limits(budget(memory_mb: 16_384, config:))
  end

  # The shipped configuration must leave the ceiling to the scaling: data/limits.yml pinned 768 MB, so
  # three /fix passes on an 8 GB Mac shed every model fix at about 1 GB resident.
  def test_the_shipped_configuration_lets_an_eight_gigabyte_mac_scale
    shipped = Master::Fix::ResourceBudget.new(root: Dir.pwd, memory_mb: 8192)

    assert_equal [819, 1638], limits(shipped)
  end

  def test_pass_one_of_a_fix_run_is_no_longer_critical_on_a_laptop
    critical = budget(memory_mb: 8192).send(:classify_one_check, :ok, :rss_mb, 791, *limits(budget(memory_mb: 8192)))

    assert_equal [:ok, nil], critical
  end
  def test_container_pressure_sheds_optional_work_even_when_process_rss_is_low
    resource = budget(memory_mb: 4096)
    result = resource.send(:classify_resource_checks, { rss_mb: 100, cgroup_memory_ratio: 0.94 })

    assert_equal :critical, result.first
    assert_match(/cgroup_memory_ratio/, result.last.join(" "))
  end

  def test_container_ratio_uses_the_most_constrained_ancestor
    resource = budget(memory_mb: 4096)
    groups = [["/group/child", "max", "current"], ["/group", "max", "current"]]
    values = { "/group/child/max" => 1000, "/group/child/current" => 100,
               "/group/max" => 2000, "/group/current" => 1800 }
    resource.stub(:linux_memory_groups, groups) do
      resource.stub(:memory_bytes, ->(path) { values[path] }) do
        assert_in_delta 0.9, resource.send(:cgroup_memory_ratio), 0.001
      end
    end
  end
end
