# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/rails/route_contracts"

class TestRouteContracts < Minitest::Test
  Response = Struct.new(:code, :headers, :body) do
    def [](name) = headers[name]
  end

  # minitest/mock is not installed here; swap the module function for the block.
  # Keywords are forwarded on their own: the signed-in fetch carries a cookie.
  def with_fetch(fake)
    original = RouteContracts.method(:fetch)
    RouteContracts.define_singleton_method(:fetch) { |*args, **opts| fake.call(*args, **opts) }
    yield
  ensure
    RouteContracts.define_singleton_method(:fetch, original)
  end

  # Same swap for the sign-in POST.
  def with_post(fake)
    original = RouteContracts.method(:post)
    RouteContracts.define_singleton_method(:post, fake)
    yield
  ensure
    RouteContracts.define_singleton_method(:post, original)
  end

  def html_response(body) = Response.new("200", { "Content-Type" => "text/html; charset=utf-8" }, body)

  PAGE = File.read(File.join(__dir__, "fixtures", "post_page.html"))

  def test_a_page_records_title_heading_landmarks_and_forms_with_ids_normalised
    row = RouteContracts.describe(html_response(PAGE))
    assert_equal 200, row["status"]
    assert_equal "text/html", row["type"]
    assert_equal "Post N - brgen", row["title"]
    assert_equal "Hei Bergen", row["heading"]
    assert_equal %w[header nav main form], row["landmarks"]
    assert_equal ["/posts/N/comments"], row["forms"]
  end

  def test_a_byte_body_records_readable_utf8_text
    body = "<title>Kategorier - BSDports</title><h1>Åpne</h1>".b
    row = RouteContracts.describe(html_response(body))
    assert_equal Encoding::UTF_8, row["title"].encoding
    refute_includes YAML.dump(row), "!binary"
  end

  def test_a_redirect_records_its_target_path_only
    response = Response.new("302", { "Location" => "https://brgen.no/session/new?return=7" }, "")
    row = RouteContracts.describe(response)
    assert_equal({ "status" => 302, "type" => "", "location" => "/session/new?return=N" }, row)
  end

  def test_compare_names_each_changed_field_and_each_missing_path
    expected = { "/a" => { "status" => 200, "title" => "A" }, "/gone" => { "status" => 200 } }
    actual = { "/a" => { "status" => 200, "title" => "B" }, "/new" => { "status" => 404 } }
    assert_equal [
      ["/a", 'title: "A" -> "B"'],
      ["/gone", "missing from the target"],
      ["/new", "not in the recorded contract"],
    ], RouteContracts.compare(expected, actual)
  end

  # brgen's verticals 404 on brgen.no and answer on their subdomain.
  def test_a_path_that_404s_on_the_primary_host_is_recorded_on_the_host_that_answers
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1", host: "brgen.no,markedsplass.brgen.no", user: nil)
    answers = { "brgen.no" => "404", "markedsplass.brgen.no" => "200" }
    fake = ->(_target, _path, host) { html_response("<title>Marked</title>").tap { |r| r.code = answers.fetch(host) } }
    with_fetch(fake) do
      row = RouteContracts.answer(target, "/listings", nil)
      assert_equal 200, row["status"]
      assert_equal "markedsplass.brgen.no", row["host"]
      assert_equal 404, RouteContracts.answer(target, "/listings", "brgen.no")["status"], "a pinned host is asked alone"
    end
  end

  def test_matching_contracts_have_no_differences
    same = { "/" => { "status" => 200, "landmarks" => %w[main] } }
    assert_empty RouteContracts.compare(same, same)
  end

  # Signed-in half: the cookie captured by the sign-in POST is replayed on the
  # recorded paths, one sign-in per host, and the cookie carries the host.
  def test_a_signed_in_run_signs_in_per_host_and_carries_the_cookie
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1",
                                        host: "brgen.no,markedsplass.brgen.no", user: %w[demo@brgen.no secret])
    signed_uses_cookie = []
    with_fetch(lambda do |_target, _path, _host, cookie: nil|
      signed_uses_cookie << cookie
      html_response("<title>Host</title>")
    end) do
      with_post(->(target, _path, _user, host) {
        Response.new("302", { "Set-Cookie" => "_brgen_session=#{host}" }, "").tap do |response|
          def response.get_fields(name) = [headers.fetch(name)]
        end
      }) do
        rows = RouteContracts.observe_signed(target, { "/a" => { "host" => "markedsplass.brgen.no" }, "/b" => {} })
        assert_equal %w[Host Host], rows.values.map { |row| row["title"] }
      end
    end

    assert signed_uses_cookie.first.to_s.include?("_brgen_session=markedsplass.brgen.no"),
           "the pinned host's cookie is replayed (#{signed_uses_cookie.first.inspect})"
    assert signed_uses_cookie.last.to_s.include?("_brgen_session=brgen.no"),
           "the primary host's cookie is replayed (#{signed_uses_cookie.last.inspect})"
  end

  def test_a_failed_sign_in_refuses_aloud_instead_of_recording_the_form
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1", host: nil, user: %w[demo@brgen.no wrong])
    with_post(->(*_args) { Response.new("200", {}, "<form>") }) do
      error = assert_raises(SystemExit) { RouteContracts.sign_in(target, "brgen.no") }

      assert_match(/sign-in failed/, error.message)
    end
  end

  def test_paths_skip_dynamic_segments_and_framework_routes
    paths = RouteContracts.paths("bsdports")
    refute_empty paths
    assert paths.none? { |path| path.include?(":") || path.start_with?("/rails/") }
  end
end
