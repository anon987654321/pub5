#!/usr/bin/env ruby
# frozen_string_literal: true
require 'fileutils'
require_relative 'fm_modulator'

module Master
  module TTS
    class OneShotWorker
      def synthesize_with_dsp(text, raw_audio_path)
        processed_wav = "/tmp/master_voice_dsp_#{$$}.wav"
        
        begin
          # Apply FM Modulation and DSP chain
          modulator = DSP::FMModulator.new
          modulator.apply(raw_audio_path, processed_wav)
          
          # Stream the processed audio to the system output
          system("aplay", processed_wav, exception: true) || system("afplay", processed_wav, exception: true)
        ensure
          FileUtils.rm_f(processed_wav)
        end
      end
    end
  end
end
