# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:40 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ba1e996bbd196a69
require_relative "master/law/javascript"

Law.define(:NULLISH_COALESCING) do
  source "ECMAScript 2020 - nullish coalescing (??)"
  # The fix line already says when `??` is the answer: where 0 or '' are valid
  # values. A bare `\w+ \|\| \w+` says nothing about that and fired on 21 of 41
  # JavaScript files — every boolean condition in the tree, where `??` is not an
  # improvement but a syntax error: `if (!this.tracking || this.startPos === null)`
  # cannot mix `??` with `||` unparenthesised, and `event.currentTarget ||
  # this.element` falls back between two objects, neither of which is ever 0.
  #
  # The defect needs a literal on the right — `x || 0`, `x || ''` — which is
  # where a falsy-but-valid left side silently takes the fallback. An identifier
  # or member expression on the right is an object default and idiomatic `||`.
  detect do |line|
    next false if line.match?(/\b(?:if|while|switch)\s*\(/)
    next false unless line.match?(/=\s*[^=]*\|\|/)
    next false if line.match?(/[!<>=]=/)
    # A numeric coercion answers NaN, not null, when its input is junk. `||` is
    # the operator that turns NaN into the default; `??` would let it through.
    next false if line.match?(/\b(?:Number|parseFloat|parseInt)\([^()]*\)\s*\|\|/)

    line.match?(/\|\|\s*(?:-?\d+(?:\.\d+)?|""|''|``)\s*[;,)\]}]?\s*$/)
  end
  fix "Use ?? when 0 or '' are valid values."
  bad  "const n = count || 0"
  good "const n = count ?? 0"
end
