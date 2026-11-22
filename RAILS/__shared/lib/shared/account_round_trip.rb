# frozen_string_literal: true

module Shared
  # The export/import round-trip contract, over an app's real schema. prove
  # exports a user, reads the sheet back with AccountImporter, and returns
  # every difference from the records the sheet must carry: each owned
  # association, each non-secret attribute of each record, compared by the
  # column type the app's model answers. [] is a full round trip.
  #
  # The format's own limits are part of the contract, not findings: secrets
  # are absent by design, times carry whole seconds (the sheet's iso8601
  # granularity), and nil and a blank string both export as "" - matched when
  # the two are both empty.
  module AccountRoundTrip
    module_function

    def prove(user)
      # The sheet's reader walks the graph the way the route that exports it
      # does, outside the test default's strict loading.
      user.strict_loading!(false)
      sheet = AccountExporter.call(user)
      types = type_sheet(user)
      sections = AccountImporter.call(sheet, types)
      diffs = []
      account_section(sections, user, diffs)
      association_sections(sections, user, diffs)
      diffs
    end

    # Every section's column type map, read off each exported model: an
    # association's type map comes from its first record's class, so the read
    # side decodes ints and times the way the column says. An empty
    # association carries no rows to decode.
    def type_sheet(user)
      types = { "account" => column_types(user) }
      owned(user).each do |reflection|
        types[reflection.name.to_s] = record_types(reflection, user)
      end
      types
    end

    def account_section(sections, user, diffs)
      expected = user.attributes.reject { |name, _| secret?(name) }
      got = sections["account"]&.fetch("0", {})
      missing = expected.keys - got.keys
      diffs << "account is missing #{missing.sort.join(', ')}" unless missing.empty?

      expected.each do |field, value|
        next unless got.key?(field)

        diffs << "account.#{field} exports #{cell(value).inspect}, reads back #{got[field].inspect}" unless matches?(value, got[field])
      end
    end

    def association_sections(sections, user, diffs)
      owned(user).each do |reflection|
        records = export_records(user, reflection)
        section = sections[reflection.name.to_s] || {}
        diffs << "#{reflection.name} carries #{records.size} records, the sheet #{section.size}" if records.size != section.size

        records.each_with_index do |record, index|
          got = section.fetch(index.to_s, {})
          record.attributes.reject { |name, _| secret?(name) }.each do |field, value|
            next unless got.key?(field)

            diffs << "#{reflection.name}[#{index}].#{field} exports #{cell(value).inspect}, reads back #{got[field].inspect}" unless matches?(value, got[field])
          end
        end
      end

      unknown = sections.keys - %w[account] - owned(user).map { |reflection| reflection.name.to_s }
      diffs << "sheet carries sections the schema does not own: #{unknown.sort.join(', ')}" unless unknown.empty?
    end

    def export_records(user, reflection)
      value = user.public_send(reflection.name)
      # Array(), not [:x]: an unowned has_one exports no rows at all, the
      # way the exporter's own records() answer does.
      reflection.macro == :has_one ? Array(value) : value.to_a
    end

    # The same ownership the exporter reads; one definition, in the exporter's
    # own words.
    def owned(user)
      user.class.reflect_on_all_associations
           .select { |reflection| %i[has_one has_many].include?(reflection.macro) }
           .reject { |reflection| reflection.options[:through] }
           .sort_by(&:name)
    end

    def column_types(record)
      record.class.attribute_types.filter_map do |name, type|
        next if secret?(name)

        [name, type.type]
      end.sort.to_h
    end

    def record_types(reflection, user)
      value = user.public_send(reflection.name)
      record = reflection.macro == :has_one ? value : value.first
      record ? column_types(record) : {}
    end

    # A section's record type is known only where records exist; fields of an
    # empty association have no type to name, and the sheet carries no rows to
    # decode for them.

    def secret?(name)
      AccountExporter::SECRET_COLUMNS.include?(name) ||
        AccountExporter::SECRET_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
    end

    def matches?(value, decoded)
      case value
      when Time, ActiveSupport::TimeWithZone, DateTime
        value.strftime("%FT%T") == decoded.strftime("%FT%T")
      else
        decoded == value || (blank?(value) && decoded.nil?)
      end
    end

    def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)

    def cell(value) = value.is_a?(String) ? value : value.inspect
  end
end
