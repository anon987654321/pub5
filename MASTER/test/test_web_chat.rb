# frozen_string_literal: true

require_relative "test_helper"

class TestWebChat < Minitest::Test
  class FakeNode
    attr_reader :text

    def initialize(page, text = "", attributes = {})
      @page = page
      @text = text
      @attributes = attributes
    end

    def attribute(name) = @attributes[name]

    def focus = self

    def type(text, *)
      @page.submit(text)
      self
    end

    def property(_name) = text
  end

  class FakePage
    attr_reader :url, :prompt, :screenshots

    PNG = ("\x89PNG\r\n\x1a\n".b + ("test-pixels" * 8).b).freeze

    def initialize(answer: "Fresh answer.", repeated: false)
      @answer = answer
      @repeated = repeated
      @submitted = false
      @reply_reads = 0
      @screenshots = []
      @input = FakeNode.new(self)
    end

    def go_to(url)
      @url = url
    end

    def at_css(selector)
      selector.include?("textarea") || selector.include?("contenteditable") ? @input : nil
    end

    def css(_selector)
      @reply_reads += 1
      old = FakeNode.new(self, "Earlier answer.", "data-message-author-role" => "assistant")
      return [old] unless @submitted

      user = FakeNode.new(self, @prompt, "class" => "message user")
      return [old, user] if @reply_reads < 3

      answer = @repeated ? "Earlier answer." : @answer
      [old, user, FakeNode.new(self, answer, "data-message-author-role" => "assistant")]
    end

    def submit(text)
      @submitted = true
      @prompt = text
    end

    def network = self

    def wait_for_idle(timeout:)
      true
    end

    def screenshot(encoding:, format:)
      @screenshots << { submitted: @submitted, format: }
      PNG
    end
  end

  def build_chat
    chat = Master::Io::WebChat.allocate
    chat.instance_variable_set(:@provider, "chatgpt")
    chat.instance_variable_set(:@config, {
      "url" => "https://chatgpt.com/",
      "input_selector" => "textarea",
      "reply_selector" => "div[data-message-author-role='assistant']",
      "timeout" => 3,
    })
    chat.define_singleton_method(:timeout_seconds) { 3 }
    chat.define_singleton_method(:sleep) { |seconds| Thread.pass }
    chat
  end

  def test_browser_chat_returns_the_new_answer_and_captures_each_visible_stage
    chat = build_chat
    page = FakePage.new

    result = chat.send(:converse, page, "What is new?")

    assert_equal "Fresh answer.", result
    assert_equal "What is new?", page.prompt
    assert_equal [
      { stage: "loaded", submitted: false },
      { stage: "submitted", submitted: true },
      { stage: "answered", submitted: true },
    ], chat.screenshot_evidence.map { |row| { stage: row.fetch(:stage), submitted: page.screenshots.shift.fetch(:submitted) } }
  end

  def test_identical_repeated_answer_is_valid_when_a_new_assistant_turn_appears
    chat = build_chat
    page = FakePage.new(repeated: true)

    assert_equal "Earlier answer.", chat.send(:converse, page, "Ask the same thing again")
    assert_equal %w[loaded submitted answered], chat.screenshot_evidence.map { |row| row.fetch(:stage) }
  end

  def test_broad_container_with_the_prompt_and_answer_is_not_an_assistant_reply
    chat = build_chat
    chat.instance_variable_set(:@submitted_text, "What is new?")
    container = FakeNode.new(nil, "What is new? Fresh answer.")

    refute chat.send(:reply_candidate?, container)
  end

  def test_screenshot_files_and_directory_are_private
    require "tmpdir"
    old = ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"]
    Dir.mktmpdir("master-web-chat-test") do |root|
      target = File.join(root, "captures")
      ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"] = target
      chat = build_chat
      chat.instance_variable_set(:@screenshot_evidence, [])
      chat.send(:capture_screenshot, FakePage.new, stage: "loaded")
      path = chat.screenshot_evidence.fetch(0).fetch(:path)

      assert_equal 0o700, File.stat(target).mode & 0o777
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  ensure
    old.nil? ? ENV.delete("MASTER_WEB_CHAT_SCREENSHOT_DIR") : ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"] = old
  end

  def test_screenshots_are_not_saved_without_an_explicit_directory
    old = ENV.delete("MASTER_WEB_CHAT_SCREENSHOT_DIR")
    chat = build_chat
    chat.instance_variable_set(:@screenshot_evidence, [])
    page = FakePage.new

    chat.send(:capture_screenshot, page, stage: "loaded")

    evidence = chat.screenshot_evidence.fetch(0)
    assert_equal "loaded", evidence.fetch(:stage)
    assert_operator evidence.fetch(:bytes), :>, 64
    assert_match(/\A[0-9a-f]{64}\z/, evidence.fetch(:sha256))
    refute evidence.key?(:path)
  ensure
    old.nil? ? ENV.delete("MASTER_WEB_CHAT_SCREENSHOT_DIR") : ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"] = old
  end

  def test_ferrum_process_start_timeout_is_classified_as_timeout
    error_class = Class.new(StandardError)
    error_class.define_singleton_method(:name) { "Ferrum::ProcessTimeoutError" }
    error = error_class.new("Browser did not produce websocket url within 45 seconds")

    assert_equal :timeout, Master::Io::WebChat.failure_category(error)
  end

  def test_ferrum_pending_connections_deadline_is_classified_as_timeout
    error_class = Class.new(StandardError)
    error_class.define_singleton_method(:name) { "Ferrum::PendingConnectionsError" }
    error = error_class.new("main frame still has pending connections")

    assert_equal :timeout, Master::Io::WebChat.failure_category(error)
  end

  def test_ferrum_binary_missing_skips_the_browser_lane
    error_class = Class.new(StandardError)
    error_class.define_singleton_method(:name) { "Ferrum::BinaryNotFoundError" }

    assert_equal :model_missing, Master::Io::WebChat.failure_category(error_class.new("Chrome missing"))
  end

  def test_ferrum_dead_browser_is_offline
    error_class = Class.new(StandardError)
    error_class.define_singleton_method(:name) { "Ferrum::DeadBrowserError" }

    assert_equal :offline, Master::Io::WebChat.failure_category(error_class.new("browser process exited"))
  end

  def test_dispatcher_timeout_is_not_relabelled_as_web_chat_provider_error
    chat = build_chat
    chat.define_singleton_method(:enabled?) { true }
    chat.define_singleton_method(:with_browser) { |_unused = nil, &block| raise Timeout::Error }
    assert_raises(Timeout::Error) { chat.ask(prompt: "ping") }
  end

  def test_web_chat_own_timeout_is_reported_as_provider_error
    chat = build_chat
    chat.define_singleton_method(:enabled?) { true }
    chat.define_singleton_method(:with_browser) { raise Master::Io::WebChat::RequestTimeout }
    assert_raises(Master::Io::WebChat::ProviderError) { chat.ask(prompt: "ping") }
  end

  def test_provider_browser_deadlines_fit_inside_the_free_lane_deadline
    providers = Master.models_config.dig("ferrum_web_chat", "providers")
    limit = Master::Io::LaneSelection.free_call_timeout_s

    refute_empty providers
    providers.each do |name, config|
      assert_operator config.fetch("timeout").to_i, :<=, limit,
                      "#{name} browser timeout must not outlive the dispatcher call ceiling"
    end
  end

  def test_ferrum_timeout_is_below_the_dispatcher_free_lane_ceiling
    chat = build_chat
    assert_equal 3, chat.send(:ferrum_timeout_s), "a provider-specific shorter limit remains authoritative"

    chat.define_singleton_method(:timeout_seconds) { 120 }
    assert_equal Master::Io::WebChat::FERRUM_TIMEOUT_S, chat.send(:ferrum_timeout_s)
    assert_operator chat.send(:ferrum_timeout_s), :<, 60
  end

  def test_native_ferrum_async_quit_thread_is_used_for_profile_cleanup
    chat = build_chat
    release = Queue.new
    native_worker = Thread.new { release.pop }
    # Named before the block: a local assigned inside it is out of scope in
    # the ensure below, which joins both workers.
    cleanup_worker = nil
    browser = Object.new
    browser.define_singleton_method(:quit) do |wait: true|
      raise "wait must be false" unless wait == false
      native_worker
    end

    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      chat.send(:cleanup_browser, browser)
      cleanup_worker = Master::Io::WebChat::PROFILE_CLEANUP[:thread]
      assert cleanup_worker&.alive?, "the lease tracks the native cleanup worker"
      assert_raises(Master::Io::WebChat::ProviderError) do
        chat.send(:refuse_if_cleanup_pending!)
      end
    end

    release << true
    native_worker.join(1)
    cleanup_worker&.join(1)
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      chat.send(:refuse_if_cleanup_pending!)
      assert_nil Master::Io::WebChat::PROFILE_CLEANUP[:thread]
    end
  ensure
    release << true if release
    native_worker&.join(1)
    cleanup_worker&.join(1)
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      Master::Io::WebChat::PROFILE_CLEANUP[:thread] = nil
      Master::Io::WebChat::PROFILE_CLEANUP[:failed] = nil
    end
  end

  def test_failed_browser_cleanup_keeps_the_profile_unavailable
    chat = build_chat
    browser = Object.new
    browser.define_singleton_method(:quit) { raise IOError, "cleanup failed" }
    worker = nil

    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      chat.send(:cleanup_browser, browser)
      worker = Master::Io::WebChat::PROFILE_CLEANUP[:thread]
    end
    worker.join(1)

    assert_equal "IOError", Master::Io::WebChat::PROFILE_CLEANUP[:failed]
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      error = assert_raises(Master::Io::WebChat::ProviderError) do
        chat.send(:refuse_if_cleanup_pending!)
      end
      assert_match(/cleanup failed.*shared profile is unavailable until restart/, error.message)
    end
  ensure
    worker&.join(1)
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      Master::Io::WebChat::PROFILE_CLEANUP[:thread] = nil
      Master::Io::WebChat::PROFILE_CLEANUP[:failed] = nil
    end
  end

  def test_slow_browser_cleanup_does_not_block_and_prevents_profile_reuse
    chat = build_chat
    release = Queue.new
    browser = Object.new
    browser.define_singleton_method(:quit) { release.pop }
    worker = nil

    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      chat.send(:cleanup_browser, browser)
      worker = Master::Io::WebChat::PROFILE_CLEANUP.fetch(:thread)
      assert worker&.alive?, "the deliberately blocked quit must remain in its worker"
      assert_raises(Master::Io::WebChat::ProviderError) do
        chat.send(:refuse_if_cleanup_pending!)
      end
    end

    release << true
    worker.join(1)
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      chat.send(:refuse_if_cleanup_pending!)
      assert_nil Master::Io::WebChat::PROFILE_CLEANUP[:thread]
    end
  ensure
    release << true if release
    worker&.join(1)
    Master::Io::WebChat::PROFILE_MUTEX.synchronize do
      Master::Io::WebChat::PROFILE_CLEANUP[:thread] = nil
      Master::Io::WebChat::PROFILE_CLEANUP[:failed] = nil
    end
  end
end
