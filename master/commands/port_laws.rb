# frozen_string_literal: true

require "date"
require "set"
require_relative "../../laws/engine"
require_relative "../port/pub4_laws"
require_relative "../port/pub4_rows"

module Commands
  # `bin/master port-laws PUB4 [--ref REF] [--agent-rules FILE]` imports every
  # pub4 Law into laws/pub4/ and registry/laws.yml (PLAN.md section 5, P2):
  # the Law.define bodies with the code their files shared, the laws.yml
  # statements and catalogue policy, pub4's checks, ratchets and house lint
  # as check, ratchet and lint Laws, and the operator directives and agent
  # rules as conduct Laws. Every Law enters advisory. Each is then loaded
  # once to measure whether its fixtures prove here; one that does not is
  # kept and marked broken with the failure.
  #
  # Re-runnable: it reads pub4 at REF through git, rewrites only files it
  # wrote and nobody edited since, and keeps each row's lifecycle, census
  # and enactment date.
  class PortLaws
    LAW_DIR = "MASTER/law"
    ALWAYS = %w[lib/review/scan/detector.rb data/laws.yml data/law_runtime.yml data/scan.yml].freeze
    STANDS_IN = %w[lib/master.rb lib/ground/swallow.rb law/definition.rb].freeze

    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(argv)
      @pub4 = argv.shift or return usage
      @ref = option(argv, "--ref") || "origin/main"
      rules = option(argv, "--agent-rules")
      @revision = git("rev-parse", "--short=10", @ref).strip
      @kept = []
      log "pub4 #{@ref} at #{@revision}"
      split = split_laws
      vendor(split)
      units = unroll(split)
      rows = Port::Pub4Rows.new(documents.merge("agent_rules" => rules && read_outside(rules)), revision: @revision)
                           .build(units, split.flat_map(&:refused))
      write_laws(rows, units)
      measure(rows)
      write_rows(rows)
      stale
      verify
    end

    private

    def usage
      @out.puts "usage: bin/master port-laws PUB4_CHECKOUT [--ref origin/main] [--agent-rules FILE]"
      64
    end

    def option(argv, name)
      index = argv.index(name) or return
      argv.delete_at(index)
      argv.delete_at(index)
    end

    def log(line) = @out.puts("port: #{line}")

    def git(*args)
      run = @world.exec("git", "-C", @pub4, *args)
      raise Core::Refusal.new(:exec, "git #{args.first}", run.err.strip) unless run.ok?

      run.out
    end

    def show(path) = git("show", "#{@ref}:#{path}").force_encoding("UTF-8")

    def read_outside(path)
      run = @world.exec(RbConfig.ruby, "-e", "print File.read(ARGV[0])", path)
      run.ok? ? run.out.force_encoding("UTF-8") : raise(Core::Refusal.new(:read, path, run.err.strip))
    end

    def documents
      {
        "laws" => Core::Registry.parse(show("MASTER/data/laws.yml")),
        "context" => Core::Registry.parse(show("MASTER/data/project_context.yml")),
        "checks" => Core::Registry.parse(show("MASTER/checks/checks.yml")),
        "ratchets" => show("MASTER/lib/operator/ratchets.rb"),
        "lints" => lints
      }
    end

    # pub4's house lints: each MASTER/tools lint module, with the first
    # sentence of its opening comment as what it holds.
    def lints
      paths = git("ls-tree", "-r", "--name-only", @ref, "MASTER/tools/").lines.map(&:strip).grep(%r{_lint\.rb\z})
      paths.map do |path|
        comment = show(path).lines.drop_while { |l| !l.start_with?("#") || l.include?("frozen_string_literal") }
                            .take_while { |l| l.start_with?("#") }.map { |l| l.sub(/\A#\s?/, "").strip }.join(" ")
        [path, comment.split(/(?<=\.)\s/).first]
      end
    end

    def split_laws
      files = git("ls-tree", "--name-only", @ref, "#{LAW_DIR}/").lines.map(&:strip).grep(/\.rb\z/)
      files.reject { |f| f.end_with?("/definition.rb") }.map do |path|
        name = File.basename(path)
        split = Port::Pub4Laws.split(name, show(path))
        put("laws/pub4/master/law/#{name}", Port::Pub4Laws.support_file(name, split.support, @revision))
        split
      end
    end

    # The pub4 files the shared code, the Laws and the scanner helpers need,
    # moved to the same place under laws/pub4/master/ so their paths still
    # resolve: each require_relative target, each library file a constant
    # names by pub4's convention (Master::Design::Scale is lib/design/scale.rb),
    # and each data/*.yml one names. lib/master.rb and lib/ground/swallow.rb
    # are hand-written stand-ins.
    def vendor(splits)
      tree = git("ls-tree", "-r", "--name-only", @ref, "MASTER/").lines.map { |l| l.strip.delete_prefix("MASTER/") }.to_set
      texts = splits.flat_map { |s| [s.support] + s.units.map { |u| u.code || u.loop.body.map(&:first).join("\n") } }
      queue = ALWAYS + splits.flat_map { |s| Port::Pub4Laws.requires("law/#{s.name}", s.support) }
      queue += texts.flat_map { |t| Port::Pub4Laws.named_files(t, tree) }
      seen = []
      until queue.empty?
        path = queue.shift
        next if seen.include?(path) || STANDS_IN.include?(path)

        seen << path
        text = show("MASTER/#{path}")
        if path.end_with?(".rb")
          put("laws/pub4/master/#{path}", Port::Pub4Laws.vendored(path, text, @revision))
          queue.concat(Port::Pub4Laws.requires(path, text).select { |p| tree.include?(p) })
        else
          put("laws/pub4/master/#{path}", "# Imported unchanged from pub4 #{@revision} MASTER/#{path} by `bin/master port-laws`.\n#{text}")
        end
      end
      log "vendored #{seen.size} pub4 files (#{seen.count { |p| !p.end_with?('.rb') }} data)"
    end

    # A define inside `<collection>.each` becomes one file per element: the
    # collection is evaluated with the shared code loaded, and so is the id.
    def unroll(splits)
      units = splits.flat_map(&:units)
      units.flat_map do |unit|
        next [unit] unless unit.loop

        require File.join(@world.manifest.root, "laws/pub4/master/law/#{unit.file}")
        opens = unit.nesting.join("; ")
        ends = unit.nesting.map { "end" }.join("; ")
        wrap = ->(src) { unit.nesting.empty? ? src : "#{opens}; #{src}; #{ends}" }
        collection = TOPLEVEL_BINDING.eval(wrap.call(unit.loop.receiver))
        namer = TOPLEVEL_BINDING.eval(wrap.call("proc { |#{unit.loop.params}| #{unit.loop.id_source} }"))
        collection.each_with_index.map do |element, index|
          selector = collection.is_a?(Hash) ? ".slice(#{element.first.inspect})" : ".values_at(#{index})"
          unit.with(id: namer.call(element).to_s, code: Port::Pub4Laws.unrolled(unit, selector))
        end
      end
    end

    def put(path, text)
      (@touched ||= []) << path
      current = File.file?(File.join(@world.manifest.root, path)) ? @world.read(path).force_encoding("UTF-8") : nil
      return if current == text

      if current && Port::Pub4Laws.edited?(current)
        @kept << path
        return
      end
      @world.write(path, text)
    end

    def write_laws(rows, units)
      by_id = units.to_h { |u| [u.id, u] }
      practices = rows.transform_values { |row| row.delete("practice") }
      rows.each do |id, row|
        unit = by_id[id] unless row["unported"]
        text = if unit
                 Port::Pub4Laws.render(unit, revision: @revision)
               else
                 Port::Pub4Laws.statement_law(id, row.dig("pub4", "source"), @revision, practices[id] || row["statement"],
                                              "pub4 #{row.dig('pub4', 'source')}")
               end
        put(row["file"], text)
      end
      log "kept #{@kept.size} files edited since their import: #{@kept.first(10).join(', ')}" if @kept.any?
    end

    def measure(rows)
      root = @world.manifest.root
      paths = rows.values.map { |r| File.join(root, r["file"]) }.select { |p| p.include?("/laws/pub4/") }
      results = Law.measure(paths.sort, rows)
      rows.each do |id, row|
        next unless row["file"].start_with?("laws/pub4/")

        failure = results.fetch(id) { "never defined by #{row['file']}" }
        failure ? row["broken"] = failure : row.delete("broken")
      end
      broken = rows.count { |_, r| r["broken"] }
      log "measured #{paths.size} imported Laws: #{paths.size - broken} prove at load, #{broken} broken"
    end

    def write_rows(rows)
      current = Core::Registry.load(:laws).fetch("laws")
      kept = current.reject { |_, r| r.key?("pub4") }
      merged = kept.merge(rows.to_h { |id, row| [id, preserve(row, current[id])] })
      text = @world.read("registry/laws.yml").force_encoding("UTF-8")
      head = text.lines.take_while { |l| l.start_with?("#") }.join
      @world.write("registry/laws.yml", head + { "laws" => merged }.to_yaml(line_width: -1).delete_prefix("---\n"))
      Core::Registry.reset!
      log "registry/laws.yml: #{merged.size} rows (#{kept.size} written in pub5, #{rows.size} imported)"
    end

    # The operator's half of a row survives a re-run: promotion, census and
    # the date the Law was enacted here.
    def preserve(row, old)
      return row unless old

      row.merge(old.slice("lifecycle", "census", "enacted"))
    end

# Files an earlier run wrote that this one did not: World has no delete
# verb, so they are named for a person to remove.
def stale
  root = @world.manifest.root
  mine = Dir[File.join(root, "laws/pub4/**/*")].select { |f| File.file?(f) }.map { |f| f.delete_prefix("#{root}/") }
            .select { |f| @world.read(f).force_encoding("UTF-8").match?(/\A# (frozen_string_literal: true\n\n# )?Imported unchanged from pub4/) }
  left = mine - @touched
  log "stale: #{left.size} files no longer written by the port: #{left.join(' ')}" if left.any?
end

def verify
      laws = Law.load!
      broken = laws.count(&:broken)
      log "Law.load!: #{laws.size} Laws, #{laws.count(&:enforced?)} enforced, #{broken} broken"
      0
    rescue Law::Invalid => e
      e.message.lines.first(20).each { |line| log "load refused: #{line.chomp}" }
      1
    end
  end
end
