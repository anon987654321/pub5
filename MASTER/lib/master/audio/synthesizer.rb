module Master
  module Audio
    class Synthesizer
      DEFAULT_VOICE = "en-US-Neural2-F" # Smooth, warm, calming profile

      def self.speak(text)
        # Auto-mic input capture & smooth TTS generation
        audio_stream = TextToSpeech.synthesize(text, voice: DEFAULT_VOICE, smoothing: 0.85)

        # Apply subtle tape saturation and analog low-pass spatial effects
        dsp_fx = Master::Audio::DSP.apply_analog_warmth(audio_stream)

        PipeWire.broadcast(dsp_fx, bluetooth_sink: true)
      end
    end
  end
end
