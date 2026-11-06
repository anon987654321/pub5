# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:26 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 100909afe7832c68
require_relative "master/law/shell"

Law.define(:NEVER_BATCH_DELETE) do
  source "master.yml v66 file_deletion_protocol - never batch-delete files"
  # File deletion lives here, and only here. GUARD_EXPENSIVE_OPS carried a bare
  # `rm -rf` too, so one question had two instruments free to disagree; it keeps
  # the database sweeps, this keeps the filesystem. The root and home targets
  # came across with it — an unbounded `rm -rf /` is the same consequence class
  # as a glob and the same rule should say so.
  #
  # `${app_dir}` is a variable expansion, not a brace glob, and the `{` in it
  # was four of this law's six findings — every scoped removal in the deploy
  # pipeline. Blanked before the glob test, since a `{` that survives is one
  # somebody typed.
  # An array literal is the fourth branch's exemption, and it is what the other
  # three already test for. A glob, a bare `$var` and a `Dir[]` are all
  # dangerous because the set is unknown until the line runs; the `.each { rm }`
  # branch asked only whether there was a loop, so it read a receiver spelled out
  # in full as the same hazard. `%w[.mp3 .job .err .meta.json].each { |ext|
  # rm_f(dir + ext) }` — the tts test's teardown — names how many files go and
  # which, and each call removes one named path, which is what the fix line asks.
  # `Dir[...]` keeps firing: the `[` there follows a word character, so the
  # bracket belongs to an index rather than to a literal.
  detect do |line|
    bare = line.gsub(/\$\{[^}]*\}/) { |m| "\0" * m.length }
    enumerated = /(?:%[wi][\[({][^\])}]*[\])}]|(?<![\w\])])\[[^\[\]]*\])\s*\.each\s*\{/
    bare.match?(/\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)*[^\s;|&]*[*?{]/) ||
      bare.match?(%r{\brm\s+-[a-zA-Z]*[rf][a-zA-Z]*\s+(?:"?/"?\s*(?:$|;)|"?~|\$\w+)}) ||
      line.match?(/FileUtils\.rm(_r|_rf|_f)?\(?\s*Dir\[/) ||
      (line.match?(/\.each\s*\{[^}]*(?:File\.delete|FileUtils\.rm)/) && !line.match?(enumerated))
  end
  fix "Delete one named path per call and confirm first; globs and .each { rm } need an explicit operator ack."
  bad  <<~RUBY
    FileUtils.rm_rf(Dir["tmp/*.txt"])
    system("rm -f build/*.o")
    stale.each { |f| File.delete(f) }
  RUBY
  good <<~RUBY
    FileUtils.rm("tmp/session.txt")
    system("rm", "-f", "build/main.o")
    File.delete(path) if confirmed?(path)
    %w[.mp3 .job].each { |ext| FileUtils.rm_f(base + ext) }
  RUBY
end
