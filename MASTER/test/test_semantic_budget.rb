# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/fix_loop"
require "fix/scanner"

# What the pass runner lends the stream, cut down: a repair that records the file it was handed.
module SemanticBudgetHarness
  def repair_file(path, *handed)
    @repairs << path
    StreamStage::STREAMED_LOCK.synchronize { handed.last.streamed << [handed[-2], "CHEAP"] }
    1
  end

  def resolve_violations(raw) = raw.map(&:to_h)
  def reload_due? = false
  def report_skip_breakdown(*, **); end
  def emit_topology(*); end
  def circuit_open? = false
  def llm_stage_resources_ok?(_pass) = true

  # Inside Master::ROOT, so the semantic answers are kept (FindingCache records repo-relative paths);
  # never written, since the processor is handed the text.
  def files(count = 6) = Array.new(count) { |n| File.join(Master::ROOT, "lib", "semantic_budget_probe_#{n}.rb") }

  def repaired = Array.new(@repairs.size) { @repairs.pop }.uniq

  def pass_semantic_budget = @budget.dup

  def from_now(seconds) = Time.at(Process.clock_gettime(Process::CLOCK_REALTIME) + seconds)

  StreamStage = Master::Fix::FixLoop::PassRunner::StreamStage
end

# A requested /fix shares one model lane between the semantic reads and the repairs. Read inline,
# a minute and a half a file, the reads filled the pass and no file was ever repaired. The stream
# now reads the corpus mechanically, queues every cheap finding for repair, and then makes a
# budget's worth of the reads it put off; later passes read the rest.
class TestSemanticBudget < Minitest::Test
  include Master::Fix::FixLoop::PassRunner::StreamStage
  include SemanticBudgetHarness

  Finding = Master::Review::Scan::Finding
  Budget = Master::Fix::FixLoop::PassRunner::StreamStage::SemanticBudget
  Rule = Struct.new(:id)
  CODE = "x = 1\n"

  # A cheap finding on every file, so every file is due a semantic read and a repair.
  class CheapLaw
    def self.reads_beyond_file? = false
    def id = "CHEAP"
    def check(_code, path:) = [Finding.build(law: "CHEAP", message: "cheap #{File.basename(path)}", line: 1)]
  end

  # The model tier, slow as a lane is.
  class SlowModel
    attr_reader :calls

    def self.reads_beyond_file? = true

    def initialize(delay)
      @delay = delay
      @calls = []
    end

    def id = "MODEL"
    def set_agent(_agent) = nil

    def check(_code, path:)
      sleep @delay
      @calls << path
      [Finding.build(law: "MODEL", message: "drift in #{File.basename(path)}", line: 2)]
    end
  end

  class NullCommitter
    def commit_if_dirty(*, **) = nil
  end

  LawOrder = Struct.new(:rules) do
    def ordered(violation_counts:) = rules
  end

  def setup
    @root = Dir.mktmpdir("semantic-budget")
    @cache_was = ENV.fetch("MASTER_SCAN_CACHE", nil)
    ENV["MASTER_SCAN_CACHE"] = "1"
    @model = SlowModel.new(0.4)
    @processor = Master::Fix::Scan::FileProcessor.new(cache_root: @root)
    @scan_phase = Master::Fix::ScanPhase.new(scanner: @processor, root: @root)

    @committer = NullCommitter.new
    @law_order = LawOrder.new([Rule.new("CHEAP")])
    @violation_counts = Hash.new(0)
    @repairs = Queue.new
    @budget = Budget.new(2, 60, 0, 0.0)
  end

  def teardown
    @cache_was.nil? ? ENV.delete("MASTER_SCAN_CACHE") : ENV["MASTER_SCAN_CACHE"] = @cache_was
    FileUtils.remove_entry(@root)
  end

  def test_every_cheap_finding_is_repaired_before_the_deadline_however_slow_the_model
    corpus = files
    found, = streaming_observation(corpus, @root, 1, from_now(1.5))

    assert_equal corpus.sort, repaired.sort, "the model reads must not hold the repairs past the deadline"
    assert_equal 2, @model.calls.size, "the pass reads only its budget's worth"
    assert_equal 2, found.count { |row| row[:law] == "MODEL" }
  end

  def test_the_seconds_budget_stops_the_reads_too
    @budget = Budget.new(10, 0.5, 0, 0.0)
    streaming_observation(files, @root, 1, from_now(30))

    assert_equal 2, @model.calls.size
  end

  def test_preview_reads_only_its_semantic_budget_and_does_not_advance_the_cursor
    corpus = files

    found = preview_violations(corpus)

    assert_equal 2, @model.calls.size, "preview must obey the same bounded read allowance"
    assert_equal 4, semantic_pending.size, "unread semantic files must be visible as pending"
    assert_equal 2, found.count { |row| row[:law] == "MODEL" }
    refute File.exist?(Master::Fix::FixLoop::StreamCursor.file(@root)),
           "a read-only preview must not advance the persistent semantic cursor"
  end

  def test_later_passes_read_what_earlier_ones_left_and_every_file_is_read_once
    corpus = files
    streaming_observation(corpus, @root, 1, from_now(30))
    assert_equal 4, semantic_pending.size

    2.times { |n| streaming_observation(corpus, @root, n + 2, from_now(30)) }

    assert_equal corpus.sort, @model.calls.sort
    assert_empty semantic_pending
  end

  def test_the_order_resumes_past_the_last_file_read_and_wraps
    paths = %w[a.rb b.rb c.rb d.rb].map { |name| File.join(@root, name) }
    Master::Fix::FixLoop::StreamCursor.mark_semantic(@root, paths[2])

    order = Master::Fix::FixLoop::StreamCursor.semantic_order(@root, paths.reverse)

    assert_equal [paths[3], paths[0], paths[1], paths[2]], order
  end

  def test_another_thread_still_reads_inline_while_the_scan_defers
    put_off = []
    other = nil
    @processor.deferring_semantic(put_off) do
      other = Thread.new { scan(files(1).first) }.value
    end

    assert_empty put_off
    assert_includes other.map { |finding| finding[:law] }, "MODEL"
  end

  private

  def scan(path) = @processor.apply_laws(code: CODE, ast: nil, path:, law_set: [CheapLaw.new, @model])

  def violations_for(path)
    scan(path).map do |finding|
      { law: finding[:law], line: finding[:line], message: finding[:message], severity: :warning, file: path }
    end
  end
