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

  # Signed-in half: one sign-in per run on the primary host - the apps are one
  # monolith, so the session row is shared - and its cookie is replayed on the
  # recorded paths. A row's host pin survives the walk, so a check asks the
  # vertical's host, not the primary's.
  def test_a_signed_in_run_replays_one_cookie_across_every_host
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1",
                                        host: "brgen.no,markedsplass.brgen.no", user: %w[demo@brgen.no secret])
    hosts_for_rows = []
    with_fetch(->(_target, _path, host, cookie:) {
      hosts_for_rows << [host, cookie]
      html_response("<title>Host</title>")
    }) do
      with_post(->(_target, _path, _user, _host) {
        Response.new("302", { "Set-Cookie" => "_brgen_session=one" }, "").tap do |response|
          def response.get_fields(name) = [headers.fetch(name)]
        end
      }) do
        RouteContracts.instance_variable_set(:@signin, nil)
        rows = RouteContracts.observe_signed(target, { "/a" => { "host" => "markedsplass.brgen.no" }, "/b" => {} })
        assert_equal %w[markedsplass.brgen.no brgen.no], hosts_for_rows.map(&:first)
        assert_equal ["_brgen_session=one"] * 2, hosts_for_rows.map(&:last), "one cookie serves every host"
        assert_equal "markedsplass.brgen.no", rows.fetch("/a")["host"], "the host pin survives into the row"
        refute rows.fetch("/b")["host"], "an unpinned row stays unpinned"
      end
    end

    assert_equal 1, RouteContracts.instance_variable_get(:@signin).size, "one sign-in, not one per host"
  end

  # A member carrying an otp_secret is challenged at sign-in; the third
  # credential field names the base-32 secret, and the completing POST's
  # cookies are merged over the sign-in's: the walk must carry the
  # post-challenge session.
  def test_sign_in_completes_the_two_factor_challenge_and_merges_its_cookies
    cleared = Response.new("302", { "Location" => "/account", "Set-Cookie" => "_app_session=cleared; path=/" }, "")
    def cleared.get_fields(name) = [headers.fetch(name)]

    target = RouteContracts::Target.new(app: "amber", base: "http://127.0.0.1:1", host: nil,
                                        user: %w[demo@amber.test secret JBSWY3DPEHPK3PXP])
    with_fetch(->(*_args, **_opts) { html_response("<title>Challenge</title>") }) do
      original = RouteContracts.method(:challenge_code)
      RouteContracts.define_singleton_method(:challenge_code) { |*_args| cleared }
      begin
        with_post(->(_target, path, _user, _host) {
          if path == "/two_factor_setup"
            cleared
          else
            Response.new("302", { "Set-Cookie" => "session_id=one; path=/; _app_session=pending; path=/" }, "").tap do |response|
              def response.get_fields(name) = [headers.fetch(name)]
            end
          end
        }) do
          RouteContracts.instance_variable_set(:@signin, nil)
          cookie = RouteContracts.sign_in(target, nil)

          assert_includes cookie, "session_id=one", "the database session survives the merge"
          assert_includes cookie, "_app_session=cleared", "the challenge's cleared flag replaces the pending one"
        end
      ensure
        RouteContracts.define_singleton_method(:challenge_code, original)
      end
    end
  end

  # RFC 6238's SHA-1 vector at T=59: the last six digits of 94287082.
  def test_the_totp_helper_matches_the_reference_vector
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    assert_equal "287082", RouteContracts.totp_code(secret, 1)
  end

  def test_a_failed_sign_in_refuses_aloud_instead_of_recording_the_form
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1", host: nil, user: %w[demo@brgen.no wrong])
    with_post(->(*_args) { Response.new("200", {}, "<form>") }) do
      error = assert_raises(SystemExit) { RouteContracts.sign_in(target, "brgen.no") }

      assert_match(/sign-in failed/, error.message)
    end
  end

  # A rate-limited or wrong-password /session POST still answers 302 - to the
  # sign-in form, not the app. The instrument must refuse aloud; a guest
  # session walked as auth is exactly the contract a rewrite would then copy.
  def test_a_302_to_the_sign_in_form_refuses_instead_of_recording
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1", host: nil, user: %w[demo@brgen.no secret])
    with_post(->(*_args) { Response.new("302", { "Location" => "/session/new" }, "") }) do
      RouteContracts.instance_variable_set(:@signin, nil)
      error = assert_raises(SystemExit) { RouteContracts.sign_in(target, nil) }

      assert_match(/sign-in failed/, error.message)
    end
  end

  def test_paths_skip_dynamic_segments_and_framework_routes
    paths = RouteContracts.paths("bsdports")
    refute_empty paths
    assert paths.none? { |path| path.include?(":") || path.start_with?("/rails/") }
  end
end
