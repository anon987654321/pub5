# frozen_string_literal: true

require "yaml"
require_relative "models"

module Studio
  class ReplicateClient
    # Runs a chain of different Replicate models over one frame, each step
    # handing its output to the next. The chain is a laboratory, not a filter:
    # repair, then sharpen, then emulate stock, then grade locally.
    module Chain
      PATH = File.join(__dir__, "chains.yml").freeze
      IMAGE_INPUTS = %w[image input_image start_image first_frame_image].freeze
      # Inputs worth keeping in a receipt: what the step decided, never an
      # uploaded URL, a token, or a provider's opaque payload.
      RECORDABLE = %w[prompt prompt_strength scale_factor creativity aspect_ratio seed
                      output_format output_quality guidance_scale num_inference_steps
                      safety_tolerance].freeze

      module_function

      def definitions = @definitions ||= YAML.safe_load_file(PATH) || {}

      def definition(name)
        steps = definitions.fetch(name.to_s) { raise ArgumentError, "unknown chain: #{name}" }
        raise ArgumentError, "chain #{name} has no steps" if Array(steps).empty?

        Array(steps)
      end

      # Returns the developed frame's path and the provenance of every step.
      # A step that fails leaves the previous frame untouched and raises, so a
      # half-developed chain never passes for a finished one.
      def run(client:, frame:, definition:, subject:, directory:, budget: nil)
        steps = definition.is_a?(Array) ? definition : self.definition(definition)
        steps.each_with_index.reduce({ "path" => frame, "steps" => [], "intermediates" => [] }) do |carried, (step, index)|
          model = step.fetch("model")
          inputs = Models.any_inputs_for(model)
          key = IMAGE_INPUTS.find { |candidate| inputs.include?(candidate) }
          raise ArgumentError, "#{model} takes no image input" unless key

          budget&.consume!
          url = client.upload_file(carried.fetch("path"), subject:)
          output = client.predict(model, { key => url }.merge(step_inputs(step)), timeout: 600)
          path = File.join(directory, next_name(carried.fetch("path"), index, model, output))
          client.download_url(first_url(output), path)
          File.chmod(0o600, path)
          carried.merge(
            "path" => path,
            "steps" => carried.fetch("steps") + [record(step, model, key)],
            "intermediates" => carried.fetch("intermediates") + [carried.fetch("path")]
          )
        end
      end

      def step_inputs(step)
        (step["inputs"] || {}).transform_keys(&:to_s)
      end

      def record(step, model, key)
        decided = step_inputs(step).select { |name, _| RECORDABLE.include?(name) }
        { "model" => model, "image_input" => key, "inputs" => decided }
      end

      def next_name(previous, index, model, output)
        stem = File.basename(previous.to_s, ".*")
        slug = model.split("/").last.gsub(/[^a-z0-9]+/i, "_")
        "#{stem}_#{index + 1}_#{slug}#{extension(output)}"
      end

      def extension(output)
        url = first_url(output).to_s
        found = File.extname(url.split("?").first.to_s).downcase
        %w[.jpg .jpeg .png .webp].include?(found) ? found : ".jpg"
      end

      # Replicate answers with a string, a list, or a hash per model family.
      def first_url(output)
        case output
        when String then output
        when Array then first_url(output.first)
        when Hash
          value = output["url"] || output["image"] || output["video"] || output.values.first
          first_url(value)
        else
          raise ArgumentError, "chain step returned no output: #{output.inspect[0, 120]}"
        end
      end
    end
  end
end
