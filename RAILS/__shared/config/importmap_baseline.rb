# frozen_string_literal: true

# Shared importmap pins for the pub5 Rails family.
# Include from each app: eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)
# Local modules are protected by the asset pipeline's SRI hashes. External pins must opt in explicitly.

sc_pin = lambda do |name|
  pin("@stimulus-components/#{name}", to: "@stimulus-components--#{name}.js")
end

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/request.js", to: "@rails--request.js"
pin "morphdom", to: "morphdom.js"
pin "stimulus-use"
pin "stimulus_reflex"
pin "cable_ready"
pin "sortablejs"
pin "tiptap", to: "tiptap.js", preload: false
pin "pub5/tiptap_editor", to: "tiptap_editor_controller.js"
pin "pub5/comment_thread", to: "comment_thread_controller.js"
pin "pub5/hotwire", to: "hotwire.js"
pin "pub5/pwa_runtime", to: "pwa_runtime.js"
pin "pub5/console_guard", to: "console_guard.js"
pin "pub5/visual_field", to: "visual_field.js"
pin "pub5/visual_surface", to: "visual_surface_controller.js"
pin "pub5/stimulus_boot", to: "stimulus_boot.js"
pin "pub5/live_search", to: "live_search_controller.js"
pin "pub5/search_focus", to: "search_focus_controller.js"
pin "pub5/search_palette", to: "search_palette_controller.js"
pin "pub5/offline_page", to: "offline_page_controller.js"
pin "pub5/edge_swiper", to: "edge_swiper_controller.js"
pin "pub5/infinite_scroll", to: "infinite_scroll_controller.js"
pin "pub5/browser_fingerprint", to: "browser_fingerprint_controller.js"
pin "pub5/direct_upload", to: "direct_upload_controller.js"
pin "pub5/character_counter", to: "character_counter_controller.js"
pin "pub5/theme_meta", to: "theme_meta.js"
pin "pub5/theme_toggle", to: "theme_toggle_controller.js"
pin "pub5/luxury_product", to: "luxury_product_controller.js"
pin "pub5/parallax_tilt", to: "parallax_tilt_controller.js"
pin "pub5/scroll_reveal", to: "scroll_reveal_controller.js"
pin "pub5/nearby_chat", to: "nearby_chat_controller.js"
pin "pub5/conversation_log", to: "conversation_log_controller.js"
pin "pub5/dismiss", to: "dismiss_controller.js"
pin "pub5/optimistic_send", to: "optimistic_send_controller.js"
pin "pub5/presence", to: "presence_controller.js"
pin "pub5/scroll_chrome", to: "scroll_chrome_controller.js"
pin "pub5/brgen_shell", to: "brgen_shell_controller.js"
pin "pub5/nav_autohide", to: "nav_autohide_controller.js"
pin "pub5/action", to: "action_controller.js"
pin "pub5/bottom_sheet", to: "bottom_sheet_controller.js"
# Vendored rather than pinned to cdn.jsdelivr.net, which script-src does not
# allow: the 1% sample would fail once CSP is enforced. Lazy, as before.
pin "web-vitals", to: "web-vitals.js", preload: false
pin "pub5/autosave", to: "autosave_controller.js"
pin "pub5/draft_store", to: "draft_store_controller.js"
pin "pub5/media_picker", to: "media_picker_controller.js"
# Only media_picker imports it, so it loads with a photo picker and costs no
# modulepreload on the pages without one.
pin "pub5/image_compression", to: "image_compression.js", preload: false
pin "pub5/post_progressive", to: "post_progressive_controller.js"
pin "pub5/feed_compose", to: "feed_compose_controller.js"
pin "pub5/link_preview", to: "link_preview_controller.js"
pin "pub5/feed_hotkey", to: "feed_hotkey_controller.js"
pin "pub5/offline_feed", to: "offline_feed_controller.js"
pin "pub5/pwa_standalone", to: "pwa_standalone_controller.js"
pin "pub5/outbound_click", to: "outbound_click_controller.js"
pin "pub5/onboarding", to: "onboarding_queue.js"
pin "pub5/cookie_consent", to: "cookie_consent.js"
pin "pub5/cookie_consent_controller", to: "cookie_consent_controller.js"
pin "pub5/welcome_onboarding", to: "welcome_onboarding_controller.js"
pin "pub5/link_converter", to: "link_converter_controller.js"
pin "pub5/network_aware", to: "network_aware_controller.js"
pin "pub5/media_exclusive", to: "media_exclusive_controller.js"
pin "pub5/haptics", to: "haptics_controller.js"
pin "pub5/geolocation", to: "geolocation_controller.js"
pin "pub5/viewport_aware", to: "viewport_aware_controller.js"
pin "pwa/offline_store", to: "pwa_offline_store.js"
pin "lightgallery", to: "lightgallery.js"
pin "idb-keyval", to: "idb-keyval.js"

pin "stimulus-glow", to: "@stimulus-components--glow.js"
pin "stimulus-places-autocomplete", to: "stimulus-places-autocomplete.js"

%w[
  animated-number auto-submit carousel character-counter chartjs checkbox-select-all clipboard
  color-picker confirmation content-loader dialog dropdown hotkey lightbox notification
  password-visibility popover prefetch rails-nested-form read-more remote-rails reveal
  scroll-progress scroll-reveal scroll-to sortable sound speech-recognition textarea-autogrow timeago
].each { |name| sc_pin.call(name) }
