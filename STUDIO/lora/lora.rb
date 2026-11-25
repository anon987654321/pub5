# frozen_string_literal: true

require "yaml"
require "json"
require "rbconfig"
require_relative "../replicate/subprocess"

# Consolidated LoRA craft: what a photograph of a subject can be asked for, in
# words a FLUX.1-dev person LoRA acts on, plus the selfie sittings the series
# renders. Recovered from the 2026-08/10/19 STUDIO notes (PHOTOGRAPHY.md,
# lora/guides/{photography,prompting}.md and preprompt/lib/craft.rb) after that
# knowledge was lost in the pub4 -> pub5 move, and kept here as the one owner.
#
# Two facts drive everything below:
#
#   * Geometry, light direction and expression are decided at generation and no
#     grade can add them. The optical signature (plastic skin, uniform
#     speculars, a perfect dot for an eye reflection) is the one layer postpro
#     exists to fix. So this file spends its words on the first three.
#   * Focal length does not distort a face; distance does. A real selfie is shot
#     at arm's length, roughly 45 cm, and inherits the wide-angle projection that
#     enlarges the nose and drops the ears. A generated image has no camera in
#     it, so it can keep a selfie's framing and held gaze at a portrait's
#     distance. That separation is the single most specific thing to ask for.
#
# FLUX.1 is guidance-distilled: a negative prompt does nothing. Every rule here
# is therefore stated as what is wanted, never as what to avoid.

