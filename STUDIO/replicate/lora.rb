# STUDIO/replicate/lora.rb - LoRA Dataset Compiler & Training Orchestrator
module Studio
  module Replicate
    class LoraTrainer
      DEFAULT_CONFIG = {
        resolution: 1024,
        train_batch_size: 2,
        gradient_accumulation_steps: 4,
        learning_rate: 1e-4,
        lr_scheduler: "cosine",
        optimizer: "AdamW",
        max_train_steps: 1200,
        network_dim: 32,      # LoRA rank
        network_alpha: 16
      }.freeze

      def self.prepare_dataset(raw_images_dir:, output_dir:, trigger_word: "analog_film_v5")
        FileUtils.mkdir_p(output_dir)

        # Validate, resize to square resolution, and generate caption text files
        Dir.glob("#{raw_images_dir}/*.{jpg,png}").each_with_index do |img_path, idx|
          filename = "img_#{idx.to_s.rjust(3, '0')}"
          dest_img = File.join(output_dir, "#{filename}.jpg")
          dest_txt = File.join(output_dir, "#{filename}.txt")

          # Resize & normalize via ImageMagick/vips pipeline
          system("convert #{Shellwords.escape(img_path)} -resize 1024x1024^ -gravity center -extent 1024x1024 #{Shellwords.escape(dest_img)}")

          # Write companion caption file enforcing trigger word
          File.write(dest_txt, "#{trigger_word}, high analog quality, 35mm photograph, natural grain")
        end

        { status: "dataset_ready", count: Dir.glob("#{output_dir}/*.jpg").size }
      end

      def self.generate_training_script(config_name: "portra_lora", output_path: "config/train_portra.toml")
        toml_content = <<~TOML
          [model_arguments]
          pretrained_model_name_or_path = "stabilityai/stable-diffusion-xl-base-1.0"
          v2 = false

          [dataset_arguments]
          train_data_dir = "data/lora_training_sets/#{config_name}"
          resolution = 1024

          [training_arguments]
          output_dir = "models/lora/#{config_name}"
          output_name = "#{config_name}_v1"
          epochs = 10
          learning_rate = 1e-4
          save_every_n_epochs = 2
          mixed_precision = "bf16"
          save_precision = "bf16"
          network_module = "networks.lora"
          network_dim = 32
          network_alpha = 16
        TOML

        File.write(output_path, toml_content)
        output_path
      end
    end
  end
end
