# frozen_string_literal: true

require_relative "minitest_helper"
require "json"
require "stringio"
require_relative "../api"

# The shared machine boundary each STUDIO tool answers with `api '<json>'`.
# These exercise Studio::Api itself, against real handler callables, so the
# envelope, the capture and the error paths are proved without a provider.
class TestStudioApi < Minitest::Test
  def call(argv, actions, input: StringIO.new(""))
    output = StringIO.new
    status = Studio::Api.respond(actions, argv:, input:, output:)
    [status, JSON.parse(output.string)]
  end

  def test_requested_only_for_the_api_verb
    assert Studio::Api.requested?(["api", "{}"])
    refute Studio::Api.requested?([])
    refute Studio::Api.requested?(["--list"])
  end

  def test_ok_response_carries_the_handler_result
    status, body = call(["api", '{"action":"ping"}'], { "ping" => ->(_request) { { "pong" => true } } })

    assert_equal 0, status
    assert_equal true, body["ok"]
    assert_equal({ "pong" => true }, body["result"])
  end

  def test_error_response_reports_the_exception_and_exits_nonzero
    status, body = call(["api", '{"action":"boom"}'], { "boom" => ->(_request) { raise "nope" } })

    assert_equal 1, status
    assert_equal false, body["ok"]
    assert_match(/RuntimeError: nope/, body["error"])
  end

  def test_unknown_action_is_refused_and_names_the_known_ones
    status, body = call(["api", '{"action":"nope"}'], { "ping" => ->(_request) { 1 } })

    assert_equal 1, status
    assert_match(/unknown action "nope"/, body["error"])
    assert_match(/ping/, body["error"])
  end

  def test_request_is_read_from_stdin_when_no_argument_is_given
    status, body = call(["api"], { "ping" => ->(request) { request["who"] } },
                        input: StringIO.new('{"action":"ping","who":"ma"}'))

    assert_equal 0, status
    assert_equal "ma", body["result"]
  end

  def test_handler_arguments_reach_the_callable
    status, body = call(["api", '{"action":"echo","word":"hei"}'],
                        { "echo" => ->(request) { request["word"] } })

    assert_equal 0, status
    assert_equal "hei", body["result"]
  end

  def test_stdout_chatter_is_captured_under_output_rather_than_the_wire
    handler = lambda do |_request|
      puts "working"
      warn "careful"
      { "done" => true }
    end
    status, body = call(["api", '{"action":"work"}'], { "work" => handler })

    assert_equal 0, status
    assert_equal true, body["result"]["done"]
    assert_match(/working/, body["output"])
    assert_match(/careful/, body["output"])
  end

  def test_empty_request_is_refused
    status, body = call(["api"], {})

    assert_equal 1, status
    assert_equal false, body["ok"]
    assert_match(/empty API request/, body["error"])
  end

  def test_a_non_object_request_is_refused
    status, body = call(["api", "[1,2,3]"], {})

    assert_equal 1, status
    assert_match(/must be a JSON object/, body["error"])
  end
end