module Studio
  module Lora
    # The LoRA CLI: run `ruby STUDIO/lora/lora.rb` with no arguments and it asks
    # what to do, then hands off to the owning tool. Flags are not the interface;
    # this is the one place a person starts from.
    module CLI
      module_function

      def run(argv)
        require_relative "../replicate/api"
        return Studio::Api.respond(api_actions, argv:) if Studio::Api.requested?(argv)

        require_relative "../replicate/interactive"
        wizard = Studio::Interactive.new
        return run_flags(argv) unless argv.empty? && wizard.tty?

        choice = wizard.choose("What would you like to do with a LoRA subject?", [
          ["Validate a subject's training plan", :validate],
          ["Audit photographic quality and subject readiness", :quality],
          ["Review an existing portrait series against holdout photographs", :review],
          ["Review or restore local private source material", :recover],
          ["Render a selfie series", :selfie],
          ["Produce finished selfie films", :film],
        ])
        case choice
        when :validate then validate
        when :quality then quality_command([])
        when :review
          subject = wizard.ask("Subject", default: "ragnhild")
          review_command(["--subject", subject])
        when :recover then puts JSON.pretty_generate(recovery_command([]))
        when :selfie then selfie(wizard)
        when :film then film_command([])
        end
      end

      # The API actions MASTER reaches over the subprocess boundary: read-only
      # validation and the render hand-off, with no prompt in sight.
      def api_actions
        {
          "validate" => ->(request) { validate_report(request) },
          "quality" => ->(request) { quality_report(request) },
          "readiness" => ->(request) { readiness_report(request) },
          "review" => ->(request) { review_report(request) },
          "subjects" => ->(_request) { subjects },
          "craft" => ->(_request) { craft },
          "recover" => ->(request) { recovery_report(request) },
          "selfie" => ->(request) { selfie_render(request) },
          "film" => ->(request) { film_render(request) },
        }
      end

      def validate_report(request)
        require_relative "validate"
        validator = Studio::Lora::Validator.new
        subject = request["subject"].to_s
        if subject.empty?
          validator.validate_all
        else
          {
            "schema" => "studio.lora.validation.v1",
            "read_only" => true,
            "provider_calls" => 0,
            "subject_count" => 1,
            "subjects" => [validator.validate_subject(subject)],
          }
        end
      end

      def quality_report(request)
        require_relative "quality"
        Studio::Lora::Quality.report(subject: request["subject"])
      end

      # MASTER's preflight entrypoint: training readiness, independent holdout
      # inventory and review consent in one report. It never calls a provider.
      def readiness_report(request)
        report = quality_report(request || {})
        report.merge(
          "schema" => "studio.lora.readiness.v1",
          "read_only" => true,
          "provider_calls" => 0,
          "training_started" => false,
        )
      end

      # Review the latest completed series against the independent holdout set.
      # This writes private HTML/JSON review artefacts but never renders or uploads.
      def review_report(request)
        require_relative "review"
        subject = request.fetch("subject").to_s
        result = Studio::Lora::Review::Builder.new(subject:).build(candidate: false)
        result.merge("provider_calls" => 0, "candidate_generation" => false)
      end

      def subjects
        require_relative "validate"
        root = Studio::Lora::Validator::ROOT
        Studio::Lora::Validator.subject_names(root:)
      end

      # The subject craft vocabulary, so MASTER can describe what STUDIO renders.
      def craft
        {
          "geometry" => Studio::Lora::Craft::GEOMETRY,
          "scenes" => Studio::Lora::Selfie::SCENES,
          "subject_scenes" => Studio::Lora::Selfie::SUBJECT_SCENES,
        }
      end

      # Read-only by default. Applying copies is possible only when the
      # request explicitly sets apply=true and each subject's private consent
      # and source-rights evidence already validates locally.
      def recovery_report(request)
        request ||= {}
        arguments = []
        arguments.concat(["--from", request["from"].to_s]) unless request["from"].to_s.empty?
        arguments.concat(["--subject", request["subject"].to_s]) unless request["subject"].to_s.empty?
        arguments << "--include-sources" if request["include_sources"] == true
        arguments << "--restore-johann-history" if request["restore_johann_history"] == true
        arguments << "--apply" if request["apply"] == true
        recovery_command(arguments)
      end

      def recovery_command(arguments)
        require_relative "migrate_local"
        Studio::Lora::LocalMigration.run(arguments)
      end

      def film_render(request)
        require_relative "selfie_film"
        subjects = request["subjects"] || (request["subject"] ? [request["subject"]] : Studio::Lora::SelfieFilm::SUBJECTS)
        Studio::Lora::SelfieFilm.new.run_all(
          subjects:, count: request.fetch("count", Studio::Lora::SelfieFilm::DEFAULT_COUNT),
          engine: request["engine"], inference_profile: request["inference_profile"]
        )
      end

      def train_command(argv)
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("train.rb", __dir__), *argv)
        success ? 0 : ($?.exitstatus || 1)
      end

      def film_command(argv)
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("selfie_film.rb", __dir__), *argv)
        success ? 0 : ($?.exitstatus || 1)
      end

      def selfie_render(request)
        require_relative "selfie_series"
        subject = request.fetch("subject", "ragnhild")
        count = request.fetch("count", 4).to_i.clamp(1, 24)
        engine = request["engine"]
        series = Studio::Visual::SelfieSeries.new(
          subject:, engine:, inference_profile: request["inference_profile"]
        )
        { "subject" => subject, "rendered" => series.run(count:), "prior_renders_retained" => true }
      end

      def run_flags(argv)
        case argv.first
        when "validate" then validate_with_flags(argv.drop(1))
        when "quality" then quality_command(argv.drop(1))
        when "review" then review_command(argv.drop(1))
        when "recover"
          puts JSON.pretty_generate(recovery_command(argv.drop(1)))
          0
        when "--json", "--subject" then validate_with_flags(argv)
        when "selfie" then selfie(Studio::Interactive.new(input: $stdin, output: $stdout, tty: false))
        when "film" then film_command(argv.drop(1))
        when "train" then train_command(argv.drop(1))
        when "-h", "--help", nil then puts help
        else abort "lora: unknown command #{argv.first.inspect} (see --help)"
        end
      end

      def quality_command(argv)
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("quality.rb", __dir__), *argv)
        success ? 0 : ($?.exitstatus || 1)
      end

      def review_command(argv)
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("review.rb", __dir__), *argv)
        success ? 0 : ($?.exitstatus || 1)
      end

      def validate
        load File.expand_path("validate.rb", __dir__)
      end

      def validate_with_flags(argv)
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("validate.rb", __dir__), *argv)
        success ? 0 : ($?.exitstatus || 1)
      end

      def selfie(wizard)
        require_relative "../replicate/models"
        subject = wizard.ask("Subject", default: "ragnhild")
        count = wizard.number("How many sittings", default: 4, range: 1..24)
        # A selfie series means the subject's own reference photographs first;
        # the trained identity is the fallback.
        success = system(Studio::Subprocess.environment, RbConfig.ruby, File.expand_path("photograph.rb", __dir__),
                        "--selfie-series", "--subject", subject, "--count", count.to_s)
        success ? 0 : ($?.exitstatus || 1)
      end

      def help
        <<~TEXT
          lora - the STUDIO likeness subject tool
          usage:
            ruby STUDIO/lora/lora.rb                 ask what to do (interactive)
            ruby STUDIO/lora/lora.rb validate        audit every subject's training plan
            ruby STUDIO/lora/lora.rb train --all --approve-spend-usd USD
                                                       preflight and train within an explicit spend ceiling
            ruby STUDIO/lora/lora.rb recover         dry-run local source recovery from ../pub4
            ruby STUDIO/lora/lora.rb recover --apply  copy only after private rights preflight
            ruby STUDIO/lora/lora.rb validate --json  read-only training and consent audit
            ruby STUDIO/lora/lora.rb quality --json   read-only photography/profile/holdout audit
            ruby STUDIO/lora/lora.rb review --subject NAME
                                                       review the latest series against independent holdouts
            ruby STUDIO/lora/lora.rb selfie          render a selfie series after likeness approval
            ruby STUDIO/lora/lora.rb film            make finished, locally private selfie films
          The subject craft itself (scenes, prompting rules, grades) lives in
          this file as Studio::Lora::Craft and Studio::Lora::Selfie.
        TEXT
      end
    end
    module Craft
      # The arm's length framing with a three-metre portrait's proportion.
      GEOMETRY = "held at arm's length in framing and eye contact but with the " \
                 "facial proportions of a portrait made from three metres, no " \
                 "wide-angle enlargement of the nose or forehead"
      # What a retouched training set removed. Stated as presence, not absence.
      SKIN = "visible pores and fine vellus hair, uneven skin texture across the " \
             "face, subsurface scattering warming the light through the ears and " \
             "nostrils, natural asymmetry"
      LIGHT = "one clear light direction with a real shadow side, catchlights in " \
              "both eyes shaped by the source"
      FOCUS = "sharp focus on the nearest eye"
      # Shared craft contains capture technique only. Film stock is a per-shot
      # decision, not a universal prompt fragment.
      COMPOSITION = "one unmistakable visual centre, deliberate headroom and eye-line, " \
                    "clear separation between subject and background, foreground and background " \
                    "kept in distinct readable planes, negative space supporting the subject's gaze, " \
                    "every visible object serving the frame"
      PHOTOGRAPHIC_CRAFT = [GEOMETRY, LIGHT, SKIN, FOCUS, COMPOSITION, "no text in the frame"].join(", ")

      def self.photographic(words)
        # Phone perspective is an intentional alternative, not a contradiction
        # appended to portrait-distance geometry.
        tail = words.to_s.include?("24mm-equivalent phone lens") ? [LIGHT, SKIN, FOCUS, COMPOSITION] : [PHOTOGRAPHIC_CRAFT]
        [words, *tail].compact.join(", ")
      end

      # A shot is a capture plan and a single laboratory decision, not a stack
      # of filters. These are existing Postpro presets, not new film stocks.
      LABORATORY = %w[house portrait cinematic neon_night reportage silver_gelatin
                      pastel_portrait instant_pack aged_kodachrome street noir
                      saturated_negative golden_age contact_print analog_scan
                      vhs_tape crt_broadcast].freeze

      # The house decision, so nobody has to remember a flag: every sitting is
      # developed with its own named grade, then one shared second pass carries
      # the series together, and only the developed frame is kept. Change the
      # look here, once, rather than at each call site.
      HOUSE_CHAIN = %w[aged_kodachrome].freeze
      SHOT_AXES = %w[scene framing distance lens lighting moment gaze composition].freeze
      SHOT_OPTIONAL = %w[preset key_side catchlight focus].freeze
      KEY_SIDE = {
        "short" => "key light on the side turned away from the camera",
        "broad" => "key light on the side facing the camera",
        "even" => "even light across the face"
      }.freeze
      SHOT_FOCUS = {
        "eyes" => FOCUS, "face" => "the face in sharp focus",
        "deep" => "subject and background in deep focus"
      }.freeze
      CAMERA_DISTANCES = %w[1m 2m 3m 5m selfie].freeze

      def self.compile_shot(shot)
        raise ArgumentError, "shot must be an object" unless shot.is_a?(Hash)
        unknown = shot.keys - (SHOT_AXES + SHOT_OPTIONAL)
        raise ArgumentError, "unknown shot fields: #{unknown.join(', ')}" unless unknown.empty?
        SHOT_AXES.each do |axis|
          value = shot.fetch(axis, nil)
          raise ArgumentError, "shot needs #{axis}" unless value.is_a?(String) && !value.strip.empty? && value.bytesize <= 2000
        end
        distance = shot.fetch("distance")
        lens = shot.fetch("lens")
        preset = shot.fetch("preset", "house")
        raise ArgumentError, "unknown camera distance" unless CAMERA_DISTANCES.include?(distance)
        raise ArgumentError, "unknown lens" unless LENS.key?(lens)
        raise ArgumentError, "unknown lighting" unless LIGHTING.key?(shot.fetch("lighting"))
        raise ArgumentError, "unknown moment" unless MOMENT.key?(shot.fetch("moment"))
        raise ArgumentError, "unknown laboratory preset" unless LABORATORY.include?(preset)
        raise ArgumentError, "phone distance conflicts with a portrait lens" if distance == "selfie" && lens != "24mm"
        raise ArgumentError, "portrait distance conflicts with phone perspective" if distance != "selfie" && lens == "24mm" && shot.fetch("framing").include?("phone")
        key_side = shot["key_side"] && KEY_SIDE.fetch(shot["key_side"]) { raise ArgumentError, "unknown key side" }
        catchlight = shot["catchlight"] && CATCHLIGHT.fetch(shot["catchlight"]) { raise ArgumentError, "unknown catchlight" }
        focus = SHOT_FOCUS.fetch(shot.fetch("focus", "eyes")) { raise ArgumentError, "unknown focus" }
        clauses = [shot.fetch("scene"), shot.fetch("framing"), SUBJECT_DISTANCE.fetch(distance),
                   LENS.fetch(lens), LIGHTING.fetch(shot.fetch("lighting")), key_side, catchlight,
                   MOMENT.fetch(shot.fetch("moment")), shot.fetch("gaze"), shot.fetch("composition"),
                   SKIN, focus, "no text in the frame"].compact
        prompt = clauses.join(", ")
        hits = backfiring_words(prompt)
        raise ArgumentError, "prompt works against itself: #{hits.keys.join(', ')}" unless hits.empty?
        { "shot" => shot.merge("preset" => preset), "prompt" => prompt, "preset" => preset }
      end

      # Where the camera stands, which is the axis that decides distortion. The
      # description is deliberately omitted from a prompt: handing the model a
      # description of distortion measures whether it follows a description,
      # not whether it knows what distance does.
      SUBJECT_DISTANCE = {
        "selfie" => "camera at arm's length, roughly 45cm from the face, visible wide-angle perspective",
        "1m" => "camera about a metre from the subject, mild perspective exaggeration",
        "2m" => "camera about two metres back, natural facial proportion",
        "3m" => "camera about three metres back, compressed facial proportion",
        "5m" => "camera about five metres back, strongly compressed, flattened features",
      }.freeze

      LENS = {
        "24mm" => "24mm wide lens, strong perspective, foreground close and background deep",
        "35mm" => "35mm lens, moderate depth of field, slight environmental context",
        "50mm" => "50mm lens, natural perspective, shallow depth of field",
        "85mm" => "85mm portrait lens, compressed background, creamy bokeh",
        "105mm" => "105mm short telephoto, flattened features, isolated subject",
        "135mm" => "135mm telephoto, heavy compression, background reduced to tone",
        "anamorphic" => "anamorphic lens, oval bokeh, horizontal blue flare",
        "petzval" => "Petzval lens, swirling background bokeh, sharp centre falling off to the edges",
      }.freeze

      LIGHTING = {
        "soft" => "soft diffused key light, low contrast falloff",
        "hard" => "hard direct key light, defined shadow edges",
        "window" => "window light from camera-left, natural falloff",
        "golden_hour" => "warm low-angle golden-hour sunlight",
        "rembrandt" => "Rembrandt key light, triangle of light on the shadow-side cheek",
        "split" => "split lighting, one half of the face lit and the other in shadow",
        "loop" => "loop lighting, small nose shadow angled down the cheek",
        "butterfly" => "butterfly lighting, elevated on-axis key with a small shadow under the nose",
        "rim" => "rim light separating the subject from a dark background",
        "practical" => "lit only by practical lamps inside the scene, mixed colour temperature",
        "neon" => "neon sign lighting, saturated magenta and cyan on skin",
        "overcast" => "overcast sky as one enormous softbox, shadowless and even",
        "open_shade" => "open shade, cool ambient fill bounced from the sky",
        "direct_flash" => "direct on-camera flash, hard shadow behind the subject",
        "mixed" => "mixed daylight and tungsten, warm interior against cool window light",
        "backlit" => "backlit rim light, subject silhouetted against the source",
      }.freeze

      # The light source reflected in the eye. Its shape states the modifier,
      # which is why a portrait reads as lit rather than rendered.
      CATCHLIGHT = {
        "window" => "large soft rectangular catchlight from a window",
        "open_shade" => "soft sky catchlights",
        "overcast" => "soft sky catchlights",
        "golden_hour" => "warm sun catchlights",
        "practical" => "lamp catchlights",
        "neon" => "neon catchlights",
        "direct_flash" => "hard flash catchlights",
        "mixed" => "warm and cool catchlights",
        "backlit" => "faint catchlights",
        "hard" => "hard sun catchlights",
        "softbox" => "rectangular catchlights high in the eyes",
        "beauty_dish" => "round catchlights with a darker centre",
        "twin" => "key and fill catchlights at ten and two o'clock",
      }.freeze

      # The moment, not the performance. A smile asked for by name collapses to
      # the one held shape a model has seen most, and people read a held
      # expression as held. Portrait practice shoots just after a laugh, as the
      # face settles.
      MOMENT = {
        "after_laugh" => "the moment just after a laugh, the face still settling",
        "real_grin" => "a wide spontaneous grin, cheeks lifted, eyes bright",
        "about_to_laugh" => "amused and about to laugh",
        "half_smile" => "a lopsided half-smile, one corner of the mouth higher",
        "eye_crinkle" => "fine lines at the outer corners of the eyes from a real expression",
        "breath_held" => "a breath held, lips just closed",
        "mid_word" => "lips parted mid-word",
        "unguarded" => "an unguarded, tired expression, nothing arranged for the camera",
      }.freeze

      STOCK = {
        "portra" => "Kodak Portra 400 colour negative scan, fine grain, gentle highlight rolloff",
        "portra800" => "Kodak Portra 800 colour negative, warmer grain, low-light latitude",
        "gold" => "Kodak Gold 200 warm consumer colour, soft contrast",
        "ultramax" => "Kodak UltraMax 400 consumer negative, punchy saturation",
        "fuji400h" => "Fujifilm Pro 400H, cool pastel palette, gentle greens and soft skin",
        "superia" => "Fujifilm Superia 400, green-leaning consumer colour, visible grain",
        "cinestill" => "CineStill 800T tungsten-balanced, halation around highlights",
        "hp5" => "Ilford HP5 Plus 400 black and white, forgiving latitude, classic grain",
        "trix" => "Kodak Tri-X 400 black and white, silver-rich contrast, visible grain",
        "instax" => "Fujifilm Instax instant print, bright flash falloff, small-format softness",
        "polaroid" => "Polaroid SX-70 instant film, soft focus falloff, milky highlights",
      }.freeze

      # Words that ask for the opposite of a photograph: prompt-optimiser terms
      # that pull a picture toward concept art, and the retouched-skin words that
      # name the failure this vocabulary exists to avoid.
      BACKFIRING_WORDS = {
        "8k" => "pulls the picture toward rendered concept art",
        "masterpiece" => "pulls the picture toward illustration",
        "artstation" => "names a concept-art site, and the picture follows it there",
        "octane render" => "names a 3D renderer, so the picture reads as rendered",
        "hyperrealistic" => "reads as illustration imitating a photograph",
        "flawless" => "asks for the retouched, poreless skin that marks a generated face",
        "poreless" => "asks for the retouched, poreless skin that marks a generated face",
        "airbrushed" => "asks for the retouched, poreless skin that marks a generated face",
      }.freeze

      def self.backfiring_words(prompt)
        text = prompt.to_s.downcase
        BACKFIRING_WORDS.select { |word, _| text.match?(/(?<![\w-])#{Regexp.escape(word)}(?![\w-])/) }
      end
    end

    # The selfie series' sittings. Ten, radically different from one another:
    # a different environment, a different thing happening in the frame, a
    # different crop, lens and light. Each is a complete prompt body, so a
    # sitting states its own lens and no shared craft is appended over it.
    module Selfie
      # Each scene is the body of the prompt: environment, what is happening,
      # crop, lens, light and moment. The subject's trigger, descriptor and the
      # shared Craft tail are added by IdeaPicture, which is the one place that
      # knows them. Every sitting declares five shot-design axes - framing,
      # lens or distance, light, moment and eye-line - and
      # Quality.audit_scene_design refuses a sitting that leaves one to chance.
      SCENES = [
        # 1 — a white-sand beach with limestone islands on the horizon
        "a barefoot selfie on a white-sand beach in Langkawi looking out over the " \
        "green limestone islands of southern Thailand, warm late-afternoon sun low " \
        "across the water, salt-damp hair, chest-up crop, 50mm lens, eyes on the " \
        "lens, the moment just after a laugh",
        # 2 — the new tower, vertigo
        "a selfie at the foot of the new Menara Merdeka tower in Kuala Lumpur, the " \
        "camera angled up the glass and steel, pale blue midday haze, city vertigo, " \
        "wide environmental framing, 35mm lens, eyes on the lens, a wide real grin",
        # 3 — night market, colour
        "a night-market selfie in George Town, Penang, surrounded by hanging " \
        "lanterns and steaming food stalls, saturated neon and tungsten mixing on " \
        "the skin, the crowd softly blurred behind, chest-up framing, 50mm lens, chin lowered eyes up, " \
        "amused and about to laugh",
        # 4 — rainforest canopy, dappled green
        "a selfie on a rainforest canopy walkway in Taman Negara, dappled green " \
        "light through the leaves, mist drifting between the trees, " \
        "head-and-shoulders crop, 85mm lens, eyes just past the lens, an unguarded " \
        "expression",
        # 5 — Norwegian ferry deck, wind
        "a selfie on the deck of a Norwegian coastal ferry with a fjord wall behind, " \
        "wind pulling at her hair, flat overcast light, the arm holding the camera " \
        "visible at the frame edge, 50mm lens, eyes on the lens, a warm half-smile",
        # 6 — snow cabin at dusk, blue hour
        "a selfie outside a snow-covered mountain cabin at dusk, the last blue light " \
        "in the sky and a single warm lamp behind her, a wool jumper and breath " \
        "visible in the cold, head-and-shoulders framing, 85mm lens, eyes on the lens, cheeks lifted eyes bright",
        # 7 — midnight kitchen, one lamp
        "a selfie in a dim kitchen at midnight making tea, lit by one lamp under the " \
        "cabinets, steam rising from the cup, one hand resting at the jaw, waist-up framing, eyes lowered to the cup, 50mm " \
        "lens, a tired unguarded expression, nothing arranged for the camera",
        # 8 — car window, golden hour
        "a selfie through the open window of a parked car at a coastal overlook at " \
        "golden hour, warm low sun raking across her face, chest-up framing, 35mm lens, eyes just past " \
        "the lens, laughing at something off frame",
        # 9 — rainy old town, umbrella
        "a selfie on a cobbled old-town street in the rain, holding an umbrella, wet " \
        "stone reflecting the shop lights, cool overcast light, waist-up framing, 50mm lens, eyes on " \
        "the lens, biting back a grin",
        # 10 — rooftop pool, blue hour city
        "a selfie on a rooftop pool deck at blue hour with a lit city skyline " \
        "behind, cool ambient light on her face against warm city bokeh, chest-up framing, 35mm lens, " \
        "eyes on the lens, a wide real grin",
      ].freeze

      # Each sitting gets its own stock, rather than inheriting one house look.
      SCENE_STOCKS = %w[
        portra ultramax cinestill fuji400h hp5 portra800 trix gold superia instax
      ].freeze

      # Six individual sittings for each trained identity. Scene bodies carry
      # the environment, gesture, light and framing; the subject trigger and
      # identity descriptor are added once by IdeaPicture.
      SUBJECT_SCENES = {
        "johann" => [
          "a candid mid-torso selfie beside a rain-streaked café window in central Bergen, wearing a long charcoal herringbone wool chore coat over an oatmeal Fair Isle lambswool crewneck, the coat's broad collar and knit texture clearly visible, wet cobblestones and a soft harbour blur outside, cool north daylight, rectangular window catchlights, a quiet expression just after a laugh, portrait-distance facial proportions with intimate direct-to-lens framing, 85mm",
          "a coastal-ferry-deck selfie with a Norwegian fjord wall behind, wearing a forest-green Fair Isle wool crewneck over a clean white waffle-knit Henley, relaxed dark denim, the patterned knit visible across the chest, waist-up framing, wind moving the hair and coat collar, broad overcast sky as a softbox, relaxed half-smile, natural eye contact, 50mm",
          "a late-night record-shop selfie between listening shelves, wearing a dark espresso suede leather blouson over a cream cashmere zip cardigan and charcoal merino crewneck, the suede nap and simple collar clearly visible, one warm tungsten practical and a cool street-window fill, waist-up framing, mixed warm and cool catchlights, amused mid-conversation expression, eyes finding the lens, 50mm",
          "a winter cabin selfie at blue hour, wearing a deep aubergine velvet tailored blazer over a black fine-gauge merino rollneck, relaxed dark wool trousers, the velvet pile catching the warm cabin light, snow and dark pine outside, one warm lamp behind and cold sky fill across the face, head-and-shoulders framing, visible breath, unguarded eyes, 85mm",
          "a morning harbour-side selfie after rain, working boats and muted buildings falling softly out of focus, clean grey daylight, chest-up framing, a real small grin, eyes on the lens, documentary colour-negative photography, 50mm",
          "a black-and-white street portrait selfie beneath an old Bergen arcade, wet stone catching a hard strip of daylight, chest-up framing, rich Tri-X silver tones, direct gaze and natural facial texture, an unhurried calm, 85mm",
        ].freeze,
        "ragnhild" => [
          "a painter's-studio selfie beside a large unfinished canvas, wearing a sharply tailored oxblood wool jacket with matching high-waisted trousers and an ivory silk-charmeuse blouse, the clean lapel and fluid blouse visible in a waist-up crop, daylight from a tall north-facing window, paint-marked sleeve and quiet concentration, eyes returning to the lens, soft rectangular catchlights, restrained editorial framing, 85mm",
          "a gallery-evening selfie after the visitors have left, wearing a rich-purple velvet blazer over a dark plum satin blouse and fluid tailored black trousers, the velvet and silk textures visible under warm track lights, paintings behind and gentle cool fill from the windows, waist-up framing, thoughtful expression, eyes drifting past the lens, soft even skin, 50mm",
          "a waterfront selfie on a windy Bergen afternoon, wearing a dark chestnut suede coat with a soft shearling collar over a pale cashmere knit, the collar and knit clearly framed against the grey sea and distant mountains, soft overcast light, hair moving naturally, the moment just after a laugh, eyes bright at the lens, 50mm",
          "a small old-town café selfie on a rainy afternoon, wearing a structured black leather blazer over a vivid chartreuse fine-gauge merino sweater and dark tailored trousers, the clean leather shoulders and bright knit visible in the crop, window reflections and warm lamps behind, short-side window light shaping the cheek, a lopsided half-smile, eyes on the lens, 85mm",
          "a monochrome studio portrait selfie in front of a charcoal drawing, head-and-shoulders framing, soft clamshell light with a gentle fill and no hard shadow edge, direct calm gaze, nothing performed, tactile HP5 documentary grain, 85mm",
          "a winter hillside selfie just after sunrise, pale sky and bare branches behind, crisp open-shade light, wool coat, chest-up framing, a reflective unposed expression, eyes past the lens, muted Fuji colour, 50mm",
        ].freeze,
        "merethe" => [
          "a coastal-cliff selfie in western Norway, wearing a warm camel suede coat with a neat shearling collar over an ivory ribbed cashmere turtleneck, the soft pile and knit clearly visible in the chest-up frame, sea and pale sky behind, low warm sunlight, a genuine half-smile, eyes on the lens, 85mm",
          "a quiet minimalist studio selfie against warm white, wearing a tailored deep-plum velvet suit with a champagne silk-charmeuse blouse, clean single-breasted lines and rich fabric texture visible in the frame, one large softbox above and to camera-left, visible natural skin texture, composed direct gaze, a settled post-laugh composure, 85mm",
          "a candlelit kitchen selfie late in the evening, wearing a clean black leather jacket over a deep burgundy charmeuse blouse and dark straight-leg trousers, open jacket framing the blouse, one practical flame warming one side of the face and soft darkness on the other, a candid expression mid-thought, eyes lowered in thought, 50mm",
          "a backlit-window selfie on a grey morning, wearing a long deep-olive brushed-wool coat over an ivory cable-knit sweater with a restrained aubergine scarf, the coat's structured shoulder and knit pattern clearly visible, waist-up framing, soft daylight outlining the subject, reflected fill preserving detail in the eyes, a small post-laugh smile, 85mm",
          "a rainy old-town street selfie under an umbrella, shop lights reflected on wet cobbles, chest-up framing, restrained amber and blue mixed light, an amused expression, eyes on the lens, 50mm",
          "a coastal ferry selfie with a deep Norwegian fjord behind, cool overcast sky light, wind in the hair, waist-up framing, practical wool outerwear, open unguarded expression, eyes on the lens, natural colour-negative film, 50mm",
        ].freeze
      }.freeze

      SUBJECT_SCENE_STOCKS = {
        "johann" => %w[portra hp5 cinestill portra800 gold trix].freeze,
        "ragnhild" => %w[portra fuji400h gold portra800 hp5 superia].freeze,
        "merethe" => %w[fuji400h portra portra800 cinestill ultramax instax].freeze
      }.freeze

      # The house sitting keeps portrait-distance geometry while keeping the
      # selfie's framing and gaze: that is the craft decision in README §1.
      # phone: true is a deliberate distortion study for an operator who wants
      # the arm's-length look; it is not the default and needs no flag in the
      # normal path.
      PHONE_SELFIE = "handheld at arm's length, slight wide-angle perspective, natural available light, " \
                     "candid, visible skin texture and pores, no studio lighting, no beauty retouching, " \
                     "clean phone camera colour"

      def self.phone_selfie(scene)
        body = scene.to_s.gsub(/,\s*(?:35|50|85)mm\b/i, ", 24mm-equivalent phone lens")
        "#{body}, #{PHONE_SELFIE}"
      end

      # A sitting, one-based like the scenario numbers the old toolkit used.
      # Unknown subjects retain the recovered general-purpose scene set.
      def self.scene(number, subject: nil, phone: false) # rubocop:disable Style/OptionalBooleanParameter
        scenes = SUBJECT_SCENES.fetch(subject.to_s, SCENES)
        stocks = SUBJECT_SCENE_STOCKS.fetch(subject.to_s, SCENE_STOCKS)
        index = (Integer(number) - 1) % scenes.size
        body = scenes.fetch(index)
        return phone_selfie(body) if phone

        stock = Studio::Lora::Craft::STOCK.fetch(stocks.fetch(index))
        "#{body}, #{stock}"
      end

      # Only name stocks that the current laboratory can actually develop.
      # The legacy scene API still exposes its original prompt vocabulary.
      PRESET_BY_STOCK = {
        "portra" => "house", "portra800" => "cinematic", "gold" => "golden_age",
        "ultramax" => "saturated_negative", "fuji400h" => "pastel_portrait",
        "superia" => "pastel_portrait", "cinestill" => "neon_night",
        "hp5" => "reportage", "trix" => "silver_gelatin",
        "instax" => "instant_pack", "polaroid" => "instant_pack"
      }.freeze
      # Different environments first; then genuinely different photographic
      # treatments, rather than silently repeating the first six sittings.
      ALTERNATE_TREATMENTS = [
        ["clinical frontal portrait in an empty tiled hall, fluorescent ceiling practicals, chest-up framing, 50mm, direct gaze, calm expression", "contact_print"],
        ["documentary portrait outside a closed theatre, hard sidelight, chest-up framing, 85mm, eyes just past the lens, mid-conversation", "street"],
        ["oblique portrait through rain-streaked glass, layered reflections, overcast light, head-and-shoulders framing, 85mm, thoughtful gaze past the lens", "aged_kodachrome"],
        ["graphic portrait on a stairwell landing, one bare practical lamp, strong shadow side and negative space, chest-up framing, 50mm, quiet direct gaze", "noir"],
        ["found-media portrait in a quiet hotel corridor, warm practical lighting, waist-up framing, 50mm, a fleeting grin at the lens", "analog_scan"],
        ["editorial close-up in an empty studio, short-side Rembrandt light, 85mm, eyes on the lens, the moment after a laugh", "portrait"],
        ["observational portrait at an empty railway platform, blue-hour sky and warm practical fill, low vantage point, waist-up framing, 35mm, eyes off frame, reflective expression", "cinematic"],
        ["frontal documentary portrait beside a pale stone wall, soft open shade, head-and-shoulders framing, 85mm, direct gaze, settled half-smile", "reportage"],
        ["portrait in a silent library aisle, one green reading lamp and cool window fill, waist-up framing, 50mm, eyes on an open book, absorbed expression", "house"],
        ["night portrait outside a record store, neon reflection in a shop window, chest-up framing, 50mm, amused eyes on the lens", "neon_night"],
        ["portrait on an empty seaside promenade, low sunlight across the cheek, chest-up framing, 85mm, direct gaze and genuine laughter", "golden_age"],
        ["portrait at a florist doorway, cloudy daylight and a muted floral backdrop, chest-up framing, 50mm, eyes just past the lens, relaxed half-smile", "pastel_portrait"],
        ["portrait at a small concert after soundcheck, direct flash and deep background, waist-up framing, 35mm, eyes on the lens, a spontaneous grin", "instant_pack"],
        ["portrait under a railway arch, distant daylight and a deliberate silhouette, head-and-shoulders framing, 85mm, eyes toward the light, quiet expression", "silver_gelatin"]
      ].freeze

      DIRECTIONS = {
        "natural" => [
          ["window", "after_laugh", "85mm", "house"],
          ["open_shade", "half_smile", "50mm", "pastel_portrait"],
          ["overcast", "real_grin", "50mm", "reportage"],
          ["golden_hour", "about_to_laugh", "85mm", "golden_age"]
        ],
        "cinematic" => [
          ["practical", "mid_word", "50mm", "cinematic"],
          ["mixed", "half_smile", "85mm", "house"],
          ["neon", "about_to_laugh", "50mm", "neon_night"],
          ["rembrandt", "after_laugh", "85mm", "silver_gelatin"]
        ],
        "editorial" => [
          ["butterfly", "half_smile", "105mm", "house"],
          ["hard", "mid_word", "85mm", "saturated_negative"],
          ["split", "breath_held", "85mm", "noir"],
          ["window", "after_laugh", "50mm", "pastel_portrait"]
        ],
        "experimental" => [
          ["practical", "unguarded", "50mm", "aged_kodachrome"],
          ["direct_flash", "mid_word", "35mm", "contact_print"],
          ["mixed", "breath_held", "50mm", "vhs_tape"],
          ["hard", "half_smile", "85mm", "analog_scan"]
        ],
        "snapshot" => [
          ["direct_flash", "real_grin", "24mm", "instant_pack"],
          ["overcast", "after_laugh", "24mm", "house"],
          ["window", "about_to_laugh", "24mm", "pastel_portrait"],
          ["mixed", "half_smile", "24mm", "analog_scan"]
        ]
      }.freeze
      CONTEXTS = [
        "a quiet café doorway", "a covered railway platform",
        "a studio opening onto a courtyard", "a sheltered waterfront terrace",
        "a record-shop entrance", "an old building's open arcade"
      ].freeze

      def self.directional_recipe(number, direction:)
        treatments = DIRECTIONS.fetch(direction) { raise ArgumentError, "unknown photographic direction" }
        index = Integer(number) - 1
        raise ArgumentError, "sitting must be between 1 and 24" unless index.between?(0, 23)
        light, moment, lens, preset = treatments.fetch(index % treatments.size)
        context = CONTEXTS.fetch(index / treatments.size)
        shot = {
          "scene" => "a candid portrait at #{context}",
          "framing" => index.even? ? "head and shoulders" : "chest-up environmental framing",
          "distance" => direction == "snapshot" ? "selfie" : "3m",
          "lens" => lens, "lighting" => light, "moment" => moment,
          "gaze" => index.even? ? "eyes on the lens" : "eyes just past the lens",
          "composition" => "one clear visual centre, deliberate negative space, readable depth planes",
          "preset" => preset
        }
        plan = Craft.compile_shot(shot)
        { "scene" => plan.fetch("prompt"), "preset" => preset, "sitting" => number,
          "shot" => plan.fetch("shot"), "direction" => direction }
      end

      def self.recipe(number, subject: nil, direction: "varied")
        return directional_recipe(number, direction:) unless direction == "varied"

        n = Integer(number)
        raise ArgumentError, "sitting must be positive" unless n.positive?
        scenes = SUBJECT_SCENES.fetch(subject.to_s, [])
        stocks = SUBJECT_SCENE_STOCKS.fetch(subject.to_s, [])
        index = n - 1
        if index < scenes.size
          body = scenes.fetch(index)
          preset = PRESET_BY_STOCK.fetch(stocks.fetch(index))
        elsif index < scenes.size + SCENES.size
          general = index - scenes.size
          body = SCENES.fetch(general).gsub(/\bher\b/, "the subject's")
          preset = PRESET_BY_STOCK.fetch(SCENE_STOCKS.fetch(general))
        else
          alternate = index - scenes.size - SCENES.size
          body, preset = ALTERNATE_TREATMENTS.fetch(alternate % ALTERNATE_TREATMENTS.size)
        end
        # Keep capture neutral; the authoritative laboratory develops it once.
        body = body.gsub(/, (?:documentary colour-negative photography|rich Tri-X silver tones|tactile HP5 documentary grain|muted Fuji colour|natural colour-negative film)/i, "")
        { "scene" => body, "preset" => preset, "sitting" => n }
      end

      # A distinct postpro heavy look per frame, and per subject. postpro deals
      # its named looks through Random.new(POSTPRO_SEED), so the seed decides the
      # look. The subject offset matters: seeded by frame number alone, two
      # subjects landed on the same ten looks in the same order, which is what
      # made the first run read as one set repeated rather than two sittings.
      def self.grade_seed(number, subject)
        (subject.to_s.bytes.sum * 101) + (Integer(number) * 977)
      end
    end

    # The recovered photography notes as runtime data (lora/guides.yml): which
    # layer of a portrait a failure lives in and whether a grade can reach it,
    # the per-model prompting rules, the checks a render has to pass, and how the
    # measurable ones were calibrated.
    module Guides
      PATH = File.join(__dir__, "guides.yml")

      def self.load
        @load ||= YAML.safe_load_file(PATH)
      end

      def self.layers = load.fetch("layers")
      def self.prompting = load.fetch("prompting")
      def self.checks = load.fetch("checks")
      def self.calibration = load.fetch("calibration")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  status = Studio::Lora::CLI.run(ARGV)
  exit(status.is_a?(Integer) ? status : 0)
end
