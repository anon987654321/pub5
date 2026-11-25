# frozen_string_literal: true

require_relative "../../../lib/gap"
require_relative "../../support/check_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/axe"

module Deploy
  # Audit WCAG rules on every declared viewport, reporting findings under their Laws.
  class AxeCheck

    def self.run = new.result

    def result
      CheckResult.new.tap { |result| measure(result) }
    rescue CdpSession::Unavailable, CdpSession::Error, SystemCallError => e
      CheckResult.new.tap { |failed| failed.inconclusive!("accessibility_axe: Chrome/CDP stopped (#{e.message})") }
    end

    private

    def measure(result)
      unless GeometryProbe.available?
        return result.inconclusive!("accessibility_axe: no Chrome", gap: Master::Gap::NO_BROWSER)
      end

      live = GeometryProbe.reachable(surfaces)
      return result.inconclusive!("accessibility_axe: no app reachable - nothing audited") if live.empty?

      GeometryProbe.with_browser(warm: live) do |cdp|
        live.each { |surface| record(result, id: surface.id, report: audited(cdp, surface)) }
      end
    end

    def surfaces
      GeometryProbe.surfaces
    end

    def audited(cdp, surface)
      return { "error" => "did not render" } unless GeometryProbe.ok?(GeometryProbe.walk(cdp, surface))

      Axe.run(cdp)
    rescue CdpSession::JsError => e
      { "error" => "axe did not run - #{e.message}" }
    end

    def record(result, id:, report:)
      return result.incomplete!("accessibility_axe: #{id} #{report["error"]}") if report["error"]

      result.checked!
      Axe.findings(id, report).each { |line| result.fail(line, severity: :soft) }
    end
  end
end
