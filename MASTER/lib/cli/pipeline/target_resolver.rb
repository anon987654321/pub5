# frozen_string_literal: true

require_relative "../../boot/paths"

module Master
  module CLI
    class Pipeline
      # A /fix target is either one path or a comma/whitespace-separated list of
      # governed tree names. The questions "is this a tree list?" and "which
      # word is not a governed tree?" are pure text work asked both before a run
      # starts (CommandRegistry) and inside one (Pass), so they are answered
      # here once instead of in three near-identical spellings.
      module TreeTarget
        module_function

        # The upcased words of a multi-word target, or [] when the target is a
        # single word and therefore a path. Flags are not words: "/fix RAILS
        # --lane=code" names one place and one option.
        def names(text)
          tokens = text.to_s.split(/[,\s]+/).reject(&:empty?).reject { |token| token.start_with?("-") }
          return [] if tokens.size < 2

          tokens.map(&:upcase)
        end

        def list?(text)
          words = names(text)
          words.any? && words.all? { |word| MasterPaths::TREES.include?(word) }
        end

        # The words of a tree list that no governed tree names. A target naming
        # no governed tree at all is a path that happens to contain a space, not
        # a tree list, so only a partial list can be a refused typo.
        def ungoverned(text)
          words = names(text)
          return [] if words.empty?

          outside = words.reject { |word| MasterPaths::TREES.include?(word) }
          outside.size == words.size ? [] : outside
        end

        # Why a target cannot be served, naming the offending word and the trees
        # that exist, or nil when every word is governed.
        def refusal(text)
          outside = ungoverned(text)
          return if outside.empty?

          "#{outside.join(", ")} #{outside.one? ? "is" : "are"} not a governed tree " \
            "(#{MasterPaths::TREES.join(", ")}): a /fix target is one path inside a governed tree " \
            "or a list of governed trees"
        end
      end

      module TargetResolver
        ALL_TREE_NAMES = MasterPaths::TREES

        def resolve_target(raw)
          text = raw.to_s.strip
          # Shell-style recursive targets are scope notation, not literal
          # directories. /fix RAILS/** therefore governs the RAILS tree itself.
          text = text.sub(%r{/\*\*(?:/\*)?\z}, "")
          # An omitted target means the checkout MASTER is actually running from.
          # "everything"/"all" remains the explicit repository-wide spelling.
          return Master::REPO_ROOT if all_tree_target?(text)
          return @root if text.empty?
          return Master::REPO_ROOT if text.match?(%r{\A(?:all|everything|the|code|codebase|it|this|that)\z}i)
          # A tree list is a queue the caller splits, and an ungoverned word is a
          # typo. Neither is one directory, so refuse instead of expanding a path
          # named after the sentence the person typed.
          if (refusal = tree_target_refusal(text))
            raise ArgumentError, refusal
          end
          aliases = target_aliases
          return aliases[text] if aliases.key?(text)
          return tree_prefixed(text) if tree_prefixed(text)
          # A path is only a target when it exists: a governed prefix matched by
          # text alone (MASTER/MASTER RAILS) is not a directory anyone meant.
          path = File.expand_path(text, @root)
          return path if governed_path?(path) && exists?(path)

          # CLI analysis targets such as `lib/io` are MASTER-relative when the
          # caller is the repository root. Resolve that shorthand before
          # declaring the target outside the governed trees.
          master_relative = File.expand_path(text, Master::ROOT)
          return master_relative if governed_path?(master_relative) && exists?(master_relative)

          raise ArgumentError, "target outside pub5 trees: #{raw.inspect}"
        end

        # One path cannot stand for several trees. `MASTER RAILS` is a queue of
        # two runs; CommandRegistry#fix_targets splits it. `OPENBSD STUDIO BIZ`
        # names a word no tree owns, so the person hears which word that was.
        def tree_target_refusal(text)
          if TreeTarget.list?(text)
            return "target is a list of trees: #{TreeTarget.names(text).join(", ")} " \
                   "(resolve one tree at a time, or name all of #{ALL_TREE_NAMES.join(", ")})"
          end

          refusal = TreeTarget.refusal(text)
          "target outside pub5 trees: #{refusal}" if refusal
        end

        def tree_prefixed(text)
          return File.join(Master::RAILS_ROOT, text.sub(%r{\Arails[:/]}i, "")) if text.match?(%r{\Arails[:/]}i)

          name = text.delete_prefix("../")
          return unless ALL_TREE_NAMES.any? { |tree| name.match?(%r{\A#{tree}(?:/|\z)}i) }

          File.expand_path(name, Master::REPO_ROOT)
        end

        def exists?(path) = File.file?(path) || File.directory?(path)

        def governed_path?(path)
          repo = File.expand_path(Master::REPO_ROOT)
          return true if path == repo
          ALL_TREE_NAMES.any? do |tree|
            root = File.join(repo, tree)
            path == root || path.start_with?("#{root}/")
          end
        end

        def all_tree_target?(text)
          names = text.split(/[,\s]+/).reject(&:empty?).map(&:upcase).uniq.sort
          names == ALL_TREE_NAMES.sort
        end

        def shell_target(abs)
          return "self" if abs == File.join(@root, "lib")
          return "all five trees" if abs == Master::REPO_ROOT
          return "master" if abs == @root
          return "rails" if abs == Master::RAILS_ROOT
          return "face" if abs == File.join(Master::ROOT, "web", "public")
          return "web" if abs == File.join(Master::ROOT, "web")
          if abs.start_with?("#{Master::RAILS_ROOT}/")
            return "rails/#{abs.delete_prefix("#{Master::RAILS_ROOT}/")}"
          end
          if abs.start_with?("#{@root}/")
            return abs.delete_prefix("#{@root}/")
          end

          abs
        end

        def target_aliases
          {
            "self" => File.join(@root, "lib"),
            "master" => @root,
            "itself" => @root,
            "." => @root,
            "rails" => Master::RAILS_ROOT,
            "RAILS" => Master::RAILS_ROOT,
            "face" => File.join(Master::ROOT, "web", "public"),
            "web" => File.join(Master::ROOT, "web"),
          }
        end
      end
    end
  end
end
