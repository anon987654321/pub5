# frozen_string_literal: true

require "minitest/autorun"

class NewsletterCaptureContractTest < Minitest::Test
  # RAILS root: the shared engine lives beside the apps at RAILS/__shared, and
  # this plugin is parked two levels further down under RAILS/plugins (see
  # RAILS/plugins/README.md and plugin.yml, parked_on 2026-11-01).
  ROOT = File.expand_path("../../..", __dir__)
  PLUGIN = File.expand_path("..", __dir__)
  CONTROLLER = File.join(PLUGIN, "frontend/newsletter_capture_controller.js")
  VIEW = File.join(PLUGIN, "views/_newsletter_signup_popup.html.erb")
  CTA = File.join(ROOT, "__shared/app/views/shared/_newsletter_cta.html.erb")
  IMPORTMAP = File.join(ROOT, "__shared/config/importmap_baseline.rb")
  BOOT = File.join(ROOT, "__shared/frontend/stimulus_boot.js")
  FOOTER = File.join(ROOT, "__shared/app/views/shared/_site_legal_footer.html.erb")
  VISUALS = File.join(ROOT, "__shared/app/services/shared/newsletter_visuals.rb")
  COMPOSER = File.join(ROOT, "__shared/app/services/shared/newsletter_composer.rb")
  EDITION = File.join(ROOT, "__shared/app/views/shared/newsletter/_edition.html.erb")
  MODEL = File.join(ROOT, "brgen/app/models/newsletter_edition.rb")

# brgen's tree beside __shared exists only in the repo checkout; brgen's own CI
# on vm23 sees /home/brgen/app, so the brgen half of the contract skips there.
def require_brgen_beside_shared!
  skip "brgen is not beside __shared in this layout" unless File.directory?(File.join(ROOT, "brgen", "app"))
end

def test_popup_is_shared_and_time_capped
  require_brgen_beside_shared!
    body = File.read(VIEW)
    controller = File.read(CONTROLLER)

    assert_includes body, %(data-controller="newsletter-capture")
    assert_includes body, %(check_box :agreed_to_marketing)
    assert_includes body, %(newsletter_popup.marketing_opt_in)
    refute_includes body, %(hidden_field_tag "email_subscription[agreed_to_marketing]", "1")
    assert_includes File.read(CTA), %(name="email_subscription[agreed_to_marketing]" value="1" required)
    assert_includes File.read(File.join(ROOT, "brgen/app/views/shared/_email_subscribe.html.erb")),
                    %(name="email_subscription[agreed_to_marketing]" value="1" required)
    controller_source = File.read(File.join(ROOT, "brgen/app/controllers/email_subscriptions_controller.rb"))
    assert_includes controller_source, %(params.dig(:email_subscription, :agreed_to_marketing) == "1")
    assert_includes body, %(newsletter_popup.reward)
    assert_includes controller, "7 * 24 * 60 * 60 * 1000"
    assert_includes controller, "showModal()"
  end

  # Parked 2026-11-01 (plugin.yml): "Render removed from _site_legal_footer;
  # stimulus import/registration and importmap pin removed". The popup renders
  # nowhere, so nothing may half-wire it back in while the plugin stays parked.
  def test_parked_popup_is_not_wired_into_the_shared_boot
    refute_includes File.read(IMPORTMAP), %(newsletter_capture),
                    "the parked popup must not be pinned in the shared baseline"
    refute_includes File.read(BOOT), %(newsletter_capture),
                    "the parked popup must not be imported by the shared boot"
    refute_includes File.read(BOOT), %(newsletter-capture),
                    "the parked popup must not be registered by the shared boot"
  end

  # Parked 2026-11-01 (plugin.yml): the popup render came out of the legal
  # footer. The live subscribe surface is the shared CTA partial, which still
  # posts to the brgen endpoint.
  def test_parked_popup_stays_out_of_the_footer_while_the_live_cta_keeps_the_endpoint
    footer = File.read(FOOTER)
    refute_includes footer, %(render "shared/newsletter_signup_popup"),
                    "the parked popup must not render from the legal footer"
    refute_includes footer, %(newsletter_signup_popup)
    assert_includes File.read(CTA), "email_subscriptions_path"
  end

  def test_newsletters_carry_replicate_artwork
    require_brgen_beside_shared!
    visuals = File.read(VISUALS)
    composer = File.read(COMPOSER)
    edition = File.read(EDITION)
    model = File.read(MODEL)

    assert_includes visuals, "REPLICATE_MODEL"
    assert_includes visuals, "artworks_for"
    assert_includes visuals, "source: :replicate"
    assert_includes composer, ":artworks"
    assert_includes edition, %(render "shared/newsletter/artwork")
    assert_includes model, "artwork_from_json"
  end

  def test_newsletter_provider_is_called_replicate
    visuals = File.read(VISUALS)
    refute_includes visuals, "preprompt_hero"
    refute_includes visuals, "PREPROMPT_MODEL"
    refute_includes visuals, "source: :preprompt"
  end
end
