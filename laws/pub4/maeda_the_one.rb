# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:254 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b26d77b2b135a20a
require_relative "master/law/rendered"

module Law
  Law.define(:MAEDA_THE_ONE) do
    buy = F.el("button.buy", primary: true, rect: F.at(40).merge("h" => 44))
    sell = F.el("button.sell", primary: true, rect: F.at(84).merge("h" => 44))
    F.rendered(self, :MAEDA_THE_ONE,
               source: "John Maeda, The Laws of Simplicity (2006), Law 10 The One; ONE_PRIMARY_ACTION " \
                       "holds the view's grain, this the card's and the form's",
               fix: "Give each card and form one primary action; make the rest ghost or link buttons.",
               bad: F.page(F.el("div.card", index: 0), buy.merge("host" => 0), sell.merge("host" => 0)),
               good: F.page(F.el("div.card", index: 0), F.el("div.card", index: 1),
                            buy.merge("host" => 0), sell.merge("host" => 1)))
  end
end
