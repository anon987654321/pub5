# frozen_string_literal: true

require "erb"

require_relative "../../support/check_result"
require_relative "../../support/fleet"

module Deploy
  # PWA-100 and BRGEN-115. Five manifests, and nothing checked that what they
  # declare exists or that what they call the app matches what the page does.
  #
  # The icon check is the reason this is a check rather than a test, and it is
  # also the trap it exists to encode. An icon in a manifest is a path, not a
  # file, and it resolves from two places: the app's own public/ and the shared
  # engine's, which shared/lib/shared/engine.rb:133 mounts with its own
  # ActionDispatch::Static. Looking in the app's public/ alone reports brgen and
  # bsdports as declaring five icons and shipping two — which is wrong, and is
  # exactly what a hand check found before reading the engine. Amber keeping its
  # own copies is the anomaly, not the other two lacking them.
  #
  # So: resolve every declared icon against both, and fail only when it is in
  # neither. That is the claim worth holding, and it is one nobody can make by
  # listing a directory.
  class PwaInstallable
    # checks/lib/source -> checks/lib -> checks -> MASTER -> repository root; the
    # apps themselves live under RAILS/, so every lookup joins RAILS_ROOT.
    # Before the 11b0633bd move this constant sat at RAILS/checks and three
    # levels sufficed; from MASTER it is four plus the RAILS_ROOT join.
    ROOT = File.expand_path("../../../..", __dir__)

    APPS = Fleet.app_names.freeze

    # Chrome installs on one 192 and one 512 with purpose "any". Maskable and
    # monochrome are polish; these two are the requirement.
    REQUIRED_SIZES = %w[192x192 512x512].freeze
    REQUIRED_KEYS = %w[name short_name start_url display icons].freeze

    def self.run = new.run

    def run
      @result = CheckResult.new
      APPS.each { |app| check_app(app) }
      check_brgen_brand
      @result
    end

    private

    def check_app(app)
      manifest = manifest_path(app)
      unless manifest
        @result.fail("pwa_installable: #{app} has no manifest under app/views/pwa")
        return
      end

      source, rendered = manifest_sources(manifest)
      check_keys(app, rendered)
      check_icons(app, rendered)
      check_service_worker(app)
    end

    # master's face lives at MASTER/web (apps.yml deploy_root), not RAILS/master;
    # every app root comes from Fleet.app_dir so the manifest, the worker and the
    # icon roots all resolve against the tree the app actually deploys from.
    def manifest_path(app)
      candidates = %w[app/views/pwa/manifest.json app/views/pwa/manifest.json.erb]
      candidates.map { |path| File.join(app_root(app), path) }.find { |path| File.file?(path) }
    end

    # A manifest may be a static JSON document or a .json.erb the app renders per
    # request (brgen resolves the city per host; mrdamascy reads design tokens).
    # The requirement is about the manifest the browser receives, so the keys and
    # the icons are measured against the rendered JSON; the raw source stays
    # available for the brand check, which must see city_name before rendering.
    # The rendered pass evaluates the template with the helper names the apps
    # bind, stubbed to neutral values -- it measures shape, not copy.
    def manifest_sources(path)
      source = File.read(path)
      return [source, source] unless path.end_with?(".erb")

      [source, render_manifest_erb(source)]
    end

    def render_manifest_erb(source)
      sandbox = manifest_sandbox
      _erbout = +""
      sandbox.module_eval(ERB.new(source).src, "(manifest render)")
      _erbout
    end

    # The stubs live on a sandbox module, not on Object: module_eval's cref
    # is the sandbox, so `Master`, `Current` and `I18n` resolve inside it and
    # never touch (or collide with) the real constants the check process has
    # loaded. Method calls resolve on the module for the same reason.
    def manifest_sandbox
      sandbox = Module.new
      define_manifest_text_helpers(sandbox)
      define_manifest_context_constants(sandbox)
      # asset_path returns the plain public path so the icon-resolution pass
      # measures the file that ships, not a build-time digest.
      sandbox.define_singleton_method(:asset_path) { |name| "/#{name}" }
      sandbox
    end

    def define_manifest_text_helpers(sandbox)
      sandbox.define_singleton_method(:t) { |_key, **opts| opts[:default].to_s }
      sandbox.define_singleton_method(:city_name) { "Bergen" }
      sandbox.define_singleton_method(:design_token) { |_name| "" }
      sandbox.define_singleton_method(:raw) { |value| value }
      sandbox.define_singleton_method(:current_city) { "Bergen" }
    end

    def define_manifest_context_constants(sandbox)
      # master reads the face token for theme/background colour; a neutral
      # value keeps the shape check independent of the live token file.
      master = Module.new
      master.define_singleton_method(:tokens) do
        { "face_root" => { "face_bg" => "#101014" } }
      end
      sandbox.const_set(:Master, master)
      current = Object.new
      current.define_singleton_method(:subapp) { "" }
      current.define_singleton_method(:locale) do
        blank = Object.new
        blank.define_singleton_method(:presence) { nil }
        blank
      end
      sandbox.const_set(:Current, current)
      i18n = Module.new
      i18n.define_singleton_method(:locale) { :en }
      sandbox.const_set(:I18n, i18n)
    end

    def check_keys(app, source)
      REQUIRED_KEYS.each do |key|
        @result.checked!
        next if source.include?(%("#{key}":))

        @result.fail("pwa_installable: #{app} manifest declares no #{key} - not installable")
      end
    end

    # Every src, resolved against both public roots. The sizes check reads the
    # declared purpose because a manifest of nothing but maskable icons installs
    # nowhere.
    def check_icons(app, source)
      icons = parse_icons(source)

      @result.checked!
      if icons.empty?
        @result.fail("pwa_installable: #{app} manifest lists no icons")
        return
      end

      icons.each do |icon|
        @result.checked!
        next if resolves?(app, icon[:src])

        @result.fail("pwa_installable: #{app} declares #{icon[:src]}, which is in neither " \
                     "#{app}/public nor shared/public")
      end
      check_required_sizes(app, icons)
    end

    # One entry at a time, and an absent purpose is "any".
    #
    # Both halves of that were learned the hard way on the first run. A single
    # regex reading src, sizes and purpose across the whole array pairs entry
    # one's src with entry three's purpose the moment an entry omits the key —
    # and bsdports omits it on exactly the two icons that make it installable,
    # so the check reported the one app it should have cleared. The spec says an
    # icon with no purpose is "any", which is why omitting it is correct and why
    # a checker that requires it is measuring its own assumption.
    def parse_icons(source)
      block = source[/"icons":\s*\[(.*?)\]/m, 1].to_s

      block.scan(/\{(.*?)\}/m).flatten.filter_map do |entry|
        src = entry[/"src":\s*"([^"]+)"/, 1]
        next unless src

        { src:, sizes: entry[/"sizes":\s*"([^"]+)"/, 1].to_s,
          purpose: entry[/"purpose":\s*"([^"]+)"/, 1] || "any" }
      end
    end

    def check_required_sizes(app, icons)
      # purpose is a space-separated list, so "any maskable" serves both.
      any = icons.select { |icon| icon[:purpose].split.include?("any") }
      REQUIRED_SIZES.each do |size|
        @result.checked!
        next if any.any? { |icon| icon[:sizes] == size }

        @result.fail("pwa_installable: #{app} declares no #{size} icon with purpose any - " \
                     "maskable and monochrome do not satisfy the install prompt")
      end
    end

    def check_service_worker(app)
      @result.checked!
      root = app_root(app)
      # A worker may ship as a static file (amber, bsdports, master's public/sw.js)
      # or as a .js.erb the app renders per request (mrdamascy's PwaController#service_worker
      # stamps the cache version from the asset digests). Both are a service worker.
      worker = File.join(root, "app/views/pwa/service-worker.js")
      worker_erb = File.join(root, "app/views/pwa/service-worker.js.erb")
      return if File.file?(worker) || File.file?(worker_erb)
      # master serves a static worker from public/sw.js, which AuthTier lists as public.
      return if File.file?(File.join(root, "public", "sw.js"))

      @result.fail("pwa_installable: #{app} has no service worker at #{rel(worker)}")
    end

    # BRGEN-115. brgen is the only city-tenanted app of the three, so it is the
    # only one whose manifest must not name a city: the same page is served as
    # Bergen and as Oslo, and a manifest saying Bergen on oshlo.no is visible at
    # install time. amber and bsdports are single-brand and their literals are
    # correct.
    def check_brgen_brand
      @result.checked!

      manifest = manifest_path("brgen")
      unless manifest
        @result.fail("pwa_installable: brgen has no manifest under app/views/pwa")

        return
      end
      source = File.read(manifest)
      unless source.include?("city_name")
        @result.fail("pwa_installable: brgen manifest does not derive its name from city_name - " \
                     "an installed app on oshlo.no would be called Bergen")
        return
      end

      literal = source[/"name":\s*"([A-Z][a-z]+)"/, 1]
      return unless literal

      @result.fail("pwa_installable: brgen manifest hardcodes the name #{literal.inspect}; " \
                   "the city is resolved per host")
    end

    def resolves?(app, src)
      path = src.sub(%r{\A/}, "")
      File.file?(File.join(app_root(app), "public", path)) ||
        File.file?(File.join(rails_root, "__shared", "public", path))
    end

    def app_root(app)
      Fleet.app_dir(app)
    end

    def rails_root = File.join(ROOT, "RAILS")

    def rel(path) = path.sub("#{ROOT}/", "")
  end
end
