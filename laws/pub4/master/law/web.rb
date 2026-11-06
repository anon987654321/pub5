# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 60918b6c540dab1e
require_relative "../lib/master"

module Master
  module Review
    module Scan
      module Laws

        # Retired registry twins — each lives once, in law/:
        #   ARIA_INTERACTIVE, BUTTON_OVER_ANCHOR, CLAMP_TYPOGRAPHY, I18N_COVERAGE
        #   MOBILE_FIRST, NO_IMPORT_SCSS
        #   NO_INLINE_STYLES
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        










        # SEMANTIC_ELEMENTS lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # IMG_ALT and LAZY_IMAGES returned from the twin batch: both judge a
        # TAG, and law/ scans lines — the attribute-per-line spelling made
        # every multi-line <img> a finding. tag_source flattens first.
        









        









        











































        # LOGICAL_PROPERTIES lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # META_CHARSET lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        













        










        














        SIMPLE_WRAPPER_TAG_RE = %r{
          <(p|div|span|li|h[1-6]|strong|em|small|label|td|th|dt|dd|caption)(?:\s[^>]*)?>
          \s*<%=\s*[^%<]+?\s*%>\s* # scan: intentional - matches an ERB tag, embeds none
          </\1>
        }ix.freeze

        












        # BEM_IN_VIEWS lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # UTILITY_CLASS_SOUP lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        


















































        















        











        # SKIP_TO_MAIN lives once, in law/html.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        















        # NO_LONG_TRANSITION lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        



















        











        












        











        INPUT_GENERIC_TYPE_RE = /
          <input\s+[^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)[^"']*["'][^>]*type\s*=\s*["']text["']
          |
          <input\s+[^>]*type\s*=\s*["']text["'][^>]*(?:name|id)\s*=\s*["'][^"']*(?:email|phone|tel|url|date|password)
        /ix.freeze

        











        













      end
    end
  end
end
