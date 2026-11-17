# frozen_string_literal: true

module Brgen
  # db/seeds.rb's takeaway step, kept whole: the restaurants, each menu in the
  # restaurant's own cuisine, orders and reviews, and the delivery drivers.
  # The caller sets the tenant; CityTenantable adds belongs_to :city, and the
  # string column :city is the display label only, not the association.
  module TakeawaySeed
    def self.seed!(users:, city:, scale:)
      restaurants = seed_restaurants(users, city.name, scale)
      restaurants.each { |restaurant| seed_menu(restaurant) }
      restaurants.sample(10).each { |restaurant| seed_order(restaurant, users.sample) }
      seed_drivers(users)
      restaurants
    end

    # Cuisine now travels with the restaurant name (PlausibleContent.restaurant_for).
    def self.seed_restaurants(users, city_label, scale)
      num_rest = (15 * scale).clamp(5, 100)
      num_rest.times.map do |i|
        # Faker::Restaurant.name is US-styled ("The Rusty Spoon") and the address was
        # a Faker street that doesn't exist in Bergen. Name and cuisine come from the
        # same pair so a place called "Ramen Bergen" isn't filed as Mexican.
        name, cuisine = Brgen::PlausibleContent.restaurant_for(i)
        Takeaway::Restaurant.create!(
          user: users.sample,
          name: name,
          cuisine_type: cuisine,
          address: Brgen::PlausibleContent.street_address,
          active: true, demo: true,
          delivery_fee_cents: rand(2000..6000),
          min_order_cents: rand(8000..15_000),
          latitude: 60.39 + rand(-0.04..0.04),
          longitude: 5.33 + rand(-0.04..0.04)
        ).tap { |restaurant| restaurant.update_column(:city, city_label) }
      end
    end

    def self.seed_menu(rest)
      # Menu now matches the restaurant's own cuisine, in Norwegian, rather than
      # Faker::Food's English dishes served at a Bergen kebab house.
      dishes = Brgen::PlausibleContent.dishes_for(rest.cuisine_type)
      dishes.sample(rand(4..dishes.size)).each do |(name, description)|
        Takeaway::MenuItem.create!(
          restaurant: rest,
          name: name,
          description: description,
          price_cents: rand(6000..18_000),
          available: true
        )
      end
    end

    # Orders + reviews
    #
    # Build the line items before saving, the way Takeaway::OrdersController#create
    # does. This used to create! the order bare and attach items afterwards, and
    # Takeaway::Order#meets_minimum_order reads `order_items.target` -- so the
    # subtotal was 0.00 at validation time and every restaurant with a
    # min_order_cents rejected its own seed order:
    #
    #   ActiveRecord::RecordInvalid: Minimum order for Døner Ekspress Åsane is
    #   122.76 NOK — your subtotal is 0.00 NOK.
    #
    # That took down `db:seed:replant`, which is a stage of vps_ci.sh, which is a
    # stage of vps-deploy -- so brgen could not be deployed at all, while the
    # validation itself is correct and the real checkout path was always fine.
    # Enough menu items to clear any threshold the restaurant advertises.
    def self.seed_order(rest, buyer)
      # includes(:restaurant) is load-bearing, not decoration: ApplicationRecord sets
      # strict_loading_by_default in every environment, and building an OrderItem
      # reads menu_item.restaurant, so dropping the preload raises
      # StrictLoadingViolationError here rather than degrading to an extra SELECT.
      menu = Takeaway::MenuItem.available.includes(:restaurant)
                               .where(restaurant: rest).order(Arel.sql("RANDOM()")).to_a
      return if menu.empty?

      order = Takeaway::Order.new(
        user: buyer,
        restaurant: rest,
        status: %w[pending out_for_delivery delivered].sample,
        delivery_address: Faker::Address.street_address,
        special_instructions: [ nil, Faker::Lorem.sentence ].sample
      )

      subtotal = 0
      minimum = rest.min_order_cents.to_i
      menu.each do |item|
        break if order.order_items.size >= 2 && subtotal >= minimum

        quantity = rand(1..2)
        order.order_items.build(menu_item: item, quantity: quantity, unit_price_cents: item.price_cents)
        subtotal += item.price_cents.to_i * quantity
      end
      # A restaurant whose whole menu cannot reach its own minimum is bad seed data,
      # not a reason to abort the seed.
      return if subtotal < minimum

      order.save!
      order.calculate_totals!
      order.record_activity!("TakeawayOrder") if order.respond_to?(:record_activity!)

      # Review
      return unless order.status == "delivered"

      Takeaway::Review.create!(
        user: buyer,
        restaurant: rest,
        order: order,
        rating: rand(3..5),
        body: Faker::Restaurant.review
      )
    end

    # Delivery drivers
    def self.seed_drivers(users)
      5.times do
        Takeaway::DeliveryDriver.create!(
          user: users.sample,
          vehicle_type: Takeaway::DeliveryDriver::VEHICLE_TYPES.sample,
          available: [ true, false ].sample,
          current_lat: 60.39 + rand(-0.03..0.03),
          current_lng: 5.33 + rand(-0.03..0.03)
        )
      end
    end

    # A real, owned starter tenant migrated from the retired standalone
    # Mr Damascy application. This seed is opt-in and never runs in production:
    # the customer accounts, mock payments, and fake orders from the old app
    # are intentionally not copied into Brgen.
    def self.seed_mrdamascy!(owner:, city:)
      result = Takeaway::Provisioner.create_restaurant!(
        owner:,
        city:,
        attributes: {
          name: "Mr. Damascy — Danmarksplass",
          description: "Shawarma, kebab, mezze and Damascus favourites from Danmarksplass.",
          address: "Solheimsgaten 60, 5054 Bergen",
          cuisine_type: "Kebab",
          phone: "955 55 600",
          delivery_fee_cents: 2_900,
          min_order_cents: 15_000,
        },
      )
      restaurant = result.restaurant
      store = result.store

      store.update!(active: true)
      restaurant.update!(
        active: true,
        demo: true,
        metadata: {
          "seed_source" => "RAILS/mrdamascy",
          "seed_profile" => "mrdamascy-bergen",
          "opening_hours_text" => "Man–Fre 11–21 · Lør–Søn 14–21",
          "opening_hours_text_en" => "Mon–Fri 11am–9pm · Sat–Sun 2pm–9pm",
          "delivery_zones" => MRDAMASCY_DELIVERY_ZONES,
          "promotions" => MRDAMASCY_PROMOTIONS,
          "brand_assets" => {
            "logo" => "takeaway/mrdamascy/brand/logo-transparent.svg",
            "icon" => "takeaway/mrdamascy/brand/icon.svg",
            "og_card" => "takeaway/mrdamascy/brand/og-card.png",
            "screenshots" => %w[
              takeaway/mrdamascy/screenshots/menu.jpg
              takeaway/mrdamascy/screenshots/tracking.jpg
            ],
          },
        },
      )

      categories = {}
      MRDAMASCY_CATEGORIES.each do |key, name, _name_en, _emoji, _position|
        categories[key] = restaurant.menu_categories.find_or_create_by!(name:)
      end

      MRDAMASCY_ITEMS.each do |row|
        category_key, name, name_en, origin, heat, price_kr, emoji, badges,
          weight_g, description, photo_name, options = row
        item = restaurant.menu_items.find_or_initialize_by(name:)
        item.assign_attributes(
          menu_category: categories.fetch(category_key),
          description:,
          price_cents: (price_kr * 100).to_i,
          available: true,
          vegetarian: Array(badges&.split(",")).include?("veg"),
          vegan: false,
          allergens: nil,
          metadata: {
            "name_en" => name_en,
            "origin" => origin,
            "heat" => heat,
            "emoji" => emoji,
            "badges" => badges.to_s.split(",").reject(&:empty?),
            "weight_g" => weight_g,
            "options" => options,
          },
        )
        item.save!

        photo_path = Rails.root.join(
          "engines/marketplace/engines/takeaway/app/assets/images/takeaway/mrdamascy/food",
          photo_name,
        )
        if File.file?(photo_path) && !item.photo.attached?
          File.open(photo_path, "rb") do |image|
            item.photo.attach(io: image, filename: photo_name, content_type: "image/jpeg")
          end
        end
      end

      hours = {
        1 => [11 * 60, 21 * 60],
        2 => [11 * 60, 21 * 60],
        3 => [11 * 60, 21 * 60],
        4 => [11 * 60, 21 * 60],
        5 => [11 * 60, 21 * 60],
        6 => [14 * 60, 21 * 60],
        0 => [14 * 60, 21 * 60],
      }
      hours.each do |weekday, (opens_minute, closes_minute)|
        hour = restaurant.opening_hours.find_or_initialize_by(weekday:)
        hour.assign_attributes(opens_minute:, closes_minute:)
        hour.save!
      end

      cover_path = Rails.root.join(
        "engines/marketplace/engines/takeaway/app/assets/images/takeaway/mrdamascy/brand/og-card.png",
      )
      if File.file?(cover_path) && !restaurant.cover.attached?
        File.open(cover_path, "rb") do |image|
          restaurant.cover.attach(io: image, filename: "mrdamascy-og-card.png", content_type: "image/png")
        end
      end

      restaurant
    end

    MRDAMASCY_CATEGORIES = [
      ["wraps", "Wraps & Ruller", "Wraps & Rolls", "🌯", 1],
      ["tallerker", "Tallerker", "Plates", "🍽️", 2],
      ["tilbehor", "Tilbehør", "Sides", "🍟", 3],
      ["drikke", "Drikke", "Drinks", "🥤", 4],
      ["desserter", "Desserter", "Desserts", "🍮", 5],
      ["bokser", "Bokser", "Boxes", "🎁", 6],
    ].freeze

    MRDAMASCY_DELIVERY_ZONES = [
      ["5054", "Danmarksplass", 29, 150, 15],
      ["5003", "Bergen sentrum", 39, 200, 25],
      ["5004", "Strandgaten", 29, 150, 15],
      ["5006", "Vågsbunnen", 29, 150, 20],
      ["5007", "Bergenhus vest", 35, 150, 25],
      ["5008", "Nøstet", 35, 150, 25],
      ["5009", "Møhlenpris", 35, 150, 25],
      ["5015", "Nygård", 39, 200, 30],
      ["5017", "Årstad", 39, 200, 30],
      ["5020", "Møllendal", 45, 250, 35],
      ["5141", "Fyllingsdalen", 49, 300, 40],
      ["5160", "Laksevåg", 49, 300, 40],
      ["5221", "Nesttun", 55, 300, 45],
    ].map do |postcode, name, fee_kr, minimum_kr, eta|
      {
        "postcode" => postcode,
        "name" => name,
        "fee_cents" => fee_kr * 100,
        "minimum_cents" => minimum_kr * 100,
        "eta_minutes" => eta,
      }
    end.freeze

    MRDAMASCY_PROMOTIONS = [
      { "code" => "SAHTEIN10", "kind" => "percent", "value" => 10, "minimum_cents" => 0, "description" => "First order" },
      { "code" => "YALLA25", "kind" => "fixed", "value_cents" => 2_500, "minimum_cents" => 25_000, "description" => "25 NOK off orders above 250 NOK" },
      { "code" => "GRATISLEVERING", "kind" => "free_delivery", "value" => 0, "minimum_cents" => 30_000, "description" => "Free delivery above 300 NOK" },
      { "code" => "FAMILIE15", "kind" => "percent", "value" => 15, "minimum_cents" => 40_000, "description" => "15% off family orders above 400 NOK" },
    ].freeze

    # The source app's option groups are retained as structured metadata for
    # the next menu-option UI migration. Brgen's current checkout still charges
    # only its server-stated base price until that UI and order-line contract is
    # implemented; it never pretends these options were selected.
    MRDAMASCY_WRAP_OPTIONS = [
      *[
        ["Toum", "Toum (garlic sauce)", 0, true],
        ["Tarator", "Tarator (tahini sauce)", 0, false],
        ["Yoghurt-urt", "Yoghurt & herbs", 0, false],
        ["Syrisk sterk chili", "Syrian hot chili", 0, false],
      ].map { |name, name_en, price, default_on| { "name" => name, "name_en" => name_en, "kind" => "sauce", "price_cents" => price * 100, "default_on" => default_on } },
      *[
        ["Salat", "Salad", true], ["Tomat", "Tomato", true], ["Agurk", "Cucumber", true],
        ["Rødløk", "Red onion", false], ["Rødkål", "Red cabbage", true], ["Mais", "Corn", false],
        ["Jalapeño", "Jalapeño", false], ["Sylteagurk", "Pickles", true],
      ].map { |name, name_en, default_on| { "name" => name, "name_en" => name_en, "kind" => "topping", "price_cents" => 0, "default_on" => default_on } },
      *[
        ["Ekstra kjøtt", "Extra meat", 25], ["Dobbel ost", "Double cheese", 15], ["Ekstra brød", "Extra bread", 10],
      ].map { |name, name_en, price| { "name" => name, "name_en" => name_en, "kind" => "extra", "price_cents" => price * 100, "default_on" => false } },
    ].freeze

    MRDAMASCY_ITEMS = [
      ["wraps", "Damaskus Kylling Shawarma", "Damascus Chicken Shawarma", "damaskus", 1, 129, "🌯", "signature", 450, "Kylling fra spettet, toum og sylteagurk — Damaskus' egen favoritt.", "damaskus-kylling-shawarma.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Beirut Lam Shawarma", "Beirut Lamb Shawarma", "beirut", 1, 139, "🥙", nil, nil, "Mager lam med granateple-løk og tarator — Beirut-disiplin.", "beirut-lam-shawarma.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Berlin Gemüse Kebap", "Berlin Gemüse Kebap", "berlin", 1, 139, "🥬", "veg", nil, "Grillet grønnsak og rikelig salat — køens favoritt fra Berlin.", "berlin-gemuse-kebap.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Adana Sterk Dürum", "Adana Hot Dürum", "adana", 3, 149, "🔥", nil, nil, "Krydret kjøttfars etter Adana-oppskriften. Sterk!", "adana-sterk-durum.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Bergen Kebab-i-Dürum", "Bergen Kebab-i-Dürum", "bergen", 2, 139, "🧔", "salatbar", nil, "Kvartover-ærlig kebab med salatbar akkurat som hjemme i Bergen.", "bergen-kebab-i-durum.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Dubai Gatens Shawarma", "Dubai Street Shawarma", "dubai", 1, 135, "🍟", nil, nil, "Pommes i rullen — gatens beste triks fra Dubai.", "dubai-gatens-shawarma.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["wraps", "Blomkål-Pita Miznon-stil", "Cauliflower Pita Miznon-style", "tel_aviv", 0, 129, "🥦", "veg,signature", nil, "Helstekt blomkål i pita — Miznon-spøken, Tel Aviv.", "blomkal-pita.jpg", MRDAMASCY_WRAP_OPTIONS],
      ["tallerker", "Bursa İskender", "Bursa İskender", "bursa", 1, 189, "🧈", "signature", 550, "Smør, tomatsaus og yoghurt — 1867-ritualen fra Bursa.", "bursa-iskender.jpg",
        [{ "name" => "Ekstra smør", "name_en" => "Extra butter", "kind" => "extra", "price_cents" => 1_000, "default_on" => false },
         { "name" => "Ekstra yoghurt", "name_en" => "Extra yoghurt", "kind" => "extra", "price_cents" => 1_500, "default_on" => false }]],
      ["tallerker", "Gaziantep Ali Nazik", "Gaziantep Ali Nazik", "gaziantep", 2, 179, "🍆", nil, nil, "Røkt aubergine og yoghurt under kebab, fra UNESCO-byen Gaziantep.", "gaziantep-ali-nazik.jpg", []],
      ["tallerker", "Familie Fest-Mezze", "Family Feast Mezze", "damaskus", 1, 449, "🫓", "sharing", 1200, "Hele bordets fest: wraps, dips og pommes nok til alle.", "familie-fest-mezze.jpg", []],
      ["tallerker", "Stockholm Kebabpizza — helg", "Stockholm Kebabpizza — weekend", "stockholm", 2, 169, "🍕", nil, nil, "Kebab på pizza — Stockholms oppfinnelse. Kun i helgene.", "stockholm-kebabpizza.jpg", []],
      ["tallerker", "Sydney Snackpack HSP", "Sydney Snackpack HSP", "sydney", 2, 149, "🍟", "secret", nil, "Chips, kjøtt, ost og gravy — nattens ritual fra Sydney.", "sydney-snackpack-hsp.jpg", []],
      ["tilbehor", "Hvitløks-Pommes", "Garlic Fries", "bergen", 0, 59, "🍟", nil, nil, "Pommes badet i toum.", "hvitloks-pommes.jpg", []],
      ["tilbehor", "Halloumi-Pommes", "Halloumi Fries", "bergen", 0, 79, "🧀", nil, nil, "Saltstekt halloumi over pommes.", "halloumi-pommes.jpg", []],
      ["tilbehor", "Kısır Bulgursal", "Kısır Bulgur Salad", "gaziantep", 0, 49, "🥗", "veg", nil, "Syrlig bulgursalat med granateple.", "kisir-bulgursal.jpg", []],
      ["tilbehor", "Syltebolle", "Pickle", "damaskus", 0, 29, "🥒", nil, nil, "Én syrisk sylteagurk, kjøkkenets kompliment.", "syltebolle.jpg", []],
      ["drikke", "Ayran", "Ayran", "bursa", 0, 35, "🥛", nil, nil, "Saltet yoghurtdrikk — kebabens beste venn.", "ayran.jpg", []],
      ["drikke", "Şalgam", "Şalgam", "adana", 0, 35, "🍅", nil, nil, "Gjæret turnipsdrikk, Adana-stil.", "salgam.jpg", []],
      ["drikke", "Tamarind-drikk", "Tamarind Drink", "damaskus", 0, 39, "🍹", nil, nil, "Søt-sur tamarind, servert kjølig.", "tamarind-drikk.jpg", []],
      ["drikke", "Jallab", "Jallab", "beirut", 0, 39, "🍇", nil, nil, "Druemelasse, rose og pinjekjerner.", "jallab.jpg", []],
      ["drikke", "Myntesitronlimonade", "Mint Lemonade", "damaskus", 0, 45, "🍋", nil, nil, "Fersk mynte og sitron, presset i dag.", "myntesitronlimonade.jpg", []],
      ["desserter", "Baklava fra Gaziantep", "Baklava from Gaziantep", "gaziantep", 0, 69, "🍯", nil, nil, "Pistasj, honning og mange lag.", "baklava.jpg", []],
      ["desserter", "Knefeh fra Damaskus", "Knefeh from Damascus", "damaskus", 0, 79, "🧀", "signature", nil, "Varm ost, semulegrot og sirup — Damaskus' morgen.", "knefeh.jpg", []],
      ["desserter", "Ma'moul", "Ma'moul", "damaskus", 0, 59, "🌰", nil, nil, "Semuliekaker med dadler og valnøtt.", "mamoul.jpg", []],
      ["bokser", "Damascy Boss-boks", "Damascy Boss Box", "damaskus", 0, 199, "🎁", "deal", nil, "Wrap + pommes + drikke + baklava-bite — hele måltidet i én boks.", "damascy-boss-boks.jpg",
        [{ "name" => "Ayran i boksen", "name_en" => "Ayran in the box", "kind" => "extra", "price_cents" => 0, "default_on" => false },
         { "name" => "Şalgam i boksen", "name_en" => "Şalgam in the box", "kind" => "extra", "price_cents" => 0, "default_on" => false },
         { "name" => "Brus i boksen", "name_en" => "Soft drink in the box", "kind" => "extra", "price_cents" => 0, "default_on" => false }],
      ],
    ].freeze

    private_class_method :seed_restaurants, :seed_menu, :seed_order, :seed_drivers
  end
end
