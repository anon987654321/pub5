# frozen_string_literal: true

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
      HOUSE_STOCK = "Kodak Portra 400 colour negative scan, fine grain, gentle highlight rolloff"

      # The craft appended to a free-text still, after the scene words. No lens:
      # a sitting states its own focal length, and two lenses in one prompt is a
      # contradiction the model resolves by dropping one without saying which.
      PHOTOGRAPHIC_CRAFT = [GEOMETRY, LIGHT, SKIN, FOCUS, HOUSE_STOCK, "no text in the frame"].join(", ")

      def self.photographic(words)
        [words, PHOTOGRAPHIC_CRAFT].compact.join(", ")
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
      }.freeze

      # The moment, not the performance. A smile asked for by name collapses to
      # the one held shape a model has seen most, and people read a held
      # expression as held. Portrait practice shoots just after a laugh, as the
      # face settles.
      MOMENT = {
        "after_laugh" => "the moment just after a laugh, the face still settling",
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
      # knows them.
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
        "the skin, the crowd softly blurred behind, 50mm lens, chin lowered eyes up, " \
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
        "visible in the cold, 85mm lens, eyes on the lens, cheeks lifted eyes bright",
        # 7 — midnight kitchen, one lamp
        "a selfie in a dim kitchen at midnight making tea, lit by one lamp under the " \
        "cabinets, steam rising from the cup, one hand resting at the jaw, 50mm " \
        "lens, a tired unguarded expression, nothing arranged for the camera",
        # 8 — car window, golden hour
        "a selfie through the open window of a parked car at a coastal overlook at " \
        "golden hour, warm low sun raking across her face, 35mm lens, eyes just past " \
        "the lens, laughing at something off frame",
        # 9 — rainy old town, umbrella
        "a selfie on a cobbled old-town street in the rain, holding an umbrella, wet " \
        "stone reflecting the shop lights, cool overcast light, 50mm lens, eyes on " \
        "the lens, biting back a grin",
        # 10 — rooftop pool, blue hour city
        "a selfie on a rooftop pool deck at blue hour with a lit city skyline " \
        "behind, cool ambient light on her face against warm city bokeh, 35mm lens, " \
        "eyes on the lens, a wide real grin",
      ].freeze

      # A sitting, one-based like the scenario numbers the old toolkit used.
      def self.scene(number)
        SCENES[(Integer(number) - 1) % SCENES.size]
      end

      # A distinct postpro heavy look per frame: postpro deals its named looks
      # through Random.new(POSTPRO_SEED), so a fixed seed per sitting gives each
      # frame a different look rather than the same one re-rolled.
      def self.grade_seed(number)
        10_000 + (Integer(number) * 977)
      end
    end
  end
end
