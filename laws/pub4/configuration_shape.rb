# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:272 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 489aee96f10dfcd3
require_relative "master/law/recovered_design_semantics"

Law.define(:CONFIGURATION_SHAPE) do
  source "pub2 master.json anti_sectionitis - consolidate related configuration; keep nesting shallow"
  scope :file
  detect do |text|
    value = YAML.safe_load(text)
    next false unless value.is_a?(Hash)

    max_depth = lambda do |node, depth|
      case node
      when Hash
        [depth, *node.values.map { |child| max_depth.call(child, depth + 1) }].max
      when Array
        [depth, *node.map { |child| max_depth.call(child, depth + 1) }].max
      else
        depth
      end
    end

    max_depth.call(value, 1) > 4 || value.size > 18
  rescue Psych::Exception
    false
  end
  fix "Flatten incidental nesting and consolidate related top-level sections; keep configuration shallow and grouped by purpose."
  bad <<~X
    {
      "a": {
        "b": {
          "c": {
            "d": {
              "e": true
            }
          }
        }
      }
    }
  X
  good <<~X
    {
      "retries": 3,
      "timeout": 30,
      "logging": {
        "level": "info"
      }
    }
  X
end
