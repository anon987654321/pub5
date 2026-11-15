# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# A reader on a Norwegian page and a reader on an English page must meet the
# same interface. The flash contract pins the flash: block; this one walks
# every locale file pair in the family — app files, split-domain files like
# allergens.nb.yml, engine files at any nesting depth — and fails on the first
# key that exists on one side and not the other. Registration found the tree
# fully in parity; the test exists so the next key added in one language only
# is caught the day it lands, not when a reader of the other language meets
# the fallback string.
class LocaleParityTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)

  def keys_under(hash, prefix = "")
    hash.flat_map { |key, value| value.is_a?(Hash) ? keys_under(value, "#{prefix}#{key}.") : ["#{prefix}#{key}"] }
  end

  def locale_pairs
    # Both globs keep only the nb side of each pair: en.yml would otherwise
    # arrive as its own "nb file" and compare against itself.
    (Dir.glob(File.join(RAILS_ROOT, "*/config/locales/*.yml")) +
     Dir.glob(File.join(RAILS_ROOT, "*/engines/**/config/locales/*.yml")))
      .select { |path| File.basename(path).match?(/\A(|.+?\.)nb\.yml\z/) }.sort
  end

  def test_every_nb_locale_file_has_an_en_counterpart
    missing = locale_pairs.reject do |nb_file|
      en_file = nb_file.sub(/(\.)?nb\.yml\z/) { Regexp.last_match(1) ? "#{Regexp.last_match(1)}en.yml" : "en.yml" }
      File.file?(en_file)
    end
    assert_empty missing, "locale files without an en counterpart: #{missing.join(", ")}"
  end

  def test_every_locale_pair_carries_the_same_keys_in_both_languages
    locale_pairs.each do |nb_file|
      en_file = nb_file.sub(/(\.)?nb\.yml\z/) { Regexp.last_match(1) ? "#{Regexp.last_match(1)}en.yml" : "en.yml" }
      next unless File.file?(en_file)

      nb = keys_under(YAML.safe_load_file(nb_file).fetch("nb", {}))
      en = keys_under(YAML.safe_load_file(en_file).fetch("en", {}))

      only_nb = nb - en
      only_en = en - nb
      assert_empty only_nb, "#{en_file.sub("#{RAILS_ROOT}/", "")} is missing nb-side keys: #{only_nb.first(8).join(", ")}"
      assert_empty only_en, "#{nb_file.sub("#{RAILS_ROOT}/", "")} is missing en-side keys: #{only_en.first(8).join(", ")}"
    end
  end
end
