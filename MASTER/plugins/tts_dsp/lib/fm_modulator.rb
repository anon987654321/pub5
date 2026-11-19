# frozen_string_literal: true

module Master
  module TTS
    module DSP
      class FMModulator
        # Apply FM synthesis and spatial delay to raw PCM/WAV audio.
        # Uses the OpenBSD sox toolchain for the heavy lifting.
        def apply(raw_audio_path, output_path, modulator_freq: 5.0, depth: 40)
          chain = [
            "tremolo", modulator_freq.to_s, depth.to_s,
            "pitch", "-15", 
            "echo", "0.8", "0.88", "60", "0.4",
            "highpass", "200",
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
