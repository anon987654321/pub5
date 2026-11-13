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
