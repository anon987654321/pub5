# frozen_string_literal: true

require "minitest/autorun"
require "csv"
require_relative "../../app/services/shared/account_exporter"
require_relative "../../app/services/shared/account_importer"

# The read side of the sheet: typed where the caller names a column type,
# text where it does not, and refused when the sheet is not an export.
class SharedAccountImporterTest < Minitest::Test
  def test_rows_come_back_typed_where_the_caller_knows_the_column
    sheet = sheet([
      ["account", "0", "id", "7"],
      ["account", "0", "email_address", "a@b.no"],
      ["account", "0", "nickname", ""],
      ["account", "0", "settings", "{\"theme\":\"night\"}"],
      ["account", "0", "confirmed_at", "2026-11-06T00:00:00+01:00"],
      ["posts", "0", "published", "true"],
      ["posts", "1", "published", "false"],
    ])

    sections = Shared::AccountImporter.call(sheet, "account" => { "id" => :integer, "settings" => :json,
                                                                 "confirmed_at" => :datetime },
                                                            "posts" => { "published" => :boolean })

    assert_equal 7, sections.dig("account", "0", "id")
    assert_equal "a@b.no", sections.dig("account", "0", "email_address")
    assert_nil sections.dig("account", "0", "nickname")
    assert_equal({ "theme" => "night" }, sections.dig("account", "0", "settings"))
    assert_equal Time.iso8601("2026-11-06T00:00:00+01:00"), sections.dig("account", "0", "confirmed_at")
    assert_equal true, sections.dig("posts", "0", "published")
    assert_equal false, sections.dig("posts", "1", "published")
  end

  def test_an_untyped_column_stays_text
    sheet = sheet([["account", "0", "score", "11"]])

    sections = Shared::AccountImporter.call(sheet)

    assert_equal "11", sections.dig("account", "0", "score")
  end

  def test_an_export_error_row_is_dropped_not_decoded
    sheet = sheet([["posts", "0", "export_error", "association unavailable"]])

    sections = Shared::AccountImporter.call(sheet)

    assert_equal({}, sections["posts"]["0"])
  end

  def test_a_sheet_the_exporter_did_not_write_is_refused
    row = CSV.generate { |csv| csv << %w[thing record field value].map(&:upcase) }

    error = assert_raises(ArgumentError) { Shared::AccountImporter.call(row) }

    assert_match(/expected headers/, error.message)
    assert_match(/THING/, error.message)
  end

  def test_a_column_that_cannot_be_typed_refuses_loudly
    sheet = sheet([["account", "0", "id", "seven"]])

    error = assert_raises(ArgumentError) do
      Shared::AccountImporter.call(sheet, "account" => { "id" => :integer })
    end

    assert_match(/seven|invalid/i, error.message)
  end

  private

  def sheet(rows) = CSV.generate { |csv| csv << Shared::AccountExporter::HEADERS; rows.each { |row| csv << row } }
end
