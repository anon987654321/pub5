# frozen_string_literal: true
require 'fileutils'
require_relative 'fm_modulator'

module Master
  module TTS
    class OneShotWorker
      def synthesize_with_dsp(text, raw_audio_path)
        processed_wav = "/tmp/master_voice_dsp_#{$$}.wav"
        
        begin
          modulator = DSP::FMModulator.new
          modulator.apply(raw_audio_path, processed_wav)
          
          system("aplay", processed_wav, exception: true) || system("afplay", processed_wav, exception: true)
        ensure
          FileUtils.rm_f(processed_wav)
        end
      end
    end
  end
end
