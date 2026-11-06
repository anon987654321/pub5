# frozen_string_literal: true

require "date"

module Port
  # The registry half of `bin/master port-laws`: one row per pub4 Law, in
  # pub5's registry/laws.yml shape. Sources, in the order a row takes them:
  #
  # - each Law.define (a Unit): policy from pub4's law_catalogue entry (severity,
  #   autofix, languages, path_exclude, mode, lifecycle), statement and parent
  #   from its laws.yml record when it has one, else its ask, practice or fix;
  # - each laws.yml statement record with no Ruby, a catalogue entry whose
  #   define could not be split, the operator_* directives of
  #   project_context.yml, the agent rules, and pub4's checks, ratchets and
  #   lints: a statement Law, `unported` naming what its detector waits for.
  #
  # Every row enters advisory; `pub4` records where it came from and the
  # policy pub4 gave it.
  class Pub4Rows
    SEVERITY = { "warn" => "warning", "warning" => "warning", "error" => "error", "info" => "info",
                 "veto" => "critical", "critical" => "critical" }.freeze
    AUTOFIX = %w[never review automatic].freeze

    def initialize(docs, revision:, today: Date.today.iso8601)
      @laws = docs.fetch("laws")
      @context = docs.fetch("context")
      @checks = docs.fetch("checks")
      @ratchets = docs.fetch("ratchets")
      @lints = docs.fetch("lints", [])
      @rules = docs["agent_rules"]
      @revision = revision
      @today = today
      catalogue = @laws.fetch("law_catalogue")
      @defaults = catalogue.fetch("defaults", {})
      @entries = catalogue.fetch("entries")
      @records = @laws.select { |_, v| v.is_a?(Hash) && v["statement"] }
      @parents = @records.each_with_object({}) { |(rid, r), acc| Array(r["detector_ids"]).each { |d| acc[d.to_s.upcase] = rid.upcase } }
    end

    def build(units, refused)
      @rows = {}
      units.each { |unit| law(unit) }
      refused.each { |file, line, id, reason| refuse(file, line, id, reason) }
      @entries.each_key { |id| missing_entry(id) }
      @records.each { |id, record| statement(id, record) }
      directives
      agent_rules
      checks
      ratchets
      lints
      @rows
    end

    private

    def text(value) = value.to_s.gsub(/\s+/, " ").strip

    def entry(id) = @entries[id] || @entries.find { |k, _| k.casecmp?(id) }&.last
    def record(id) = @records[id] || @records.find { |k, _| k.casecmp?(id) }&.last

    def put(id, row)
      raise ArgumentError, "#{id}: two pub4 sources claim this id" if @rows.key?(id)

      @rows[id] = row
    end

    def row(id, statement:, kind:, severity:, autofix:, origin:, parent: nil, scope: nil, unported: nil, practice: nil)
      row = { "statement" => text(statement), "kind" => kind, "severity" => SEVERITY.fetch(severity.to_s, "warning"),
              "lifecycle" => "advisory", "autofix" => AUTOFIX.include?(autofix.to_s) ? autofix.to_s : "review",
              "enacted" => @today, "file" => "laws/pub4/#{id.downcase}.rb" }
      row["parent"] = parent.upcase if parent
      row["scope"] = scope if scope && !scope.empty?
      row["unported"] = unported if unported
      row["pub4"] = origin.compact.transform_values(&:to_s)
      row["practice"] = practice if practice
      row
    end

    def law(unit)
      id = unit.id.upcase
      entry = entry(unit.id) || {}
      record = record(unit.id) || {}
      scope = { "languages" => Array(entry["languages"]), "path_exclude" => Array(entry["path_exclude"]) }.reject { |_, v| v.empty? }
      said = [unit.fields[:ask], unit.fields[:practice], unit.fields[:fix]].find { |f| f.is_a?(String) }
      statement = record["statement"] || said&.then { |s| text(s).split(/(?<=[.;])\s/).first } || unit.id
      put(id, row(id, statement:, kind: kind(unit), severity: entry["severity"] || record["severity"] || "warning",
                      autofix: entry["autofix"] || record["resolution"] || @defaults["autofix"],
                      parent: record["parent"] || @parents[id], scope:,
                      origin: { "id" => unit.id, "source" => "MASTER/law/#{unit.file}:#{unit.line}",
                                "lifecycle" => entry["lifecycle"] || @defaults["lifecycle"], "severity" => entry["severity"],
                                "mode" => entry["mode"] || @defaults["mode"] }))
    end

    def kind(unit) = Pub4Laws.kind(unit.file, unit.fields)

    def refuse(file, line, id, reason)
      return unless id

      @refused_ids ||= {}
      @refused_ids[id.upcase] = "MASTER/law/#{file}:#{line}: #{reason}"
    end

    # A catalogue entry with no define split out: refused by the splitter,
    # or (a pub4 defect) catalogued with no definition anywhere.
    def missing_entry(id)
      return if @rows.key?(id.upcase)

      entry = @entries.fetch(id)
      reason = @refused_ids&.fetch(id.upcase, nil) || "catalogued in pub4 but no Law.define(:#{id}) was found in #{Array(entry['definition_sources']).join(', ')}"
      record = record(id) || {}
      put(id.upcase, row(id.upcase, statement: record["statement"] || "#{id} (pub4 Law; its Ruby awaits a hand port)", kind: "structural",
                                    severity: entry["severity"], autofix: "never",
                                    parent: record["parent"] || @parents[id.upcase], unported: "not mechanically portable: #{reason}",
                                    origin: { "id" => id, "source" => Array(entry["definition_sources"]).join(", "),
                                              "lifecycle" => entry["lifecycle"] || @defaults["lifecycle"], "severity" => entry["severity"] }))
    end

    # A laws.yml record: a principle stated, read by a person or a model.
    # One that names pub4 evaluator methods waits for those to be ported.
    def statement(id, record)
      return if @rows.key?(id.upcase)

      evaluators = record.slice("mechanical", "semantic").map { |k, v| "#{k} #{v}" }
      put(id.upcase, row(id.upcase, statement: record["statement"], kind: "semantic", severity: record["severity"] || "warning",
                                    autofix: "never", parent: record["parent"],
                                    unported: evaluators.empty? ? nil : "its pub4 evaluators (#{evaluators.join('; ')}) live in MASTER/lib, outside law/",
                                    practice: record["statement"],
                                    origin: { "id" => id, "source" => "MASTER/data/laws.yml #{id}", "severity" => record["severity"],
                                              "resolution" => record["resolution"] }))
    end

    def directives
      Array(@context["entries"]).select { |e| e["key"].to_s.start_with?("operator_") }.each do |entry|
        id = "OPERATOR_#{entry['key'].delete_prefix('operator_').upcase}"
        put(id, row(id, statement: entry["description"] || entry["name"], kind: "conduct", severity: "warning", autofix: "never",
                        practice: entry["body"],
                        origin: { "id" => entry["key"], "source" => "MASTER/data/project_context.yml #{entry['key']}" }))
      end
    end

    # The agent rules: each top-level bullet, with its sub-bullets, is one
    # conduct Law named by its bold label or its first words.
    def agent_rules
      return unless @rules

      section = nil
      bullets = []
      @rules.each_line do |line|
        if line.start_with?("## ") then section = line.delete_prefix("## ").strip
        elsif line.start_with?("- ") then bullets << [section, +line]
        elsif line.match?(/\A\s+\S/) && bullets.any? then bullets.last[1] << line
        end
      end
      bullets.each_with_index do |(where, bullet), index|
        label = bullet[/\A- \*\*(.+?)\*\*/, 1] || bullet.delete_prefix("- ")
        id = "AGENT_#{Pub4Laws.slug(label, words: 5)}"
        id = "#{id}_#{index + 1}" if @rows.key?(id)
        first = text(bullet.lines.first.delete_prefix("- ").gsub("**", ""))
        put(id, row(id, statement: first, kind: "conduct", severity: "warning", autofix: "never", practice: bullet.strip,
                        origin: { "id" => id, "source" => "AGENT_RULES.md (pub4 session rules) - #{where}" }))
      end
    end

    def checks
      @checks.each do |name, check|
        next unless check.is_a?(Hash)

        id = "CHECK_#{name.upcase}"
        what = check["pass"] ? text(check["pass"].gsub(/%\{(\w+)\}/, '\1')) : "pub4 check #{name} (#{check['script'] || check['gap']})"
        why = if Array(check["needs"]).include?("browser") then "needs a browser over a running app"
              elsif check["script"] then "a script check, MASTER/checks/#{check['script']}"
              else "a #{check['class']} instrument over pub4's tree returning a CheckResult (MASTER/checks/#{check['require']}.rb)"
              end
        put(id, row(id, statement: "Check #{name} holds: #{what}", kind: "check", severity: "warning", autofix: "never",
                        unported: "#{why}; hand port as a check Law once its subject is in pub5",
                        origin: { "id" => name, "source" => "MASTER/checks/checks.yml #{name}", "covered_by" => check["covered_by"] }))
      end
    end

    # Each `*_rows` group of pub4's ratchet register, with the comment that
    # explains it as its statement.
    def ratchets
      lines = @ratchets.lines
      lines.each_with_index do |line, index|
        name = line[/\A\s*def ([a-z_]+)_rows\b/, 1] or next
        next if %w[fast deep all].include?(name)

        comment = lines[0...index].reverse.take_while { |l| l.match?(/\A\s*#/) }.reverse.map { |l| l.sub(/\A\s*#\s?/, "") }.join(" ")
        id = "RATCHET_#{name.upcase}"
        statement = comment.empty? ? "The #{name.tr('_', ' ')} ratchet never rises above its ceiling and never sits below it unlowered." : comment.split(/(?<=\.)\s/).first
        put(id, row(id, statement:, kind: "ratchet", severity: "warning", autofix: "never",
                        unported: "counts a pub4 population against a ceiling recorded in pub4; pub5 measures its own baseline first",
                        origin: { "id" => "#{name}_rows", "source" => "MASTER/lib/operator/ratchets.rb:#{index + 1}" }))
      end
    end

    def lints
      @lints.each do |path, purpose|
        name = File.basename(path, ".rb").delete_suffix("_lint")
        id = "LINT_#{name.upcase}"
        put(id, row(id, statement: purpose || "The #{name.tr('_', ' ')} lint finds nothing above its baseline.", kind: "lint", severity: "warning",
                        autofix: "never", unported: "a RAILS lint module with its own BASELINES over the Rails apps; hand port when rails/ moves (P3)",
                        origin: { "id" => name, "source" => path }))
      end
    end
  end
end