end

require_relative "test_helper"
require "tmpdir"
require "unwrap_error"
require "io/semantic_cache"

# The cache runs before the phantom guard judges the response, so storing a
# degenerate one makes it the permanent answer to that prompt: every identical
# question replays it, trips the same detector, and PhantomRecovery's ladder —
# which counts consecutive phantoms — reaches halt with no clean response in
# between to reset it.
#
# Measured on vm23 before this: the same question answered correctly on a cache
# miss, then halted on the second and third ask.
class TestSemanticCachePhantoms < Minitest::Test
  # 60 characters, four times over — comfortably past "same 60-char span repeats
  # >= 3 times" in data/laws.yml.
  SPAN = ("the quick brown fox jumps over the lazy dog and keeps going ")
  LOOPING = SPAN * 4
  CLEAN = "Done. The queue drained 22 jobs and none failed."

  def with_cache
    Dir.mktmpdir do |root|
      yield Master::Io::SemanticCache.new(root:, ttl: 600)
    end
  end

  # Guard the guard: if this text stopped being detectable the test below would
  # pass while measuring nothing.
  def test_the_fixture_is_actually_a_phantom
    refute_nil Master::PhantomRecovery.detect(LOOPING), "the looping fixture is not detected as a phantom"
    assert_nil Master::PhantomRecovery.detect(CLEAN), "the clean fixture is detected as a phantom"
  end

  def test_a_clean_response_is_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("what drained", "m1") { calls += 1; CLEAN } }

      assert_equal 1, calls, "a clean response was not served from cache on the second ask"
    end
  end

  def test_a_degenerate_response_is_not_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("what heter du", "m1") { calls += 1; LOOPING } }

      assert_equal 2, calls,
                   "a phantom response was cached, so the next identical question replays it and the " \
                   "consecutive-phantom ladder climbs to a halt"
    end
  end

  # The refusal must be about the content, not about the prompt: the same prompt
  # must cache normally once the model stops looping.
  def test_the_same_prompt_caches_once_the_response_is_clean
    with_cache do |cache|
      cache.fetch("hva heter du", "m1") { LOOPING }

      calls = 0
      2.times { cache.fetch("hva heter du", "m1") { calls += 1; CLEAN } }

      assert_equal 1, calls, "a prompt that once produced a phantom can never be cached again"
    end
  end

  # An unfamiliar result shape loses caching rather than being skipped silently.
  def test_an_unreadable_result_shape_is_still_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("odd", "m1") { calls += 1; { some: "structure" } } }

      assert_equal 1, calls, "a result this cannot read as text stopped being cached"
    end
  end
end

require_relative "test_helper"
require "review/scan/law_tree"
require "tmpdir"
require "fileutils"

