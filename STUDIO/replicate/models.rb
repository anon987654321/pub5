# frozen_string_literal: true

require "yaml"

module Studio
  class ReplicateClient
    # The Replicate catalogue STUDIO chooses from: which models exist for
    # photographs, likeness, motion, speech and music, what each one takes as
    # input, and how it reaches a real person's face. Loaded from models.yml,
    # which is kept in step with Replicate's public catalogue.
    module Models
      PATH = File.join(__dir__, "models.yml").freeze

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
