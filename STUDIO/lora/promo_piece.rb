# frozen_string_literal: true

require "json"

require_relative "selfie_series"
require_relative "../replicate/promo"

module Studio
  module Visual
    # The promo run for one subject, end to end: a developed still if the
    # subject has none, clips that continue from one another, and the cut with
    # the dilla bed. House defaults throughout, so the operator names the
    # subject and nothing else.
    class PromoPiece
      # Four ten-second clips is the longest piece the film renderer allows and
      # the shortest that clears thirty seconds after the crossfades.
      CLIPS = 4
      SECONDS = 10
      LOOK = "dilla_print"
      AUDIO = File.expand_path("../dilla/dilla.wav", __dir__)

      def initialize(subject:, audio: AUDIO, series: nil)
        @subject = subject.to_s
        @audio = audio
        @series = series || Studio::Visual::SelfieSeries.new(subject: @subject)
      end

      def run(clips: CLIPS, seconds: SECONDS, look: LOOK)
        still = @series.latest_still || Array(@series.run(count: 1)).first
        raise "no developed still for #{@subject}" unless still

        piece = filmed(still:, clips:, seconds:) || film(still:, clips:, seconds:)
        out = File.join(File.dirname(still), "#{@subject}_promo.mp4")
        Studio::Promo.render(clips: piece, audio: @audio, out:, look:, clip_seconds: seconds)
      end

      # Motion is the expensive half of the piece. Clips already filmed from
      # this still at this length are reused, so a failed cut costs nothing to
      # retry.
      def filmed(still:, clips:, seconds:)
        path = manifest_path(still)
        return nil unless File.file?(path)

        recorded = JSON.parse(File.read(path))
        return nil unless recorded["still"] == still && recorded["seconds"] == seconds

        kept = Array(recorded["clips"])
        return nil unless kept.size == clips && kept.all? { |clip| File.file?(clip) }

        kept
      rescue JSON::ParserError
        nil
      end

      def film(still:, clips:, seconds:)
        piece = @series.film_piece(clips:, seconds:, still:)
        path = manifest_path(still)
        File.write(path, JSON.pretty_generate("still" => still, "seconds" => seconds, "clips" => piece))
        File.chmod(0o600, path)
        piece
      end

      def manifest_path(still) = File.join(File.dirname(still), "#{@subject}_promo_clips.json")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: ruby STUDIO/lora/promo_piece.rb SUBJECT [AUDIO]" if ARGV.empty?

  subject, audio = ARGV
  options = audio ? { subject:, audio: } : { subject: }
  puts Studio::Visual::PromoPiece.new(**options).run
end