# The semantic disk cache lets an unattended chunked run resume its verdicts
# instead of re-paying every model call after a process restart (2026-11-10:
# the in-process cache died with each chunk and OPENBSD re-paid ~3 minutes of
# model calls for the same file every chunk, so passes never converged).
class TestSemanticDiskCache < Minitest::Test
  def semantic_law_class = Master::Review::Scan::Laws::SemanticLaw

  def with_cache_file
    Dir.mktmpdir("semantic-cache") do |dir|
      path = File.join(dir, "semantic_cache.jsonl")
      ENV["MASTER_SEMANTIC_CACHE"] = "1"
      ENV["MASTER_SEMANTIC_CACHE_PATH"] = path
      yield path
    end
  ensure
    ENV["MASTER_SEMANTIC_CACHE"] = "0"
    ENV.delete("MASTER_SEMANTIC_CACHE_PATH")
  end

  def agent_that_counts(replies)
    calls = 0
    replies = replies.transform_keys(&:to_sym)
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      calls += 1
      replies.fetch(operation) { raise "unexpected operation #{operation}" }
    end
    [agent, -> { calls }]
  end

  def agent_that_refuses
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, operation:| raise "model must not be called (#{operation})" }
    agent
  end

  def with_source(code)
    Dir.mktmpdir("semantic-source") do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, code)
      yield path
    end
  end

  def one_law_id
    @one_law_id ||= semantic_law_class.new(agent: nil).send(:laws_for, nil).keys.first
  end

  def test_second_instance_serves_cached_verdicts_without_model_calls
    with_cache_file do
      with_source("value = 1\n") do |path|
        code = File.read(path)
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "#{one_law_id}:3:a cached breach",
          "scan_semantic_opportunities" => "NONE",
        )
        findings = semantic_law_class.new(agent:).check(code, path:)
        assert_equal 1, findings.size
        assert_equal 2, calls.call, "one call per stream on a cold cache"

        again = semantic_law_class.new(agent: agent_that_refuses).check(code, path:)
        assert_equal 1, again.size, "the cached verdict must survive the process restart"
        assert_equal one_law_id, again.first.law.to_s
        assert_equal 3, again.first.line
        assert_equal 0, calls.call - 2, "a warm disk cache must not call the model"
      end
    end
  end

  def test_changed_code_misses_the_cache
    with_cache_file do
      with_source("value = 1\n") do |path|
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        semantic_law_class.new(agent:).check(File.read(path), path:)
        assert_equal 2, calls.call

        File.write(path, "value = 2\n")
        semantic_law_class.new(agent:).check(File.read(path), path:)
        assert_equal 4, calls.call, "a changed source must be judged again, not read from cache"
      end
    end
  end

  def test_a_clean_verdict_is_cached_as_an_empty_result_not_a_miss
    with_cache_file do
      with_source("value = 1\n") do |path|
        code = File.read(path)
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        assert_equal [], semantic_law_class.new(agent:).check(code, path:)
        assert_equal 2, calls.call

        assert_equal [], semantic_law_class.new(agent: agent_that_refuses).check(code, path:)
        assert_equal 2, calls.call, "CLEAN must be cached, not re-asked"
      end
    end
  end

  def test_disabled_cache_never_touches_the_disk
    Dir.mktmpdir("semantic-cache-off") do |dir|
      path = File.join(dir, "semantic_cache.jsonl")
      ENV["MASTER_SEMANTIC_CACHE"] = "0"
      ENV["MASTER_SEMANTIC_CACHE_PATH"] = path
      with_source("value = 1\n") do |source|
        agent, = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        assert_equal [], semantic_law_class.new(agent:).check(File.read(source), path:)
        refute File.exist?(path), "a disabled cache must not write"
      end
    end
  ensure
    ENV["MASTER_SEMANTIC_CACHE"] = "0"
    ENV.delete("MASTER_SEMANTIC_CACHE_PATH")
  end
end

require_relative "test_helper"

