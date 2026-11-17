# frozen_string_literal: true

require "date"
require "thread"
require "yaml"

module Studio
  class ReplicateClient
    # The Replicate catalogue STUDIO chooses from: which models exist for
    # photographs, likeness, motion, speech and music, what each one takes as
    # input, and how it reaches a real person's face. Loaded from models.yml,
    # which is kept in step with Replicate's public catalogue.
    module Models
      PATH = File.join(__dir__, "models.yml").freeze
      VIDEO_BUDGET_LOCK = Mutex.new
      BudgetExceeded = Class.new(StandardError)
      @video_spent_usd = 0.0

      module_function

      def catalogue
        @catalogue ||= YAML.safe_load_file(PATH)
      end

      def engines = catalogue.fetch("text_to_image")

      # The motion catalogue: image-to-video models the film renderer can drive.
      # Each declares the input keys it takes, and the film engine the renderer
      # selects by default is Studio::Visual::IdeaPicture::FILM.
      def film_engines = catalogue.fetch("image_to_video")

      def film_engine(name)
        film_engines.fetch(name.to_s) do
          raise ArgumentError, "unknown film engine #{name}; try one of #{film_engines.keys.join(", ")}"
        end
      end

      # A deterministic estimate for the selected MiniMax engine. Replicate
      # bills output and reference-video input seconds; when source durations
      # are not supplied, reserve the model's documented maximum of 15 seconds.
      def video_cost_usd(name, input, today: Date.today)
        raise ArgumentError, "video input must be a Hash" unless input.is_a?(Hash)

        spec = film_engine(name)
        pricing = spec.fetch("pricing")
        raw_duration = input_value(input, "duration") || 5
        valid_integer = raw_duration.is_a?(Integer) || raw_duration.to_s.match?(/\A\d+\z/)
        raise ArgumentError, "MiniMax video duration must be an integer from 4 to 15 seconds" unless valid_integer

        duration = Integer(raw_duration)
        raise ArgumentError, "MiniMax video duration must be an integer from 4 to 15 seconds" unless duration.between?(4, 15)

        rates = pricing.fetch("usd_per_second")
        resolution = input_value(input, "resolution") || "768P"
        list_rate = rates.is_a?(Hash) ? Float(rates.fetch(resolution.to_s)) : Float(rates)
        promotion = Date.iso8601(pricing.fetch("promotion_until"))
        rate = if today <= promotion
                 promo = pricing.fetch("promotional_usd_per_second")
                 promo.is_a?(Hash) ? Float(promo.fetch(resolution.to_s)) : Float(promo)
               else
                 list_rate
               end

        references = Array(input_value(input, "reference_video_urls"))
        max_references = Integer(pricing.fetch("max_reference_videos", 3))
        raise ArgumentError, "too many MiniMax reference videos (max #{max_references})" if references.length > max_references

        reference_seconds = references.empty? ? 0 : Float(pricing.fetch("max_reference_video_seconds", 15))
        (duration + reference_seconds) * rate
      end

      # Reserve before the paid request, under one lock, so concurrent STUDIO
      # jobs cannot both observe the same remaining allowance and overspend it.
      # An ambiguous network failure keeps its reservation: the provider may
      # already have started a billable prediction.
      def reserve_video_spend!(name, input, today: Date.today)
        return unless film_engines.dig(name.to_s, "pricing")

        cost = video_cost_usd(name, input, today:)
        call_cap = video_budget_limit("call_usd", "STUDIO_VIDEO_CALL_CAP_USD")
        run_budget = video_budget_limit("run_usd", "STUDIO_VIDEO_BUDGET_USD")
        raise BudgetExceeded, format("video estimate $%.3f exceeds the $%.2f per-call cap", cost, call_cap) if cost > call_cap

        VIDEO_BUDGET_LOCK.synchronize do
          spent = @video_spent_usd.to_f
          if spent + cost > run_budget
            raise BudgetExceeded, format("video estimate $%.3f exceeds the $%.2f remaining run budget", cost, run_budget - spent)
          end
          @video_spent_usd = spent + cost
        end
        cost
      end

      def video_budget_spent
        VIDEO_BUDGET_LOCK.synchronize { @video_spent_usd.to_f }
      end

      def reset_video_budget!
        VIDEO_BUDGET_LOCK.synchronize { @video_spent_usd = 0.0 }
      end

      def input_value(input, name)
        input[name] || input[name.to_sym]
      end

      def video_budget_limit(key, environment)
        configured = Float(catalogue.fetch("video_budget").fetch(key))
        override = ENV[environment].to_s.strip
        return configured if override.empty?

        requested = Float(override)
        raise ArgumentError, "#{environment} must be a positive finite amount" unless requested.positive? && requested.finite?

        [configured, requested].min
      end

      def default_engine = catalogue.fetch("default_engine")

      def free_models = Array(catalogue["free_models"])

      def free?(name) = free_models.include?(name.to_s)

      # The order to try for one render: the primary engine first, then the
      # fallback chain, which ends in Replicate's free tier so a render never
      # dies for want of credit. When the primary is itself free, stay inside the
      # free tier so --free never spends on a paid model. "$subject_lora" stays
      # as written; the pipeline resolves it to the subject's own trained model.
      def chain_for(primary)
        return ([primary] + free_models).uniq if free?(primary)

        [primary, *Array(catalogue["fallback_chain"])].compact.reject(&:empty?).uniq
      end

      # How a model reaches a likeness: "reference" (the subject's own
      # photographs are input), "lora" (a trained adapter) or "text" (described).
      def engine(name)
        engines.fetch(name.to_s) { raise ArgumentError, "unknown engine #{name}; try one of #{engines.keys.join(", ")}" }
      end

      def with_likeness(kind) = engines.select { |_, spec| spec["likeness"] == kind }

      def inputs_for(name) = engine(name).fetch("inputs")
    end
  end
end
