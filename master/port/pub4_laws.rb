# frozen_string_literal: true

require "prism"
require "digest"

module Port
  # The mechanical half of `bin/master port-laws`: pub4 source text in, pub5
  # Law files and registry rows out. No I/O here; the command reads pub4
  # through git and writes through World.
  #
  # A pub4 law file holds many `Law.define` calls inside shared modules,
  # constants and helpers. Each define becomes laws/pub4/<id>.rb, reopening
  # the modules it sat in, so constants resolve as they did in pub4; the
  # rest of the file (the shared code) becomes laws/pub4/master/law/<file>,
  # which every Law from that file requires. A define inside a loop is
  # unrolled one element per file. A define that cannot be split this way is
  # returned in `refused` with the reason, never dropped.
  module Pub4Laws
    HEADER = "# import-digest: "
    SCOPE_NODES = [Prism::ProgramNode, Prism::StatementsNode, Prism::ModuleNode, Prism::ClassNode].freeze

    # One define, ready to render. `loop` is set for a define unrolled from
    # `<collection>.each do |params| ... end`: the command evaluates the
    # collection and the id once per element (Unroll).
    Unit = Data.define(:id, :file, :line, :nesting, :prelude, :code, :fields, :loop)
    Loop = Data.define(:receiver, :params, :body, :keep, :id_source)
    Split = Data.define(:name, :support, :units, :refused)

    module_function

    def digest(text) = Digest::SHA256.hexdigest(text)[0, 16]

    # A file the port wrote carries the digest of what it wrote; a file whose
    # body no longer matches was edited by hand and is kept.
    def stamped(lines, body) = "#{lines.join}#{HEADER}#{digest(body)}\n#{body}"

    def edited?(text)
      head, body = text.split(/^#{Regexp.escape(HEADER)}(\h{16})\n/, 2).then { |a| [a[1], a[2]] }
      head.nil? || digest(body.to_s) != head
    end

    def split(name, source)
      tree = Prism.parse(source)
      raise ArgumentError, "#{name}: #{tree.errors.first.message}" if tree.failure?

      units = []
      refused = []
      cuts = []
      walk(tree.value, []) do |call, chain|
        anchor, inner = anchor(call, chain)
        unless anchor
          refused << [name, call.location.start_line, call_id(call), "Law.define inside #{chain.last.class.name.split('::').last}, not a module, class or each loop"]
          next
        end
        cuts << anchor
        nesting = nesting(inner)
        prelude, missing = prelude(anchor, chain, source)
        if missing.any?
          refused << [name, call.location.start_line, call_id(call), "reads local #{missing.join(', ')} defined outside its definition"]
          next
        end
        if anchor.equal?(call)
          units << Unit.new(id: call_id(call), file: name, line: call.location.start_line, nesting:, prelude:,
                            code: from_line_start(source, call), fields: fields(call), loop: nil)
        else
          units << loop_unit(name, source, anchor, call, nesting, prelude)
        end
      end
      Split.new(name:, support: support(source, cuts.uniq), units:, refused:)
    end

    def walk(node, chain, &block)
      if node.is_a?(Prism::CallNode) && node.name == :define && %w[Law ::Law].include?(node.receiver&.slice)
        yield node, chain
        return
      end
      node.compact_child_nodes.each { |child| walk(child, chain + [node], &block) }
    end

    def call_id(call)
      arg = call.arguments&.arguments&.first
      arg.is_a?(Prism::SymbolNode) ? arg.unescaped.to_s : nil
    end

    # The statement a define is cut out as: the define itself when only
    # modules and classes enclose it, or the `each` loop it sits in.
    def anchor(call, chain)
      return [call, chain] if chain.all? { |n| SCOPE_NODES.include?(n.class) } && call_id(call)

      index = chain.index { |n| !SCOPE_NODES.include?(n.class) }
      loop = chain[index]
      inner = chain[index + 1..]
      ok = loop.is_a?(Prism::CallNode) && loop.name == :each && loop.block.is_a?(Prism::BlockNode) &&
           inner.first.is_a?(Prism::BlockNode) && inner.drop(1).all? { |n| n.is_a?(Prism::StatementsNode) }
      ok ? [loop, chain[0...index]] : [nil, nil]
    end

    def nesting(chain)
      chain.grep(Prism::ModuleNode).union(chain.grep(Prism::ClassNode)).sort_by { |n| n.location.start_offset }
           .map { |n| "#{n.is_a?(Prism::ModuleNode) ? 'module' : 'class'} #{n.constant_path.slice}" }
    end

    # Local variables a cut statement reads from the scope around it: their
    # assignments are copied in front of it, in order, with what they read.
    def prelude(anchor, chain, source)
      scope = chain.reverse.find { |n| n.is_a?(Prism::StatementsNode) }
      earlier = scope ? scope.body.take_while { |s| !s.equal?(anchor) && s.location.start_offset < anchor.location.start_offset } : []
      writes = earlier.select { |s| s.is_a?(Prism::LocalVariableWriteNode) }
      wanted = outer_reads(anchor, 0)
      taken = []
      loop do
        found = writes.select { |w| wanted.include?(w.name) && !taken.include?(w) }
        break if found.empty?

        taken += found
        wanted |= found.flat_map { |w| outer_reads(w.value, 0) }
      end
      missing = wanted - writes.map(&:name)
      [taken.sort_by { |w| w.location.start_offset }.map { |w| from_line_start(source, w) }, missing.map(&:to_s)]
    end

    # Names read from outside `node`: a read whose depth reaches past every
    # block opened between it and `node`.
    def outer_reads(node, blocks)
      return [] unless node

      case node
      when Prism::DefNode then []
      when Prism::LocalVariableReadNode, Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
           Prism::LocalVariableAndWriteNode
        node.depth >= blocks ? [node.name] : []
      else
        deeper = node.is_a?(Prism::BlockNode) || node.is_a?(Prism::LambdaNode) ? blocks + 1 : blocks
        node.compact_child_nodes.flat_map { |child| outer_reads(child, deeper) }.uniq
      end
    end

    def loop_unit(name, source, anchor, call, nesting, prelude)
      block = anchor.block
      statements = block.body.is_a?(Prism::StatementsNode) ? block.body.body : []
      body = statements.map { |s| [from_line_start(source, s), s.equal?(call)] }
      keep = statements.index { |s| s.equal?(call) }
      others = statements.each_index.select { |i| i != keep && defines?(statements[i]) }
      body = body.each_with_index.reject { |_, i| others.include?(i) }.map(&:first)
      loop = Loop.new(receiver: anchor.receiver.slice, params: block.parameters&.parameters&.slice.to_s,
                      body:, keep: body.index { |_, kept| kept }, id_source: call.arguments.arguments.first.slice)
      Unit.new(id: nil, file: name, line: call.location.start_line, nesting:, prelude:, code: nil, fields: fields(call), loop:)
    end

    def defines?(node) = node.slice.match?(/\bLaw\.define\b/)

    def from_line_start(source, node)
      start = node.location.start_offset - node.location.start_column
      source.byteslice(start, node.location.end_offset - start).force_encoding("UTF-8")
    end

    # The shared code: the file with each cut statement removed, its lines
    # kept blank so a line number in a pub4 trace still finds its place.
    def support(source, cuts)
      text = source.b
      cuts.sort_by { |c| -c.location.start_offset }.each do |cut|
        range = cut.location.start_offset...cut.location.end_offset
        text[range] = text[range].gsub(/[^\n]/n, "")
      end
      text.force_encoding("UTF-8")
    end

    # The words a define states in literal strings: the statement fallback
    # (ask, practice, fix), its source, and which detector kind it has.
    WORDS = %i[fix ask practice source detect check detector adapter pattern proved_by].freeze

    def fields(call)
      found = {}
      block = call.block
      return found unless block

      stack = [block.body].compact
      until stack.empty?
        node = stack.pop
        if node.is_a?(Prism::CallNode) && node.receiver.nil? && WORDS.include?(node.name) && !found.key?(node.name)
          arg = node.arguments&.arguments&.first
          found[node.name] = literal(arg) || true
          next if %i[detect check].include?(node.name)
        end
        stack.concat(node.compact_child_nodes.reverse) unless node.is_a?(Prism::BlockNode) && !node.equal?(block)
      end
      found
    end

    # A string literal's text; a squiggly heredoc is one string in parts.
    def literal(node)
      return node.unescaped.to_s if node.respond_to?(:unescaped)
      return unless node.is_a?(Prism::InterpolatedStringNode) && node.parts.all? { |p| p.is_a?(Prism::StringNode) }

      node.parts.map(&:unescaped).join
    end

    def kind(file, fields)
      return "rendered" if %w[rendered.rb geometry.rb].include?(file)
      return "lint" if file == "linters.rb"
      return "structural" if fields[:check] || fields[:detector] || fields[:adapter]
      return "lexical" if fields[:detect] || fields[:pattern]
      return "semantic" if fields[:ask]

      "conduct"
    end

    # A unit's rendered file: header, the require of its shared code, its
    # modules reopened around what it needs from them and the define itself.
    def render(unit, revision:)
      support = "master/law/#{unit.file.delete_suffix('.rb')}"
      body = +"require_relative #{support.inspect}\n\n"
      body << unit.nesting.each_with_index.map { |open, i| "#{'  ' * i}#{open}\n" }.join
      body << unit.prelude.map { |p| "#{p}\n" }.join
      body << upcased(unit.code, unit.id).chomp << "\n"
      body << unit.nesting.each_index.reverse_each.map { |i| "#{'  ' * i}end\n" }.join
      stamped(header("MASTER/law/#{unit.file}:#{unit.line}", revision), body)
    end

    # A unit unrolled from a loop keeps the loop, narrowed to one element.
    def unrolled(unit, selector)
      loop = unit.loop
      inner = loop.body.map(&:first).join("\n")
      "#{loop.receiver}#{selector}.each do |#{loop.params}|\n#{inner}\nend"
    end

    def header(where, revision)
      ["# frozen_string_literal: true\n", "\n",
       "# Imported unchanged from pub4 #{revision} #{where} by `bin/master port-laws`.\n",
       "# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.\n"]
    end

    # A Law with no Ruby in pub4 (a laws.yml statement, a directive, an
    # agent rule, a check or ratchet awaiting its hand port): its statement
    # as the practice every writer is shown.
    def statement_law(id, where, revision, practice, source)
      body = +"require_relative \"master/lib/master\"\n\n"
      body << "Law.define(:#{id}) do\n"
      body << "  source #{source.inspect}\n"
      body << "  practice #{practice.strip.inspect}\n"
      body << "end\n"
      stamped(header(where, revision), body)
    end

    def support_file(name, text, revision)
      lines = header("MASTER/law/#{name} (shared code; its Law.define calls moved to laws/pub4/)", revision)
      stamped(lines, "require_relative \"../lib/master\"\n#{text.sub(/\A# frozen_string_literal: true\n/, '')}")
    end

    def vendored(path, text, revision)
      stamped(header("MASTER/#{path}", revision), text.sub(/\A# frozen_string_literal: true\n/, ""))
    end

    # require_relative targets a moved pub4 file names, as MASTER-relative
    # paths, so the port can carry them too.
    def requires(path, text)
      text.scan(/^\s*require_relative\s+["']([^"']+)["']/).flatten.map do |target|
        File.expand_path("#{target.delete_suffix('.rb')}.rb", "/#{File.dirname(path)}").delete_prefix("/")
      end
    end

    def underscore(name) = name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

    # MASTER-relative files a text names without requiring them: a
    # Master::A::B constant by pub4's Zeitwerk convention (lib/a.rb and
    # lib/a/b.rb, each that exists), and a data/*.yml path. Only files in `tree`.
    def named_files(text, tree)
      constants = text.scan(/\bMaster((?:::[A-Z]\w*)+)/).flatten.uniq.map { |c| c.split("::").reject(&:empty?) }
      libs = constants.flat_map do |parts|
        (1..parts.size).map { |n| "lib/#{parts.first(n).map { |p| underscore(p) }.join('/')}.rb" }
      end
      data = text.scan(%r{data/([a-z0-9_]+\.ya?ml)}).flatten.map { |f| "data/#{f}" } +
             text.scan(/["']data["'],\s*["']([a-z0-9_]+\.ya?ml)["']/).flatten.map { |f| "data/#{f}" }
      (libs + data).uniq.select { |p| tree.include?(p) }
    end

    # pub5 ids are upper case; a pub4 id spelled lower case (the detector
    # class Laws: :rubocop, :semantic) is upcased where the define names it.
    def upcased(code, id)
      return code if id == id.upcase

      code.sub(/(Law\.define\(\s*):#{Regexp.escape(id)}\b/) { "#{Regexp.last_match(1)}:#{id.upcase}" }
    end

    SEVERITY = { "warn" => "warning", "warning" => "warning", "error" => "error", "info" => "info", "veto" => "critical" }.freeze

    def slug(text, words: 6)
      text.to_s.gsub(/\*\*|`/, "").scan(/[A-Za-z0-9]+/).first(words).join("_").upcase
    end
  end
end
