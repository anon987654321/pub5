# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:258 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 53205611745b2672
require_relative "master/law/recovered_design_semantics"

Law.define(:INTERACTION_SEMANTICS) do
  source "pub3 master.json HTML semantics + WAI-ARIA - navigation is a link, an action is a button"
  ask "For interactive controls, is the native element honest about the action? Use an anchor for navigation, a button for an in-page action, and a form control for form input. Reject clickable div/span substitutes, href=# used as an action, and ARIA used to repair a native-element choice. Return CLEAN when native interaction semantics are already correct."
  fix "Use the native interactive element that matches the user's action, then add ARIA only for state or additional semantics."
  bad <<~X
    <div class="save" data-action="click->editor#save">Save</div>
    <a href="#" data-action="click->menu#open">Open menu</a>
  X
  good <<~X
    <button type="button" class="save" data-action="click->editor#save">Save</button>
    <%= link_to "Read the article", article_path(@article) %>
  X
end
