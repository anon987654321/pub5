# frozen_string_literal: true

# The census Law: each operation that touches the outside has one
# implementation, in core/. pub4 had 23 files calling the HTTP library
# directly, 3 atomic writes, 77 YAML-loading call sites and 1,711 env reads.
#
# The patterns are assembled from pieces so this file does not match itself.
# rails/ and studio/ arrive moved, not rewritten (PLAN.md section 14); they
# keep their framework's idioms until P3 decides each one. laws/pub4/ is
# pub4's Law Ruby moved the same way by `bin/master port-laws` (P2): its
# fixtures spell the calls they forbid, and the pub4 helpers beside them
# still read ENV and YAML themselves. A Law cleaned out of laws/pub4/ into
# laws/ is judged again.
Law.define(:ONE_IMPLEMENTATION_PER_OPERATION) do
  operations = {
    "http" => ["Net" "::HTTP", "URI" ".open", "Open" "URI"],
    "file write" => ['File\.(bin)?write\b', 'IO\.(bin)?write\b', 'File\.open\([^)]*,\s*["\x27][wa]'],
    "env" => ['\bENV\s*\[', '\bENV\.(fetch|key\?|to_h|each|slice|values_at)\b'],
    "exec" => ["Open" '3\.', 'IO\.popen\b', 'Process\.spawn\b', '(?<![\w.:])system\(', '(?<![\w.:])spawn\('],
    "yaml load" => ['YAML\.(safe_|unsafe_)?load(_file)?\b', 'Psych\.(safe_)?load']
  }.transform_values { |sources| Regexp.union(sources.map { |s| Regexp.new(s) }) }
  owners = { "http" => "Core::HTTP", "file write" => "World#write (Core::Atomic)", "env" => "Core::Knobs",
             "exec" => "World#exec or World#git", "yaml load" => "Core::Registry" }
  exempt = %r{\A(core|rails|studio|laws/pub4)/}

  source "PLAN.md sections 4 and 11 (M1); OpenBSD's one canonical implementation per operation"
  languages :ruby
  check do |text, file|
    next [] if file.match?(exempt)

    text.each_line.with_index(1).flat_map do |line, number|
      next [] if line.match?(/\A\s*#/)

      operations.filter_map do |operation, pattern|
        finding(line: number, message: "#{operation} outside core; use #{owners.fetch(operation)}") if line.match?(pattern)
      end
    end
  end
  fix "Call the core owner named in the finding instead of the library."
  bad ["Net" "::HTTP.get(URI(url))\n", "File" ".write(path, text)\n", "token = ENV" "[%q(KEY)]\n",
       "Open" "3.capture2(%q(git), %q(status))\n", "YAML" ".load_file(path)\n"]
  good ["Core::HTTP.request(:get, url)\n", "world.write(path, text)\n", "Core::Knobs.fetch(%q(PUB5_WRITER))\n",
        "# the Net" "::HTTP client lives in core/http.rb\n"]
end