class TestSemanticFingerprintAgreement < Minitest::Test
  SAMPLE = <<~RUBY
    class Sample
      CONST = 1

      def foo
        1
      end
    end
  RUBY

  # The actual bug, not a hypothetical: FileProcessor (stamps a fingerprint
  # onto every finding when it's first scanned) and RepairLoop::FixVerification
  # (recomputes one just before applying a fix, to detect whether the file
  # changed in between) used to be two independently-maintained copies of
  # the same formula. They quietly drifted -- FileProcessor's included an
  # extra `ast_present` key fix_verification's didn't -- so Marshal.dump
  # produced different bytes for the same code, and RepairLoop#fingerprint_matches?
  # returned false for every file, every time, forever, regardless of
  # whether anything had actually changed. Found live via repair_loop.rb's
  # skip_breakdown trace: 100% of skipped violations attributed to
  # fingerprint across every rule in a full-repo /fix pass, 0% to confidence.
  def test_file_processor_and_fix_verification_compute_identical_fingerprints
    from_file_processor = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)
    from_fix_verification = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)

    assert_equal from_file_processor, from_fix_verification
  end

  def test_a_real_scan_finding_carries_the_same_fingerprint_a_fresh_read_would_compute
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, SAMPLE)

      scanner = Master::Fix::Scanner.build(root: Master::ROOT)
      result = scanner.scan(path)
      assert result.ok?, "expected scan to succeed"

      finding = result.value!.first
      refute_nil finding, "expected at least one finding for a fixture this messy"

      fresh = Master::Review::Scan::SemanticFingerprint.for(File.read(path, encoding: "UTF-8"))
      assert_equal fresh, finding[:fingerprint]
    end
  end

  def test_differs_when_code_actually_changes
    before = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)
    after = Master::Review::Scan::SemanticFingerprint.for(SAMPLE + "\n# a new line\n")

    refute_equal before, after
  end
end

require_relative "test_helper"

# Fuzzy semantic cache: paraphrased prompts (high cosine) hit; dissimilar miss; disabled = no-op.
class TestSemanticIndex < Minitest::Test
  class FakeEmbedder
    def initialize(vectors, enabled: true)
      @vectors = vectors
      @enabled = enabled
    end

    def enabled? = @enabled
    def embed(text) = @vectors[text]

    def cosine(a, b)
      dot = a.zip(b).sum { |x, y| x * y }
      magnitude = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |y| y * y })
      magnitude.zero? ? 0.0 : dot / magnitude
    end
  end

  def make_semantic_index(vectors, enabled: true, threshold: 0.92)
    embedder = FakeEmbedder.new(vectors, enabled:)
    Master::Io::SemanticIndex.new(embedder:, threshold:)
  end

  def test_paraphrase_is_a_near_hit
    idx = make_semantic_index({ "what is X" => [1.0, 0.0, 0.0], "whats X" => [0.99, 0.02, 0.0] })
    idx.remember("what is X", "ANSWER")
    assert_equal "ANSWER", idx.nearest("whats X")
  end

  def test_dissimilar_prompt_misses
    idx = make_semantic_index({ "what is X" => [1.0, 0.0, 0.0], "unrelated" => [0.0, 1.0, 0.0] })
    idx.remember("what is X", "ANSWER")
    assert_nil idx.nearest("unrelated")
  end

  def test_fetch_computes_on_miss_then_reuses
    idx = make_semantic_index({ "q1" => [1.0, 0.0], "q1-ish" => [0.999, 0.01] })
    calls = 0
    first = idx.fetch("q1") { calls += 1; "COMPUTED" }
    second = idx.fetch("q1-ish") { calls += 1; "SHOULD_NOT_RUN" }
    assert_equal "COMPUTED", first
    assert_equal "COMPUTED", second
    assert_equal 1, calls
  end

  def test_scope_prevents_cross_model_near_hits
    idx = make_semantic_index(
      { "same question A" => [1.0, 0.0], "same question B" => [0.999, 0.01] },
    )
    idx.remember("same question A", "MODEL_A", scope: "model-a")

    assert_nil idx.nearest("same question B", scope: "model-b")
    assert_equal "MODEL_A", idx.nearest("same question B", scope: "model-a")
  end

  def test_disabled_embedder_is_a_noop
    idx = make_semantic_index({ "q" => [1.0] }, enabled: false)
    idx.remember("q", "ANSWER")
    assert_nil idx.nearest("q")
  end
end

require_relative "test_helper"
require "tmpdir"
require "fix/scanner"

