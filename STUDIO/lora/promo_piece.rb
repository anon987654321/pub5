# frozen_string_literal: true

require_relative "selfie_series"
require_relative "../replicate/promo"

module Studio
  module Visual
    # The promo run for one subject, end to end: a developed still if the
    # subject has none, clips that continue from one another, and the cut with
    # the dilla bed. House defaults throughout, so the operator names the
    # subject and nothing else.
    class PromoPiece
      CLIPS = 3
      SECONDS = 10
      LOOK = "dilla_heavy"
      AUDIO = File.expand_path("../../dilla/dilla.wav", __dir__)

      def initialize(subject:, audio: AUDIO, series: nil)
        @subject = subject.to_s
        @audio = audio
        @series = series || Studio::Visual::SelfieSeries.new(subject: @subject)
      end

      def run(clips: CLIPS, seconds: SECONDS, look: LOOK)
        still = @series.latest_still || Array(@series.run(count: 1)).first
        raise "no developed still for #{@subject}" unless still

        piece = @series.film_piece(clips:, seconds:, still:)
        out = File.join(File.dirname(still), "#{@subject}_promo.mp4")
        Studio::Promo.render(clips: piece, audio: @audio, out:, look:, clip_seconds: seconds)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: ruby STUDIO/lora/promo_piece.rb SUBJECT [AUDIO]" if ARGV.empty?

  subject, audio = ARGV
  options = audio ? { subject:, audio: } : { subject: }
  puts Studio::Visual::PromoPiece.new(**options).run
end
