# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:13 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0a6b9be1e7376d5c
require_relative "master/law/universal"

Law.define(:BASELINE_COMPATIBILITY) do
  source "MDN Web Platform Baseline - compatibility is not accessibility"
  ask <<~'ASK'.strip
    Does a web change depend on a newly available HTML, CSS, JavaScript, or PWA API without checking the
    supported browser/device matrix, fallback behavior, accessibility, and security contract?
  ASK
  fix <<~'FIX'.strip
    Check current Baseline status and consult Google's Modern Web Guidance for feature-specific patterns when
    available. Prefer Baseline Widely available semantics for core paths; progressively enhance newer APIs such as
    field-sizing, container style queries, contrast-color(), CSS anchor positioning, Trusted Types, and the
    Navigation API. Verify the target browser matrix, feature detection, keyboard and assistive-technology
    behavior, and a usable fallback. Do not make network access or a new package a build/test prerequisite.
    Baseline is compatibility evidence, not proof of accessibility or security.
  FIX
  bad "el.style.fieldSizing = %q(content)  // no feature detection, no fallback"
  good "if (CSS.supports(%q(field-sizing), %q(content))) { el.style.fieldSizing = %q(content) }"
end
