# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:128 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d74eb75d8f601168
require_relative "master/law/rendered"

module Law
  Law.define(:CHROME_AREA_BUDGET) do
    F.rendered(self, :CHROME_AREA_BUDGET,
               source: "Wroblewski, Mobile First (2011): content before navigation; Tufte's data-ink at page scale; " \
                       "operator, every pixel earns its place",
               fix: "Keep top-of-page chrome under a sixth of a phone screen and let it yield while the reader reads.",
               bad: F.page(**F.chrome(top: [F.bar("header", 0.07), F.bar("nav.tab-bar", 0.05), F.bar("aside", 0.16)])),
               good: F.page(**F.chrome(top: [F.bar("header", 0.05), F.bar("nav.tab-bar", 0.05)])))
  end
end
