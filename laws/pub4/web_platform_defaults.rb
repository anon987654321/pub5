# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:45 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3b8ee0c5dcf69ed7
require_relative "master/law/universal"

Law.define(:WEB_PLATFORM_DEFAULTS) do
  source "GoogleChrome Modern Web Guidance and MDN Web Platform Baseline"
  ask <<~'ASK'.strip
    Does new HTML, CSS, or browser JavaScript recreate native platform behavior, add a dependency before checking native capabilities, or
    treat a Baseline Newly available feature as universal without a fallback?
  ASK
  practice "Prefer accessible browser primitives and interoperable CSS over bespoke JavaScript and avoidable dependencies."
  fix <<~'FIX'.strip
    Prefer semantic HTML, native form controls and browser APIs, CSS Grid/Flexbox, intrinsic sizing, and logical properties before
    custom JavaScript or a new dependency. Default core paths to Baseline Widely available features. Use @supports or runtime feature
    detection for newer capabilities, preserving a usable accessible fallback. At feature start, check current Baseline data and,
    when available, consult GoogleChrome Modern Web Guidance for a focused implementation pattern. Do not make network access or
    a guidance CLI a build/test prerequisite.
  FIX
  bad <<~'X'
    A click handler on a generic div emulates a native disclosure, with no keyboard path or state exposed.
  X
  good <<~'X'
    Use a semantic button or native details/summary, expose expanded state where needed, and preserve keyboard operation.
  X
end