# A model read of unchanged text is replayed, clean or not, so a /fix run asks the model only about what
# changed. An inconclusive read is never kept: an outage must not stand in for an answer.
class TestSemanticReplay < Minitest::Test
  Finding = Master::Review::Scan::Finding
  PATH = File.join(Master::ROOT, "lib", "semantic_replay_probe.rb")

  # A cheap finding, so the file is due a semantic read.
  class CheapLaw
    def self.reads_beyond_file? = false
    def id = "CHEAP"
    def check(_code, path:) = [Finding.build(law: "CHEAP", message: "cheap #{File.basename(path)}", line: 1)]
  end

  class ModelLaw
    attr_reader :calls

    def self.reads_beyond_file? = true

    def initialize(answer) = (@answer = answer) && (@calls = 0)
    def id = "MODEL"
    def set_agent(_agent) = nil

    def check(_code, path:)
      @calls += 1
      if @answer == :inconclusive
        raise Master::Review::Scan::Detector::SemanticAssessmentInconclusive,
              "semantic assessment INCONCLUSIVE: lane down"
      end

      [Finding.build(law: "MODEL", message: "drift in #{File.basename(path)}", line: 2)]
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @was = ENV.fetch("MASTER_SCAN_CACHE", nil)
    ENV["MASTER_SCAN_CACHE"] = "1"
  end

  def teardown
    @was.nil? ? ENV.delete("MASTER_SCAN_CACHE") : ENV["MASTER_SCAN_CACHE"] = @was
    FileUtils.remove_entry(@dir)
  end

  def scan(law, code: "x = 1\n")
    processor = Master::Fix::Scan::FileProcessor.new(cache_root: @dir)
    processor.apply_laws(code:, ast: nil, path: PATH, law_set: [CheapLaw.new, law])
  end

  def test_law_definition_comes_from_the_scanner_target_root
    target = File.join(@dir, "project")
    FileUtils.mkdir_p(File.join(target, "law"))
    FileUtils.mkdir_p(File.join(target, "data"))
    File.write(File.join(target, "data", "laws.yml"), "{}\n")
    File.write(File.join(target, "law", "definition.rb"), "module Law; end\n")
    processor = Master::Fix::Scan::FileProcessor.new(root: target, cache_root: @dir)

    assert_equal File.join(target, "law", "definition"),
                 processor.send(:law_definition_path, File.join(target, "law", "example.rb"))
  end

  def test_law_definition_falls_back_to_the_installed_master_root
    processor = Master::Fix::Scan::FileProcessor.new(root: @dir, cache_root: @dir)

    assert_equal File.join(Master::ROOT, "law", "definition"),
                 processor.send(:law_definition_path, File.join(@dir, "law", "example.rb"))
  end

  def test_a_read_with_findings_is_replayed_for_unchanged_text
    law = ModelLaw.new(:drift)
    first = scan(law)
    second = scan(law)

    assert_equal 1, law.calls
    assert_equal first, second
    assert_includes second.map { |finding| finding[:law] }, "MODEL"
  end

  def test_changed_text_is_read_again
    law = ModelLaw.new(:drift)
    scan(law)
    scan(law, code: "x = 2\n")

    assert_equal 2, law.calls
  end

  def test_an_inconclusive_read_is_asked_again
    law = ModelLaw.new(:inconclusive)
    2.times { scan(law) }

    assert_equal 2, law.calls
  end

  def test_an_inconclusive_read_is_not_repeated_by_the_same_processor
    law = ModelLaw.new(:inconclusive)
    processor = Master::Fix::Scan::FileProcessor.new(cache_root: @dir)

    2.times do
      processor.apply_laws(code: "x = 1\n", ast: nil, path: PATH, law_set: [CheapLaw.new, law])
    end

    assert_equal 1, law.calls
    assert_equal 1, processor.semantic_gaps.size
  end
end

require_relative "test_helper"
require "date"

# A requested /fix reads a rotating tenth of the clean files semantically, so every file is read
# once across ten days and no run reads them all.
class TestSemanticRotation < Minitest::Test
  # A processor pinned to one day and one sample rate.
  class OnDay < Master::Fix::Scan::FileProcessor
    def on(day) = tap { @day = day }

    def rotation_day = @day
    def semantic_sample = 0.1
    def due?(path, findings: []) = semantic_due?(findings, path)
  end

  def test_ten_days_read_every_file_exactly_once
    paths = Array.new(200) { |n| "lib/file_#{n}.rb" }

    reads = (1..10).flat_map do |day|
      processor = OnDay.new.on(day)
      paths.select { |path| processor.due?(path) }
    end

    assert_equal paths.sort, reads.sort
  end

  def test_a_file_with_a_finding_is_always_read
    processor = OnDay.new.on(1)
    paths = Array.new(50) { |n| "lib/f#{n}.rb" }

    assert(paths.all? { |path| processor.due?(path, findings: [{ law: "CQS" }]) })
  end

  def test_rotation_covers_ten_consecutive_dates_across_new_year
    paths = Array.new(200) { |n| "lib/new_year_#{n}.rb" }
    dates = (Date.new(2026, 12, 28)..Date.new(2027, 1, 6)).to_a
    reads = dates.flat_map do |date|
      processor = OnDay.new.on(date.jd)
      paths.select { |path| processor.due?(path) }
    end

    assert_equal paths.sort, reads.sort
    source = File.read(File.expand_path("../lib/fix/scan/file_processor.rb", __dir__))
    assert_includes source, "def rotation_day = Date.today.jd"
  end
end
