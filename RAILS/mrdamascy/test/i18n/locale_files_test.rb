# frozen_string_literal: true

require "test_helper"

# Every string exists in both languages, and every static key the app asks
# for is there.
class LocaleFilesTest < ActiveSupport::TestCase
  PLURAL_KEYS = %w[zero one two few many other].freeze

  test "nb and en carry the same keys" do
    nb = locale_keys("nb")
    en = locale_keys("en")

    assert_empty nb - en, "missing in en.yml"
    assert_empty en - nb, "missing in nb.yml"
  end

  test "courier gratuity copy uses clear Bokmål wording" do
    keys = %w[tip_line tip_none tip_title tip_refused tip_unpaid]
    copy = keys.map { |key| I18n.t("orders.#{key}", locale: :nb) }
    copy << I18n.t("flash.tip_thanks", locale: :nb)

    assert_equal "Tips (ikke betalt i appen)", copy[0]
    assert_equal "Uten tips", copy[1]
    assert_equal "Vil du gi tips til kureren?", copy[2]
    assert_equal "Tusen takk for tipset!", copy.last
    refute_match(/drikkegis/i, copy.join(" "))
  end

  test "every static key used in app/ exists" do
    keys = locale_keys("nb")
    used = Rails.root.glob("app/**/*.{rb,erb}").flat_map { |path| path.read.scan(/\bt\(\s*["']([a-z_][\w.]*)["']/) }
    missing = used.flatten.uniq.reject do |key|
      keys.include?(key) || keys.any? { |known| known.start_with?("#{key}.") }
    end

    assert_empty missing
  end

  private

  def locale_keys(locale)
    flatten_keys(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale))
  end

  # A plural hash (one/other) is one key; any other hash nests.
  def flatten_keys(tree, prefix = nil)
    tree.flat_map do |name, value|
      key = [ prefix, name ].compact.join(".")
      nested = value.is_a?(Hash) && (value.keys - PLURAL_KEYS).any?
      nested ? flatten_keys(value, key) : [ key ]
    end
  end
end
