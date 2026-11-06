# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:124 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2ae4a41f43902ed7
require_relative "master/law/javascript"

Law.define(:POINTER_FEEDBACK_EARLY) do
  path "RAILS/"
  source "Pointer Events - early input acknowledgement"
  ask "Does a direct-manipulation interaction acknowledge pointer input at pointerdown or an equivalent active state instead of making a click handler carry all perceived responsiveness? Preserve keyboard and assistive-technology behavior."
  fix "Move only the immediate acknowledgement to pointerdown/active state; leave the actual command and confirmation semantics on the existing action path."
  bad "button.addEventListener('click', showPressedState)"
  good "button.addEventListener('pointerdown', showPressedState)"
end
