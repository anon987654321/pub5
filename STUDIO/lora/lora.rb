# frozen_string_literal: true

# STUDIO/lora/lora.rb
# Consolidated LoRA generation knowledge, craft vocabularies, and anti-patterns.
# Recovered from pub4 history, ar5iv research on diffusion prompt optimizers,
# and empirical testing of FLUX.1-dev realism boundaries.

module Studio
  module Lora
    # Words that pull the image toward rendered concept art or retouched skin,
    # which destroys photographic realism. Warned rather than stripped, because
    # the prompt is the caller's, but the caller should know the cost.
    #
    # Research: "8k" and "concept art" pull SD/FLUX toward optimiser averages
    # (ar5iv.labs.arxiv.org/html/2212.09611, 2209.11711). "Flawless" names the
    # retouched skin this vocabulary exists to avoid.
    BACKFIRING_WORDS = %w[
      8k 4k concept_art octane_render artstation flawless smooth_skin 
      perfect_skin airbrushed cgi 3d_render digital_art illustration
      masterpiece best_quality ultra_detailed
    ].freeze

    # Core photographic craft vocabulary for realistic, candid selfies.
    # Focuses on natural asymmetry, real lighting, and authentic moments.
    # This replaces generic "beautiful" prompts which pull CLIP toward the
    # symmetrical stock-model average, fighting the LoRA's likeness.
    PHOTOGRAPHIC_CRAFT = [
      "shot on a smartphone, natural skin texture, visible pores, slight asymmetry",
      "candid moment, unposed, relaxed expression, natural lighting",
      "well-framed, whole head in frame with headroom, subject slightly off-centre",
      "directional light with real shadows, sharp eyes, no text in the frame",
      "authentic environment, lived-in details, no studio backdrop",
      "warm faces around a laugh, genuine micro-expression"
    ].freeze

    # Radically different scene, lighting, and composition matrices.
    # Ensures every generated frame has distinct environmental and compositional DNA.
    # Prevents the "10 identical photos in different locations" problem.
    SCENE_MATRIX = [
      { environment: "tropical beach, turquoise sea, palm trees softly out of focus", lighting: "golden_hour", lens: "wide_angle", composition: "low angle, sky prominent" },
      { environment: "dense jungle canopy, dappled green light, rainforest trailhead", lighting: "overcast", lens: "standard", composition: "eye level, foliage framing" },
      { environment: "rooftop downtown, skyscraper skyline, urban haze", lighting: "blue_hour", lens: "telephoto", composition: "high angle, city below" },
      { environment: "night market, neon signs, tropical stalls glowing", lighting: "mixed_neon", lens: "fast_prime", composition: "crowded background, shallow depth" },
      { environment: "monsoon rain shelter, wet street, shophouses", lighting: "diffused", lens: "standard", composition: "reflection in puddle, candid" },
      { environment: "cable-car platform, cloud forest, mist", lighting: "fog", lens: "wide_angle", composition: "atmospheric perspective, vast background" },
      { environment: "tea plantation, rolling hills, warm humid light", lighting: "morning_mist", lens: "telephoto", composition: "compression, layered hills" },
      { environment: "balcony overlooking valley, dusk, city lights below", lighting: "twilight", lens: "standard", composition: "subject foreground, bokeh lights" },
      { environment: "busy street, Petronas Towers rising behind, humid afternoon", lighting: "hard_direct", lens: "wide_angle", composition: "leading lines, dynamic" },
      { environment: "indoor cafe, bright window light, relaxed candid", lighting: "window_light", lens: "portrait", composition: "Rembrandt lighting, intimate" }
    ].freeze

    # Postpro heavy preset mapping to ensure radically different grades per frame.
    # Avoids the "random heavy" repetition (which postpro docs warn loses colour/shapes 69% of the time)
    # by explicitly cycling distinct, deliberate looks.
    HEAVY_PRESETS = %w[
      kodak_portra
      ilford_hp5
      cinematic_teal
      vintage_fade
      high_contrast_bw
      warm_analog
      cool_digital
      cross_process
      silver_gelatin
      dream_subtle
    ].freeze

    # Enhance a base prompt with scene-specific craft vocabulary.
    def self.enhance_prompt(base_prompt, scene_idx)
      scene = SCENE_MATRIX[scene_idx % SCENE_MATRIX.size]
      craft = PHOTOGRAPHIC_CRAFT.sample
      "#{base_prompt}, #{scene[:environment]}, #{scene[:lighting]} lighting, #{scene[:lens]} lens, #{scene[:composition]}, #{craft}"
    end

    # Sanitize a prompt by removing backfiring words that degrade realism.
    def self.sanitize_prompt(prompt)
      cleaned = prompt.dup
      BACKFIRING_WORDS.each do |word|
        cleaned = cleaned.gsub(/\b#{word}\b/i, "")
      end
      cleaned.squeeze(" ").strip
    end

    # Get a distinct heavy preset for a given frame index to ensure variety.
    def self.preset_for_frame(frame_idx)
      HEAVY_PRESETS[frame_idx % HEAVY_PRESETS.size]
    end
  end
end
