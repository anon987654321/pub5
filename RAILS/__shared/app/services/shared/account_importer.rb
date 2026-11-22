# frozen_string_literal: true

require "csv"
require "json"
require "date"
require_relative "account_exporter" unless defined?(Shared::AccountExporter::HEADERS)

module Shared
  # The read side of the GDPR sheet. The exporter writes rows a spreadsheet
  # opens; this turns them back into values, typed where the caller knows the
  # column type, so an export can be re-read without trusting the CSV to
  # remember anything it does not carry.
  #
  #   Shared::AccountImporter.call(sheet, { "account" => { "id" => :integer } })
  #
  # Types come from the caller: an ActiveRecord record answers
  # attribute_types, and the round-trip proof supplies them per section.
  # Fields with no named type come back as text.
  class AccountImporter
    attr_reader :sections

    def self.call(text, types = {}) = new(text, types).import

    def initialize(text, types = {})
      @rows = CSV.parse(text, headers: true)
      verify_headers!
      @types = types
    end

    def import
      @sections = Hash.new { |hash, section| hash[section] = Hash.new { |records, index| records[index] = {} } }
      @rows.each do |row|
        section = row["section"]
        field = row["field"]
        next if field == "export_error"

        typed = @types.dig(section, field)
        @sections[section][row["record"]][field] = decode(row["value"] || "", typed)
      end
      @sections
    end

    private

    # A sheet the exporter did not write is not an importable export, and a
    # changed HEADER order or a renamed column must be named, not ignored.
    def verify_headers!
      return if @rows.headers == AccountExporter::HEADERS

      raise ArgumentError, "expected headers #{AccountExporter::HEADERS.inspect}, got #{@rows.headers.inspect}"
    end

    def decode(cell, type)
      return nil if cell.nil? || cell.empty?

      case type
      when :integer then Integer(cell, 10)
      when :float, :decimal, :money then BigDecimal(cell)
      when :boolean then { "true" => true, "false" => false }.fetch(cell)
      when :datetime, :time then Time.iso8601(cell)
      when :date then Date.iso8601(cell)
      when :json, :jsonb, :hstore then JSON.parse(cell)
      else cell
      end
    end
  end
end
