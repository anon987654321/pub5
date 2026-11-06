# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:159 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 82d2b64789ea9ecd
require_relative "master/law/universal"

Law.define(:MEANINGFUL_NAMES) do
  source "Clean Code - meaningful names (Robert C. Martin)"
  # The right-hand side has to already carry a better name, which is what the
  # fixtures below describe: `tmp = load` wastes the name `load` that is right
  # there. Any generic name on the left was 484 findings, and a sample of them
  # was `data = YAML.safe_load(path)`, `result = ideation.ideate(goal)` and
  # `result = img_f * (1.0 - intensity)` — expressions whose value genuinely is
  # the parsed data or the result, with no domain word going spare. Renaming
  # those makes the code worse, and 457 of the 484 were that shape.
  #
  # An expression with arguments, arithmetic or a literal is exempt for the same
  # reason: there is no name in it to prefer, and three more shapes where the
  # generic name is the right one and there is nothing
  # better to take: `@data = data` is the constructor idiom and has no other name
  # available; `result = blk.call` names a result after a call whose own last
  # word is `call`; and `@data = load_data` is already named after the method
  # that produced it, which is the rule satisfied rather than broken.
  detect do |line|
    next false unless line.match?(/\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\s*=\s*@?[a-z_]\w*(?:\.\w+)*\s*(?:#.*)?$/)

    left, right = line.match(/@?(\w+)\s*=\s*@?([\w.]+)/)&.captures
    next false if left.nil?
    next false if left == right                                   # @data = data
    next false if right.match?(/\.(?:call|run|value|result)\z/)   # a call's result
    next false if right.split(".").last.to_s.include?(left)       # @data = load_data
    next false if right == "nil"                                  # nothing to name it after

    true
  end
  fix "Name it after what the right-hand side already calls it, or after the domain."
  bad "tmp = load"
  good "user_profile = load"
end
