# frozen_string_literal: true

require_relative "test_helper"

# The 2026-08-22 outage class: master_container.rb calls into web services
# from OUTSIDE, nothing local boots the container, and a privatization that
# every suite blessed put ai.brgen.no in a boot loop. This pins the exact
# external surface the initializer and the TTS controller use — by reading
# the initializer for its calls and asserting each is a PUBLIC singleton
# method on the class it names, without booting Rails (TtsJob only needs a
# Rails.root stub to load).
class TestWebContainerSurface < Minitest::Test
  WEB = File.join(Master::ROOT, "web")

  def tts_job_class
    @tts_job ||= begin
      unless defined?(::Rails) && ::Rails.respond_to?(:root)
        rails = Module.new do
          def self.root = Pathname.new(Dir.tmpdir)
        end
        Object.const_set(:Rails, rails)
      end
      require "pathname"
      require "tmpdir"
      load File.join(WEB, "app/services/tts_job.rb") unless defined?(::TtsJob)
      ::TtsJob
    end
  end

  def test_browser_boot_does_not_construct_operator_runtime
    initializer = File.read(File.join(WEB, "config/initializers/master_container.rb"))
    builder = File.read(File.join(Master::ROOT, "lib/builder.rb"))
    web = builder.split("def build_web", 2).last.split("def warn_config_validation", 2).first

    assert_includes initializer, "Master::Builder.build_web"
    refute_includes initializer, "Master.bootstrap_container"
    refute_includes initializer, "start_scheduler"
    assert_includes web, "[Io::WebSearch.new"
    assert_includes web, "memory: nil"
    assert_includes web, "code_index: nil"
    assert_includes web, "browser_broker: nil"
    refute_includes web, "build_runtime"
    refute_includes web, "McpCoordinator"
  end

  def test_every_initializer_call_into_tts_job_is_public
    initializer = File.read(File.join(WEB, "config/initializers/master_container.rb"))
    controller = File.read(File.join(WEB, "app/controllers/tts_controller.rb"))
    called = (initializer + controller).scan(/\bTtsJob\.([a-z_]+[!?]?)/).flatten.uniq
    refute_empty called, "the callers stopped naming TtsJob - this test's detector went blind"
    called.each do |m|
      assert_includes tts_job_class.singleton_class.public_instance_methods, m.to_sym,
        "TtsJob.#{m} is called from outside (initializer/controller) but is not public - this is the 2026-08-22 boot-loop regression"
    end
  end
end
