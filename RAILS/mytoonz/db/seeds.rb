# frozen_string_literal: true

# Demo records are local fixtures for development and test. Never create a
# production account with a source-controlled password.
if Rails.env.production?
  puts "MyToonz production seed: no default account or demo data is created."
else
  require "faker"

  scale = (ENV["SEED_SCALE"] || 4).to_i.clamp(1, 15)

  ActiveRecord::Base.connection.disable_referential_integrity do
    %w[Reaction ComicStrip User].each do |model_name|
      begin
        model = model_name.constantize
        model.delete_all if model.respond_to?(:table_exists?) && model.table_exists?
      rescue NameError, StandardError
        # An optional model or table may not exist in a fresh local database.
      end
    end
  end

  puts "Seeding local MyToonz demo data (scale=#{scale})..."

  num_users = (30 * scale).clamp(5, 400)
  users = num_users.times.map do |index|
    User.create!(
      email_address: "toon#{index}@mytoonz.example",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  num_strips = (45 * scale).clamp(5, 900)
  strips = num_strips.times.map do
    ComicStrip.create!(
      user: users.sample,
      prompt: Faker::Lorem.sentence(word_count: rand(6..14)),
      style: ComicStrip::STYLES.sample,
      status: "completed",
      image_urls: []
    )
  end

  strips.each do |strip|
    rand(2..(18 * scale).clamp(2, 90)).times do
      strip.reactions.create!(user: users.sample, kind: %w[like love laugh].sample)
    rescue StandardError
      # The local demo remains useful when the optional reactions table is absent.
    end
  end

  puts "MyToonz demo ready: #{users.size} local users, #{strips.size} comic strips."
end
