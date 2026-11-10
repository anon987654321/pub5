# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# The tab bar survives Turbo visits (data-turbo-permanent), so its
# aria-current has to be re-marked after each one. scroll-chrome owns the bar
# and does it. Run in node against stand-in links; Stimulus is a bare base
# class and pub4/onboarding never lets the coach prompt.
class ScrollChromeCurrentTabTest < Minitest::Test
  CONTROLLER = File.expand_path("../__shared/frontend/scroll_chrome_controller.js", __dir__)
  STIMULUS = %(import { Controller } from "@hotwired/stimulus")
  ONBOARDING = %(import { mayPrompt, YIELD_EVENT } from "pub4/onboarding")

  VISIT = <<~JS
    const link = (href) => ({
      href, attributes: {},
      getAttribute() { return this.href },
      setAttribute(name, value) { this.attributes[name] = value },
      removeAttribute(name) { delete this.attributes[name] }
    })
    const links = [link("/"), link("/communities"), link("/nearby")]
    const listeners = {}

    globalThis.window = {
      location: { pathname: "/", origin: "https://brgen.no" },
      addEventListener() {}, removeEventListener() {}
    }
    globalThis.document = {
      documentElement: { classList: { toggle() {}, contains: () => true } },
      addEventListener: (type, fn) => { listeners[type] = fn },
      removeEventListener() {}
    }

    const controller = new ScrollChrome()
    controller.element = { scrollTop: 0, addEventListener() {}, removeEventListener() {} }
    controller.hasBarTarget = true
    controller.barTarget = { querySelectorAll: () => links, addEventListener() {}, removeEventListener() {}, setAttribute() {}, removeAttribute() {}, contains: () => false }
    controller.connect()
    const first = links.map((l) => l.attributes["aria-current"] ?? null)

    window.location.pathname = "/nearby"
    listeners["turbo:load"]()
    console.log(JSON.stringify([first, links.map((l) => l.attributes["aria-current"] ?? null)]))
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    [ STIMULUS, ONBOARDING ].each do |line|
      assert source.include?(line), "#{CONTROLLER} no longer imports #{line.inspect}"
    end

    program = source.sub(STIMULUS, "class Controller {}")
                    .sub(ONBOARDING, %(const mayPrompt = () => false; const YIELD_EVENT = "pub4:yield"))
                    .sub("export default class extends Controller", "class ScrollChrome extends Controller") + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out

    JSON.parse(out.lines.last)
  end

  FOCUS = <<~JS
    const classes = new Set(["chrome-hidden"])
    const attributes = { "aria-hidden": "true", inert: "" }
    const barListeners = {}
    const link = {
      getAttribute: () => "/nearby",
      setAttribute(name, value) { attributes[name] = value },
      removeAttribute(name) { delete attributes[name] }
    }
    globalThis.window = {
      location: { pathname: "/elsewhere", origin: "https://brgen.no" },
      sessionStorage: { getItem: () => "0", setItem() {} },
      localStorage: { getItem: () => null, setItem() {} },
      addEventListener() {}, removeEventListener() {}
    }
    globalThis.document = {
      activeElement: null,
      documentElement: {
        classList: {
          toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) },
          contains: (name) => classes.has(name)
        }
      },
      addEventListener() {}, removeEventListener() {}
    }

    const controller = new ScrollChrome()
    controller.element = { scrollTop: 180, scrollHeight: 2400, clientHeight: 844, addEventListener() {}, removeEventListener() {} }
    controller.hasBarTarget = true
    controller.hasPeelTarget = false
    controller.hasCoachTarget = false
    controller.barTarget = {
      querySelectorAll: () => [link],
      addEventListener: (name, fn) => { barListeners[name] = fn },
      removeEventListener() {},
      contains: (node) => node === document.activeElement,
      setAttribute(name, value) { attributes[name] = value },
      removeAttribute(name) { delete attributes[name] }
    }
    controller.connect()
    const closed = {
      hidden: classes.has("chrome-hidden"),
      ariaHidden: attributes["aria-hidden"] ?? null,
      inert: Object.hasOwn(attributes, "inert")
    }

    document.activeElement = link
    barListeners.focusin()
    const focused = {
      hidden: classes.has("chrome-hidden"),
      ariaHidden: attributes["aria-hidden"] ?? null,
      inert: Object.hasOwn(attributes, "inert")
    }
    console.log(JSON.stringify([closed, focused]))
  JS

  STATES = <<~JS
    function hiddenAt(scrollTop, scrollHeight, clientHeight) {
      const classes = new Set(["chrome-hidden"])
      globalThis.window = {
        location: { pathname: "/", origin: "https://brgen.no" },
        sessionStorage: { getItem: () => "0", setItem() {} },
        localStorage: { getItem: () => null, setItem() {} },
        addEventListener() {}, removeEventListener() {}
      }
      globalThis.document = {
        activeElement: null,
        documentElement: {
          classList: {
            toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) },
            contains: (name) => classes.has(name)
          }
        },
        addEventListener() {}, removeEventListener() {}
      }
      const controller = new ScrollChrome()
      controller.element = { scrollTop, scrollHeight, clientHeight, addEventListener() {}, removeEventListener() {} }
      controller.hasBarTarget = true
      controller.hasPeelTarget = false
      controller.hasCoachTarget = false
      controller.barTarget = {
        querySelectorAll: () => [],
        addEventListener() {}, removeEventListener() {},
        contains: () => false, removeAttribute() {}, setAttribute() {}
      }
      controller.connect()
      return classes.has("chrome-hidden")
    }
    console.log(JSON.stringify([
      hiddenAt(0, 2200, 844),
      hiddenAt(180, 2200, 844),
      hiddenAt(0, 844, 844)
    ]))
  JS

  def test_a_turbo_visit_moves_aria_current_to_the_new_page
    first, after_visit = run_page(VISIT)

    assert_equal [ "page", nil, nil ], first
    assert_equal [ nil, nil, "page" ], after_visit
  end

  def test_a_focused_hidden_tab_bar_stays_in_the_accessibility_tree_and_reveals
    closed, focused = run_page(FOCUS)

    assert_equal({ "hidden" => true, "ariaHidden" => nil, "inert" => false }, closed)
    assert_equal({ "hidden" => false, "ariaHidden" => nil, "inert" => false }, focused)
  end

  def test_the_tab_bar_is_visible_at_the_top_and_when_the_page_cannot_scroll
    at_top, mid_page, short_page = run_page(STATES)

    assert_equal [ false, true, false ], [ at_top, mid_page, short_page ]
  end
end
