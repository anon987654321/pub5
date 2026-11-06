# frozen_string_literal: true

module Gatekeeper
  # A git command that did not succeed; the gate reports it and stops the run.
  class Failure < StandardError; end

  # git for the gatekeeper, through World#exec so every call can drop the
  # names a parent git exports to its hooks. Inherited, GIT_INDEX_FILE or
  # GIT_DIR point a `git -C` at the hook's repository instead of this one:
  # the gate's tests run under the pre-commit hook, and its worktree checkout
  # would otherwise write the outer index.
  class Repo
    INHERITED = %w[GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
                   GIT_COMMON_DIR GIT_PREFIX GIT_QUARANTINE_PATH GIT_NAMESPACE GIT_REFLOG_ACTION GIT_EDITOR
                   GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
                   GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE].freeze
    NETWORK_TIMEOUT = 300

    attr_reader :root

    def initialize(world)
      @world = world
      @root = world.manifest.root
    end

    def run(*args, dir: @root, timeout: nil)
      options = { unset: INHERITED, chdir: @root }
      options[:timeout] = timeout if timeout
      @world.exec("git", "-C", dir, *args, **options)
    end

    # stdout, stripped; Failure when git exits non-zero.
    def out!(*args, **options)
      result = run(*args, **options)
      raise Failure, "git #{args.first(3).join(' ')}: #{(result.err + result.out).strip.lines.first.to_s.strip}" unless result.ok?

      result.out.strip
    end

    def ok?(*args) = run(*args).ok?

    def commit?(sha) = ok?("cat-file", "-e", "#{sha}^{commit}")

    def ancestor?(older, newer) = ok?("merge-base", "--is-ancestor", older, newer)

    # One commit's facts. %(trailers) parses the trailer block the way git
    # interpret-trailers does, so a "Writer:" line in prose is not a trailer.
    def commit(sha)
      fields = out!("show", "-s", "--format=%H%x00%P%x00%an%x00%ae%x00%s%x00%(trailers:only,unfold)", sha).split("\0", -1)
      { "sha" => fields[0], "parents" => fields[1].split, "author" => fields[2], "email" => fields[3],
        "subject" => fields[4], "trailers" => fields[5].to_s.lines.map(&:strip).reject(&:empty?) }
    end
  end
end
