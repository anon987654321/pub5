#!/usr/bin/env ruby
# frozen_string_literal: true

module Master
  module TTS
    module DSP
      class FMModulator
        # Apply FM synthesis and spatial delay to raw PCM/WAV audio.
        # Uses the OpenBSD sox toolchain for the heavy lifting.
        def apply(raw_audio_path, output_path, modulator_freq: 5.0, depth: 40)
          chain = [
            # 1. FM Modulation (Tremolo/Vibrato artifact)
            # tremolo speed(Hz) depth(%)
            "tremolo", modulator_freq.to_s, depth.to_s,
            
            # 2. Pitch shift for the "cooler" digital artifact (slight detune)
            "pitch", "-15", 
            
            # 3. Spatial Delay (Dub/Space echo effect)
            # echo delay-in delay-out decay
            "echo", "0.8", "0.88", "60", "0.4",
            
            # 4. High-pass filter to remove mud, keeping it crisp
            "highpass", "200",
            
            # 5. Reverb for the "stillness by default" spatial air
            "reverb", "40", "30", "50", "100", "20", "0"
          ]
          
          cmd = ["sox", raw_audio_path, output_path] + chain
          system(*cmd, exception: true)
          
          output_path
        end
      end
    end
  end
end
