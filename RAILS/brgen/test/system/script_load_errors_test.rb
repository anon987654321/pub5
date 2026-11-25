# frozen_string_literal: true

require "application_system_test_case"

# Two scripts failed in the browser: the radio tunnel module asked
# radio_brgen_visual for an export it does not have, and StimulusReflex threw
# on the refusal brgen gives a signed-out visitor's reflex channel.
class ScriptLoadErrorsTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
  end

  test "the radio tunnel module loads" do
    visit_city(nil, "/")
    loaded = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("radio_brgen_tunnel")
        .then((tunnel) => done(typeof tunnel.RadioBrgen === "function" && tunnel.MODES.length > 0 ? "loaded" : "partial"))
        .catch((error) => done(String(error)))
    JS

    assert_equal "loaded", loaded
  end

  # A reflex controller subscribes on the consumer the Stimulus application
  # carries; the refusal is ActionCable's reject for that subscription, the
  # call the socket makes when the server answers reject_subscription.
  # The server refuses this visitor too, and often first: its reject removed the
  # subscription before the probe looked, and the probe polled until the script
  # timeout (2 runs in 4, 2026-11-25). Reject is observed on the prototype, so
  # whichever caller refuses first is the one judged.
  test "a refused reflex subscription throws nothing" do
    visit_city(nil, "/")
    outcome = using_wait_time(20) { page.evaluate_async_script(<<~JS) }
      const done = arguments[arguments.length - 1]
      Promise.all([ import("@rails/actioncable"), import("controllers/application_controller") ])
        .then(([ cable, { default: ReflexController } ]) => {
          const consumer = cable.createConsumer()
          const subscriptions = Object.getPrototypeOf(consumer.subscriptions)
          const reject = subscriptions.reject
          subscriptions.reject = function (identifier) {
            try {
              const result = reject.call(this, identifier)
              done("refused quietly")
              return result
            } catch (error) {
              done(String(error))
            }
          }
          window.Stimulus.consumer = consumer
          window.Stimulus.register("reflex-probe", class extends ReflexController {})
          document.body.insertAdjacentHTML("beforeend", "<div data-controller='reflex-probe'></div>")
          const deadline = Date.now() + 10 * 1000
          const refuse = () => {
            const subscription = consumer.subscriptions.subscriptions[0]
            if (subscription) return consumer.subscriptions.reject(subscription.identifier)
            if (Date.now() > deadline) return done("no reflex subscription was made or refused")
            setTimeout(refuse, 50)
          }
          refuse()
        })
        .catch((error) => done(`setup failed: ${error}`))
    JS

    assert_equal "refused quietly", outcome
  end
end
