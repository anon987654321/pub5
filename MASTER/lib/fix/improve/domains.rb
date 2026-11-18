# frozen_string_literal: true

require "yaml"
require "uri"

module Master
  module Fix
    module Improve
      # Bounded, source-backed craft signals for the Elevation Engine.
      #
      # These probes identify candidates; they do not declare visual,
      # musical, editorial or user acceptance. Each candidate names the
      # measured signal and a smallest-step repair suggestion. Human and
      # rendered evidence remain separate receipts.
      module Domains
        module_function

        DOMAIN_WEIGHT = {
          code: 1.0, prose: 0.9, visual: 1.1, structure: 0.95, music: 0.8
        }.freeze
        CODE_EXTENSIONS = %w[.rb .js .mjs .cjs .jsx .ts .tsx].freeze
        PROSE_EXTENSIONS = %w[.md .markdown .rst .txt .tex].freeze
        VISUAL_EXTENSIONS = %w[.erb .scss .css .html .htm].freeze
        STRUCTURE_EXTENSIONS = %w[.yml .yaml].freeze
        MUSIC_EXTENSIONS = %w[.sco .orc .csd].freeze
        QUALITY_AREAS = {
          code: %w[readability maintainability interaction reliability],
          prose: %w[editorial clarity navigation provenance localization],
          visual: %w[visual_hierarchy accessibility interaction privacy],
          structure: %w[configuration_clarity consistency data_integrity],
          music: %w[notation production_provenance],
        }.freeze
        EXTERNAL_REVIEW_AREAS = %w[
          rendered_composition real_device_use assistive_technology
          human_listening live_host user_acceptance legal_and_business_review
        ].freeze

        def coverage(files:)
          scoped = Array(files).select { |path| File.file?(path) }
          counts = scoped.filter_map { |path| domain_for(path) }.tally
          {
            files_seen: scoped.size,
            measured_files: counts.values.sum,
            domains: counts.keys.map(&:to_s).sort,
            domain_counts: counts.transform_keys(&:to_s).sort.to_h,
            quality_areas: counts.keys.flat_map { |domain| QUALITY_AREAS.fetch(domain, []) }.uniq.sort,
            external_review_areas: EXTERNAL_REVIEW_AREAS,
            unmeasured_files: scoped.size - counts.values.sum,
          }
        end

        def scan(root:, files:)
          scoped = Array(files).select { |path| File.file?(path) }
          implementations = {
            code: method(:scan_code),
            prose: method(:scan_prose),
            visual: method(:scan_visual),
            structure: method(:scan_structure),
            music: method(:scan_music),
          }
          domains = scoped.filter_map { |path| domain_for(path) }.uniq
          domains.flat_map do |domain|
            candidates = scoped.select { |path| domain_for(path) == domain }
            implementations.fetch(domain).call(root:, files: candidates.first(400))
          end.sort_by { |opportunity| -opportunity.leverage }
        end

        def domain_for(path)
          normalized = path.to_s.tr("\\", "/")
          extension = File.extname(normalized).downcase

          # BIZ HTML is a document source, not an application view. Its visual
          # styling is judged as editorial document design, not app chrome.
          return :prose if normalized.split("/").include?("BIZ") &&
            (PROSE_EXTENSIONS + %w[.html .htm .erb]).include?(extension)

          return :code if CODE_EXTENSIONS.include?(extension)
          return :prose if PROSE_EXTENSIONS.include?(extension)
          return :visual if VISUAL_EXTENSIONS.include?(extension)
          return :structure if STRUCTURE_EXTENSIONS.include?(extension)
          return :music if MUSIC_EXTENSIONS.include?(extension)

          nil
        end

        # --- code: readable, bounded implementation with clean file endings. ---
        def scan_code(root:, files:)
          files.flat_map do |path|
            source = read_text(path)
            findings = []
            if File.extname(path).downcase == ".rb"
              spans = method_boundaries(source.lines)
              longest = spans.max_by { |span| span[:end] - span[:start] }
              if longest && (longest[:end] - longest[:start]) > 48
                findings << opportunity(
                  :code, path, "long_method",
                  "#{File.basename(path)}##{longest[:name]} spans #{longest[:end] - longest[:start]} lines",
                  9.0, "Reduce #{longest[:name]} at a genuine responsibility boundary; preserve its public contract and avoid extracting one-use helpers merely to shorten the file.",
                  line: longest[:start] + 1
                )
              end

              first = source.lines.first.to_s.strip
              if first != "# frozen_string_literal: true" && source.lines.size > 12
                findings << opportunity(
                  :code, path, "unfrozen_literals",
                  "Ruby source has no frozen-string-literal declaration",
                  4.0, "Add the frozen-string-literal magic comment only after checking that no string literal is mutated in place.",
                  line: 1
                )
              end
            end

            if %w[.js .mjs .cjs .jsx .ts .tsx].include?(File.extname(path).downcase)
              findings.concat(scan_script_experience(path, source))
            end

            if !source.empty? && !source.end_with?("\n")
              findings << opportunity(
                :code, path, "missing_final_newline",
                "the source file does not end with a newline",
                3.0, "Add one terminal newline without changing the file's content."
              )
            end

            blank_run = source.match(/(?:\n[ \t]*){4,}/)
            if blank_run
              findings << opportunity(
                :code, path, "excess_blank_lines",
                "four or more consecutive blank lines interrupt the source",
                2.5, "Reduce the blank-line run to the spacing needed to separate the surrounding concepts.",
                line: line_number(source, blank_run.begin(0))
              )
            end
            findings
          end
        end

        # Source-backed interaction and resilience prompts. These are advisory:
        # a reviewer checks the call site and existing app feedback conventions
        # before changing behaviour.
        def scan_script_experience(path, source)
          findings = []
          dialog = source.match(/\b(?:window\s*\.\s*)?(?:alert|confirm|prompt)\s*\(/)
          if dialog
            findings << opportunity(
              :code, path, "native_dialog",
              "a browser-native dialog interrupts the application's interaction context",
              5.5, "Review whether an inline, app-native feedback or confirmation pattern can preserve context; retain native confirmation where it protects a consequential action.",
              line: line_number(source, dialog.begin(0))
            )
          end

          fetch_call = source.match(/\bfetch\s*\(/)
          if fetch_call && !source.match?(/\.\s*catch\s*\(|\btry\s*\{/)
            findings << opportunity(
              :code, path, "fetch_without_visible_error_path",
              "the file contains fetch() but no visible rejection or try/catch path",
              6.5, "Trace this request's full call chain and provide useful recovery or user feedback for rejection; do not add a catch that silently swallows the error.",
              line: line_number(source, fetch_call.begin(0))
            )
          end
          findings
        end

        def method_boundaries(lines)
          starts = []
          lines.each_with_index do |text, index|
            match = text.match(/^\s*def\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_?!=]*)/)
            starts << { name: match[1], start: index } if match
          end
          starts.each_with_index.map do |entry, index|
            finish = index + 1 < starts.size ? starts[index + 1][:start] : lines.size
            { name: entry[:name], start: entry[:start], end: finish }
          end
        end

        # --- prose: hierarchy, navigability and useful editorial density. ---
        def scan_prose(root:, files:)
          files.flat_map do |path|
            source = read_text(path)
            prose = source
              .gsub(/<script\b.*?<\/script>/im, " ")
              .gsub(/<style\b.*?<\/style>/im, " ")
              .gsub(/<%.*?%>/m, " ")
              .gsub(/<!--.*?-->/m, " ")
              .gsub(/<[^>]+>/, " ")
              .gsub(/\x60[^\x60]*\x60/, " ")
              .gsub(/^\s*(?:\x60{3}|~{3}).*?^\s*(?:\x60{3}|~{3})\s*$/m, " ")
            words = prose.scan(/[\p{L}\p{N}]+/).size
            extension = File.extname(path).downcase
            markdown = %w[.md .markdown].include?(extension)
            heading_rows = if markdown
                             markdown_headings(source)
                           elsif %w[.html .htm].include?(extension)
                             html_headings(source)
                           else
                             []
                           end
            findings = []

            if words < 60 && File.basename(path) =~ /README|CONTRIBUTING|ARCHITECTURE/i
              findings << opportunity(
                :prose, path, "thin_document",
                "#{words} words cannot carry the purpose, run path and source of truth a reader needs",
                8.0, "Add only the missing practical information: purpose and audience, how to run or use it, and the canonical source of truth."
              )
            end

            navigational = markdown && (
              File.basename(path).match?(/\A(?:README|AGENTS|ARCHITECTURE|CONTRIBUTING)/i) ||
              path.tr("\\", "/").split("/").include?("docs")
            )
            if heading_rows.empty? && words > 240 && navigational
              findings << opportunity(
                :prose, path, "wall_of_text",
                "#{words} words appear without navigational headings",
                6.0, "Partition the text under headings that answer the reader's likely questions; do not add headings to short correspondence or literary prose."
              )
            end

            previous_level = nil
            heading_rows.each do |row|
              if previous_level && row[:level] > previous_level + 1
                findings << opportunity(
                  :prose, path, "heading_level_skip",
                  "heading at line #{row[:line]} jumps from level #{previous_level} to level #{row[:level]}",
                  5.0, "Restore a logical heading hierarchy without changing the section's wording or order.",
                  line: row[:line]
                )
                break
              end
              previous_level = row[:level]
            end

            if markdown
              findings.concat(scan_markdown_links(root:, path:, source:))
            end

            generic_link = source.match(/\[([^\]]+)\]\([^)]+\)/)
            if generic_link && generic_link[1].strip.match?(/\A(?:here|click here|read more|learn more)\z/i)
              findings << opportunity(
                :prose, path, "generic_link_text",
                "a link uses non-descriptive text: #{generic_link[1].strip.inspect}",
                5.5, "Give the link text a destination-specific name that remains meaningful when read out of context.",
                line: line_number(source, generic_link.begin(0))
              )
            end

            placeholder = source.match(/\bTBD\b|\bTODO:\s*write\b|lorem ipsum/i)
            if placeholder
              findings << opportunity(
                :prose, path, "placeholder",
                "placeholder text remains in reader-facing prose",
                7.5, "Replace the placeholder with verified content, or remove the promise and leave only what is known.",
                line: line_number(source, placeholder.begin(0))
              )
            end
            findings
          end
        end

        def scan_markdown_links(root:, path:, source:)
          findings = []
          in_fence = false
          source.each_line.with_index do |line, index|
            if line.match?(/^\s*(?:`{3,}|~{3,})/)
              in_fence = !in_fence
              next
            end
            next if in_fence

            line.to_enum(:scan, /!?\[[^\]]*\]\(([^)]+)\)/).each do
              match = Regexp.last_match
              destination = match[1].strip.sub(/\s+["'][^"']*["']\z/, "").sub(/\A</, "").sub(/>\z/, "")
              next if destination.empty? || destination.start_with?("#", "//")
              uri = URI.parse(destination) rescue nil
              next if uri&.scheme || destination.start_with?("mailto:", "tel:")
              next if destination.match?(/\A(?:data|javascript):/i)

              raw_path = destination.split(/[?#]/, 2).first
              next if raw_path.to_s.empty?
              decoded = URI::DEFAULT_PARSER.unescape(raw_path)
              candidate = if decoded.start_with?("/")
                            File.expand_path(decoded.delete_prefix("/"), root)
                          else
                            File.expand_path(decoded, File.dirname(path))
                          end
              root_path = File.expand_path(root)
              next unless candidate == root_path || candidate.start_with?(root_path + File::SEPARATOR)
              next if File.file?(candidate) || File.directory?(candidate)

              findings << opportunity(
                :prose, path, "broken_relative_link",
                "relative Markdown link points to a missing path: #{raw_path}",
                8.5, "Resolve the destination against the repository and update the link to an existing file or remove the broken reference; preserve external URLs and intended anchors.",
                line: index + 1
              )
              break
            end
            break if findings.any?
          end
          findings
        rescue URI::InvalidURIError
          []
        end

        def markdown_headings(source)
          source.each_line.with_index.filter_map do |line, index|
            match = line.match(/^\s*(\#{1,6})\s+\S/)
            { level: match[1].length, line: index + 1 } if match
          end
        end

        def html_headings(source)
          rows = []
          source.to_enum(:scan, /<h([1-6])\b/i).each do
            match = Regexp.last_match
            rows << { level: match[1].to_i, line: line_number(source, match.begin(0)) }
          end
          rows
        end

        # --- visual: semantic names and token-led styling, not aesthetic claims. ---
        def scan_visual(root:, files:)
          files.flat_map do |path|
            source = read_text(path)
            extension = File.extname(path).downcase
            findings = []

            if %w[.erb .html .htm].include?(extension)
              source.to_enum(:scan, /<img\b[^>]*>/im).each do
                match = Regexp.last_match
                next if match[0].match?(/\balt\s*=/i)

                findings << opportunity(
                  :visual, path, "image_without_alt",
                  "an image element has no alt attribute",
                  9.5, "Describe the information the image conveys; use alt=\"\" only when it is genuinely decorative.",
                  line: line_number(source, match.begin(0))
                )
                break
              end

              if source.match?(/<html\b/i) && !source.match?(/<html\b[^>]*\blang\s*=/i)
                findings << opportunity(
                  :visual, path, "document_language_missing",
                  "a full HTML document does not declare its primary language",
                  8.5, "Declare the correct document language on the html element using the product's actual locale; do not guess from the file path.",
                  line: line_number(source, source.index(/<html\b/i))
                )
              end

              if source.match?(/<html\b/i) && !source.match?(/<title\b[^>]*>\s*\S/im)
                findings << opportunity(
                  :visual, path, "document_title_missing",
                  "a full HTML document has no non-empty title element",
                  7.5, "Provide a concise, page-specific document title consistent with the product's naming conventions.",
                  line: line_number(source, source.index(/<html\b/i))
                )
              end

              control_match = nil
              source.to_enum(:scan, /<(input|select|textarea)\b[^>]*>/im).each do
                candidate = Regexp.last_match
                tag = candidate[0]
                next if tag.match?(/\btype\s*=\s*["']?(?:hidden|submit|button|reset|image)\b/i)
                next if tag.match?(/\b(?:aria-label|aria-labelledby|title)\s*=/i)

                id_match = tag.match(/\bid\s*=\s*["']([^"']+)["']/i)
                paired = id_match && source.match?(/<label\b[^>]*\bfor\s*=\s*["']#{Regexp.escape(id_match[1])}["']/i)
                before = source[0...candidate.begin(0)]
                label_open = before.rindex(/<label\b[^>]*>/i)
                label_close = before.rindex(%r{</label>}i)
                wrapped = label_open && (!label_close || label_open > label_close) &&
                  source[candidate.end(0)..].to_s.match?(%r{</label>}i)
                next if paired || wrapped

                control_match = candidate
                break
              end
              if control_match
                findings << opportunity(
                  :visual, path, "form_control_without_label",
                  "a form control has no explicit label or programmatic accessible name in this source",
                  9.5, "Associate the control with a visible label or a concise aria-label/aria-labelledby reference; placeholders alone are not labels.",
                  line: line_number(source, control_match.begin(0))
                )
              end

              empty_button = source.match(/<button\b(?![^>]*\b(?:aria-label|aria-labelledby|title)=)[^>]*>\s*(?:<\/button>)/im)
              if empty_button
                findings << opportunity(
                  :visual, path, "empty_button",
                  "a button has no visible or programmatic name",
                  9.0, "Give the control a visible action label or a concise accessible name that describes its action.",
                  line: line_number(source, empty_button.begin(0))
                )
              end

              source.each_line.with_index do |line, index|
                next unless line.match?(/\bimage_tag\b/) && !line.match?(/\balt\s*:/)

                findings << opportunity(
                  :visual, path, "image_tag_without_alt",
                  "an image_tag call on this line has no alt option",
                  8.5, "Supply an accurate alt option, or an explicit empty alt for a decorative image.",
                  line: index + 1
                )
                break
              end

              icon_link = source.match(/<a\b(?![^>]*\b(?:aria-label|title)=)[^>]*>\s*(?:<i\b|<svg\b|<span\b[^>]*\bicon)/im)
              if icon_link
                findings << opportunity(
                  :visual, path, "icon_only_link",
                  "an icon-only link has no accessible name",
                  9.0, "Add an aria-label that names the link's destination; retain the icon as decoration.",
                  line: line_number(source, icon_link.begin(0))
                )
              end

              icon_button = source.match(/<button\b(?![^>]*\b(?:aria-label|aria-labelledby|title)=)[^>]*>\s*(?:<i\b|<svg\b|<span\b[^>]*\bicon)/im)
              if icon_button
                findings << opportunity(
                  :visual, path, "icon_only_button",
                  "an icon-only button has no accessible name",
                  9.0, "Add an aria-label describing the action; do not use the icon glyph as the only name.",
                  line: line_number(source, icon_button.begin(0))
                )
              end
            end

            if %w[.scss .css].include?(extension) &&
               source.match?(/outline\s*:\s*(?:none|0)\b/i) &&
               !source.match?(/:focus(?:-visible)?\b/i)
              outline = source.match(/outline\s*:\s*(?:none|0)\b/i)
              findings << opportunity(
                :visual, path, "focus_outline_removed",
                "the stylesheet removes outlines without a visible focus replacement in the same source",
                9.0, "Check the compiled stylesheet graph and restore a clearly visible keyboard-focus treatment; do not add a duplicate if a shared global focus style already covers this selector.",
                line: line_number(source, outline.begin(0))
              )
            end

            if %w[.scss .css].include?(extension) &&
               source.match?(/(?:^|[;{\s])(?:animation|transition)\s*:/i) &&
               !source.match?(/prefers-reduced-motion/i)
              motion = source.match(/(?:^|[;{\s])(?:animation|transition)\s*:/i)
              findings << opportunity(
                :visual, path, "motion_without_reduced_motion_path",
                "the stylesheet defines motion but has no reduced-motion handling in the same source",
                7.5, "Inspect the compiled stylesheet graph and provide a prefers-reduced-motion alternative where this motion is non-essential; avoid duplicating an existing global policy.",
                line: line_number(source, motion.begin(0))
              )
            end

            if %w[.scss .css].include?(extension) &&
               source.scan(/#[0-9a-f]{3,8}\b/i).size >= 3 &&
               !source.match?(/scan:\s*intentional-colors/i) &&
               !path.match?(%r{(?:token|variable|palette|color|colour)[^/]*\.(?:scss|css)\z}i)
              findings << opportunity(
                :visual, path, "raw_hex_colors",
                "the stylesheet contains literal hex colours outside an intentional-colour declaration",
                5.5, "Resolve each colour through the existing design-token source; retain explicitly documented brand or media exceptions."
              )
            end
            findings
          end
        end

        # --- structure: catch ambiguous duplicate YAML keys before a reader or
        # parser silently treats the last value as authoritative. ---
        def scan_structure(root:, files:)
          files.flat_map do |path|
            source = read_text(path)
            next [] unless %w[.yml .yaml].include?(File.extname(path).downcase)

            findings = []
            walk = lambda do |node|
              next unless node.respond_to?(:children)

              if node.is_a?(Psych::Nodes::Mapping)
                seen = {}
                node.children.each_slice(2) do |key_node, _value_node|
                  next unless key_node.is_a?(Psych::Nodes::Scalar)

                  key = key_node.value
                  if seen.key?(key)
                    findings << opportunity(
                      :structure, path, "duplicate_yaml_key",
                      "mapping key #{key.inspect} is repeated at lines #{seen[key]} and #{key_node.start_line + 1}",
                      9.5, "Resolve the duplicate deliberately: keep the intended value once and preserve any distinct meaning under an explicit key.",
                      line: key_node.start_line + 1
                    )
                  else
                    seen[key] = key_node.start_line + 1
                  end
                end
              end
              node.children.each { |child| walk.call(child) }
            end
            stream = Psych.parse_stream(source)
            walk.call(stream) if stream
            findings
          end
        end

        # --- music: a score must tell the performer what to play, not make
        # them infer tempo and dynamics from a filename. Listening stays human. ---
        def scan_music(root:, files:)
          files.filter_map do |path|
            source = read_text(path)
            if MUSIC_EXTENSIONS.include?(File.extname(path).downcase)
              missing = []
              missing << "no tempo statement" unless source.match?(/\btempo\b|\bt\s+\d+/i)
              missing << "no dynamics marking" unless source.match?(/\bp[3-9]\b|cresc|dim|ff|pp/i)
              next if missing.empty?

              opportunity(
                :music, path, "unmarked_score",
                missing.join("; ") + "; a performer should not have to guess the basic markings",
                6.0, "Add verified tempo and dynamics markings at the top of the score; do not infer musical values."
              )
            elsif File.extname(path).downcase == ".yml" && source.match?(/\b(?:bpm|tempo|instrument):\s*\z/)
              opportunity(
                :music, path, "empty_music_field",
                "a tempo or instrument field is declared but empty",
                4.0, "Fill the field from an authoritative source or remove the empty declaration."
              )
            end
          end
        end

        def opportunity(domain, path, signal, detail, weight, fix, line: 1)
          Opportunity.new(
            domain:, path:, signal:, detail:,
            leverage: weight * DOMAIN_WEIGHT.fetch(domain),
            fix:, line:
          )
        end

        def read_text(path)
          File.read(path, encoding: "UTF-8", invalid: :replace)
        end

        def line_number(source, offset)
          source[0...offset].count("\n") + 1
        end
      end
    end
  end
end
