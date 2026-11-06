# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:31 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0aeddeb79c4a10a1
require_relative "master/law/universal"

Law.define(:CORE_WEB_VITALS) do
  source "web.dev Core Web Vitals thresholds - field data, not a lab-only claim"
  ask <<~'ASK'.strip
    Does a web performance or interaction-quality claim lack representative real-user evidence for 75th-percentile
    LCP <= 2.5 s, INP <= 200 ms, and CLS <= 0.1, especially on mobile?
  ASK
  fix <<~'FIX'.strip
    Use field data such as CrUX or first-party RUM at the 75th percentile; use lab traces and feature-detected
    Long Animation Frames as diagnostics, not substitutes for field evidence.
  FIX
  bad "report(%q(LCP ok), lab_trace.lcp)"
  good "report(%q(LCP p75), field_data.lcp_p75)"
end
