# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "yaml"

# The browser has one WebGL particle renderer; the CLI retains its ASCII face.
class MasterWebFaceContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WEB = File.join(ROOT, "MASTER", "web")
  PUBLIC = File.join(WEB, "public")
  SOURCES = %w[face.part1.txt face.part2.txt face.part3.txt face_speech_runtime.js face_speech_playback.js face.part5.txt].freeze

  def read(*path) = File.read(File.join(*path))
  def view = @view ||= read(WEB, "app", "views", "chat", "index.html.erb")
  def manifest = @manifest ||= YAML.safe_load_file(File.join(WEB, "config", "face_assets.yml"))
  def tokens = @tokens ||= YAML.safe_load_file(File.join(ROOT, "MASTER", "data", "tokens.yml"), aliases: true)
  def ascii = tokens.dig("tokens", "face_interface", "ascii")

  def test_the_generated_runtime_names_its_parts_by_their_current_digest
    runtime = read(PUBLIC, "face.runtime.js")
    listed = runtime[/FACE_RUNTIME_SOURCES = (\[.*?\]);/m, 1]
    refute_nil listed, "face.runtime.js lost its source list"
    named = listed.scan(/"([^"?]+)\?v=([0-9a-f]{10})"/)

    assert_equal SOURCES, named.map(&:first), "the runtime concatenates six sources in this order; run rails assets:build_face_runtime"
    named.each do |name, digest|
      assert_equal Digest::SHA256.file(File.join(PUBLIC, name)).hexdigest[0, 10], digest, "#{name} changed since face.runtime.js was built; run rails assets:build_face_runtime"
    end
    assert_includes runtime, "do not edit by hand"
  end

  def test_retired_renderers_are_absent_from_the_browser
    %w[face_ascii.js face_2d_fallback.js].each do |name|
      refute File.exist?(File.join(PUBLIC, name)), name
      refute_includes view, name
      refute_includes manifest.values.flatten, name
    end
    refute_includes view, 'id="ascii-star"'
  end

  def test_particle_kernel_still_leads_every_face_consumer_and_ascii_is_not_an_eager_module
    assert_equal "particle_kernel.js", manifest.fetch("shell_blocking").first
    assert_operator view.index('asset_path("particle_kernel.js")'), :<, view.index('id="primer"')
    refute_includes manifest.fetch("face_eager"), "face_ascii.js", "it is a shell script; the bundle is not rebuilt for it"
    bundle = read(PUBLIC, "face.modules.bundle.js")

    refute_includes bundle, "MASTER_FACE_ASCII"
  end

  def test_face_stays_the_public_global_and_ascii_adds_no_second_one
    assert_includes read(PUBLIC, "face.part5.txt"), "window.MASTER_FACE = {"
    runtime = SOURCES.map { |name| read(PUBLIC, name) }.join
    refute_match(/MASTERFace\b/, runtime)
  end

  def test_browser_uses_one_webgl_renderer_and_requires_rendered_points
    part1 = read(PUBLIC, "face.part1.txt")
    part3 = read(PUBLIC, "face.part3.txt")
    assert_includes part1, "new THREE.WebGLRenderer("
    assert_includes part1, "renderer.info.render.points"
    assert_includes part3, "renderer.render(scene, camera)"
    assert_includes part3, "markFaceReady();"
    refute_match(/drawAsciiFace|waitForAsciiRenderer|_wantsAscii/, part1 + part3)
    refute_includes read(PUBLIC, "face_semantics.js"), "start2D"
  end

  def test_the_particle_head_uses_uniform_fixed_bitmap_points
    part2 = read(PUBLIC, "face.part2.txt")

    assert_match(/gl_PointSize\s*=\s*1\.0;/, part2)
    assert_includes part2, "vColor = vec3(clamp("
    assert_includes part2, "transparent: false, depthWrite: true, depthTest: true"
    refute_includes part2, "vec3(0.74,0.66,0.58)"
    refute_includes part2, "vec3(1.0,0.98,0.94)"
  end

  def test_face_has_no_secondary_decorative_orbit_population
    part3 = read(PUBLIC, "face.part3.txt")

    assert_includes part3, "function faceFieldSample(index, salt = 0)"
    refute_includes part3, "ensureOrbitalField"
    assert_includes part3, "frameRequest !== null"
  end

  def test_cli_glyph_contract_remains_printable_ascii
    assert_match(/\A[\x20-\x7e]{2,}\z/, ascii.fetch("chars"))
    assert_equal ascii.fetch("chars").chars.sort, ascii.fetch("ink").keys.sort
  end

  def test_browser_receives_the_face_contract_and_render_budget
    assert_includes view, 'window.MASTER_FACE_CONTRACT = <%= raw json_escape(Master.tokens.fetch("face_interface", {}).to_json) %>'
    budget = tokens.dig("tokens", "face_interface", "spatial", "budget")
    %w[active_fps idle_fps reduced_motion_fps].each { |key| assert_includes budget.keys, key }
  end

  def test_the_shell_uses_plain_prompt_text_without_ascii_art
    refute ascii.key?("wordmark")
    # ascii.prompt holds the terminal shell's glyphs (Master::Face.glyph); the web
    # shell never reads them and labels turns with plain words.
    refute_includes read(PUBLIC, "chat.js"), "ascii.prompt"
    refute_match(/<pre id="wordmark"/, view)
    # The web prompt shows host:path$ like the terminal, from the same contract.
    sigil = %r{<span class="prompt-sigil" aria-hidden="true"><%= Master::Face::Contract\.shell_prompt\(path: Master::ROOT, llm: @model == "booting" \? nil : @model\) %></span>}
    assert_match(sigil, view)
    refute_includes view, 'class="sep2"'
    tokens = read(ROOT, "MASTER", "data", "tokens.yml")
    assert_match(/user_token: "user"/, tokens)
    assert_match(/master_token: "master"/, tokens)
    chat = read(PUBLIC, "chat.js")

    assert_includes chat, "shellPromptLabel(role)"
    assert_includes chat, "prompt.user_token"
    assert_includes chat, "prompt.master_token"
    refute_includes chat, "master$ "
    refute_includes chat, "promptGlyph"
    refute_includes read(PUBLIC, "face.css"), ".wordmark {"
  end

  def test_the_brand_mark_is_left_to_its_own_font
    css = read(PUBLIC, "face.css")

    assert_match(/--font-logo: "Helvetica Neue", Helvetica, Arial, sans-serif;/, css)
    assert_includes css, 'font: 700 clamp(0.9375rem, 2.8vw, 1.125rem) / 1 var(--font-logo);'
    assert_includes view, '<% mark = "ai.brgen.no" %>'
    assert_includes view, '<span class="brand-text"><%= mark %></span>'
  end

  def test_type_is_mono_for_the_face_and_shell_and_never_serif
    %w[face.css chat_upload.css].each do |name|
      css = read(PUBLIC, name)
      bare = css.gsub(/ui-sans-serif|sans-serif/i, "")

      refute_match(/\bserif\b/i, bare, "#{name}: no serif generic")
      refute_match(/georgia|garamond|palatino|cambria|times new roman|didot|bodoni/i, css, "#{name}: no named serif face")
    end
    css = read(PUBLIC, "face.css")
    shell = css.scan(/^(#chat-log|\.message|\.msg-body)\s*\{[^}]*\}/m).size

    assert_operator shell, :>=, 3
    css.scan(/^(?:#chat-log|\.message|\.msg-body|\.message\.(?:user|assistant) \.msg-prompt)\s*\{[^}]*\}/m).each do |block|
      refute_match(/font(?:-family)?:[^;]*var\(--font-brand\)/, block, "shell rule keeps the sans brand font:\n#{block}")
    end
  end
end
