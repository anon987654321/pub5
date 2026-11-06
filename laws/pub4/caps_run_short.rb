# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:111 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: be45a48637efc73c
require_relative "master/law/rendered"

module Law
  Law.define(:CAPS_RUN_SHORT) do
    F.rendered(self, :CAPS_RUN_SHORT,
               source: "Butterick, all caps for less than one line, tracked 5-12%; Bringhurst 2.1.6",
               fix: "Keep capitals to a short label under one line (NY, SOLGT); set sentences in mixed case.",
               bad: F.page(F.el("p.notice", text_transform: "uppercase",
                                            text: "Leveringen er forsinket i dag fordi bilen venter ved kaien")),
               good: F.page(F.el("span.badge", text_transform: "uppercase", text: "NY")))
  end
end
