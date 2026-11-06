# frozen_string_literal: true

require_relative "autofix"

module Fix
  # The boot. A scan is reported the way OpenBSD reports a boot: the kernel
  # ident and the build line, the census totals, the mainbus, then one
  # device line per Law that found something - the mnemonic the Law answers
  # to on the bus, the Law id it enforces, and the finding census over the
  # scanned files. In a dry run the fix0 device attaches last and counts the
  # files the deterministic rewrites would touch; it writes nothing, and the
  # boot ends on the scan's root, the cache at tmp/fix/scan.json.
  module Report
    # Law id -> bus mnemonic. A Law outside the table answers to the first
    # word of its id, so a newly ported Law still attaches under a stable,
    # pronounceable name instead of an acronym soup. The colliding words are
    # curated here so the Law the boot is read for keeps the plain name:
    # line0 is LONG_LINE, grid0 TYPOGRAPHIC_GRID, quote0 QUOTES_BY_LOCALE,
    # blank0 CONSECUTIVE_BLANK_LINES, rescue0 NARROW_SILENT_RESCUE.
    DEVICES = {
      CONSECUTIVE_BLANK_LINES: "blank", LONG_LINE: "line", TYPOGRAPHIC_GRID: "grid",
      VERTICAL_BREATH: "breath", TRAILING_WHITESPACE: "space", TRAILING_COMMAS: "comma",
      TRAILING_COMMENT: "comment", QUOTES_BY_LOCALE: "quote", PREFER_TAG_HELPERS: "tag",
      NO_LOGIC_IN_VIEW: "logic", STIMULUS_PROGRESSIVE: "stim", NO_VAR: "var",
      LAW_OF_DEMETER: "demeter", ABC_SIZE: "abc", FEW_ARGUMENTS: "args",
      CODE_SYMMETRY: "sym", DOUBLE_QUOTES_RUBY: "dq", RUBY_NUMERIC_UNDERSCORE: "num",
      NARROW_SILENT_RESCUE: "rescue", PLUCK_OVER_MAP: "pluck",
      LINE_HEIGHT_ON_SCALE: "lineheight", QUOTE_VARIABLES: "qvar",
      GRID_STRUCTURE: "gridstructure", BLANK_LINE_RUN: "blankrun",
      RESCUE_EXCEPTION: "rescueexc", RESCUE_ON_DEF: "rescuedef"
    }.freeze

    module_function

    # The boot for one scan result. laws is the set that scanned (the
    # scanning Laws, in the order the engine loads them), result the
    # Scan::Result, root the repository root and scope the path scanned.
    # repair and held come from census/2 and attach the fix0 device in a dry
    # run: repair the file count a deterministic rewrite would touch, held
    # the findings it leaves.
    def boot(result, laws:, scope:, root:, dry_run:, repair: nil, held: [])
      dir = File.expand_path(scope, root)
      lines = ["OpenBSD pub5 (GENERIC) #0: #{Time.now.strftime('%a %b %e %H:%M:%S %Z %Y')}",
               "    root@fix:#{dir}",
               "total findings = #{result.findings.size}",
               "files scanned = #{result.files}",
               "files dirty = #{result.findings.map(&:file).uniq.size}",
               "mainbus0 (root): #{File.basename(dir)}",
               "cpu0 at mainbus0: #{laws.size} laws"]
      counts = result.findings.group_by(&:law)
      used = Hash.new(0)
      laws.each do |law|
        found = counts[law.id]
        next unless found&.any?

        unit = attach(law.id, used)
        lines << "#{unit} at mainbus0: #{law.id}"
        lines << "#{unit}: #{found.size} findings in #{found.map(&:file).uniq.size} files"
        detail(unit, law, found).each { |line| lines << line }
      end
      lines.concat(fix0(repair, held)) if dry_run
      lines << "root on scan.json"
      "#{lines.join("\n")}\n"
    end

    # The device handle and its unit number: the curated mnemonic, else the
    # Law's leading word. A second Law answering to the same mnemonic
    # attaches as the next unit, the way a second disk is sd1.
    def attach(id, used)
      name = DEVICES.fetch(id) { id.to_s.split("_").first.to_s.downcase[0, 8] }
      unit = "#{name}#{used[name]}"
      used[name] += 1
      unit
    end

    # The per-device notes the boot carries: what the device fixes and what
    # it leaves. Each note is derived from the findings or the Law's row, so
    # a note printed here is true of this tree.
    def detail(unit, law, found)
      case law.id
      when :QUOTES_BY_LOCALE
        ["#{unit}: \"...\" -> «...»"]
      when :ABC_SIZE
        (ratchet = found.filter_map { |f| f.message.to_s[/ratchet (\d+)/, 1] }.first) ?
          ["#{unit}: complexity above ratchet #{ratchet}"] : []
      when :NO_VAR
        notes = []
        notes << "#{unit}: minified vendor javascript" if found.any? { |f| f.file.match?(%r{vendor/|\.min\.}) }
        notes << "#{unit}: not configured" if law.policy.fetch("autofix", "never") != "automatic"
        notes
      else
        []
      end
    end

    # The fix0 device's dry-run census: what a repair would touch, that
    # nothing outside tmp/fix is written, and what stays held.
    def fix0(repair, held)
      lines = ["fix0 at mainbus0: dry-run"]
      lines << "fix0: #{repair} files would be repaired" if repair
      lines << "fix0: nothing written outside tmp/fix"
      if held.any?
        noise = held.count { |f| %i[NO_VAR ABC_SIZE].include?(f.law) }
        lines << if noise == held.size
          "fix0: vendor and high-complexity left not configured"
        else
          "fix0: #{held.size} findings left to the review lane"
        end
      end
      lines
    end

    # What the deterministic rewrites would count over one scan: the files
    # whose findings a transform owns (Autofix::TRANSFORMS with the Law's
    # row set to automatic), and the findings that stay held.
    def census(result, laws)
      by_id = laws.to_h { |law| [law.id, law] }
      repairable, held = result.findings.partition do |finding|
        law = by_id[finding.law]
        law && Autofix::TRANSFORMS.key?(finding.law) &&
          law.policy.fetch("autofix", "never") == "automatic"
      end
      [repairable.map(&:file).uniq.size, held]
    end
  end
end
