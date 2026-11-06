# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/fix_hygiene.rb:7 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: adffcf708efca04a
require_relative "master/law/fix_hygiene"

Law.define(:NO_INFINITY_TO_I) do
  source "MASTER post-incident /fix hardening - finite convergence ranks"
  detect do |line|
    code = line.gsub(/(['"]).*?\1/, "").sub(/#.*\z/, "")
    code.match?(
      /Float::(?:INFINITY|POSITIVE_INFINITY|NEGATIVE_INFINITY|NAN).*?\.(?:to_i|to_int)\b|
       \.(?:to_i|to_int)\b.*?Float::(?:INFINITY|POSITIVE_INFINITY|NEGATIVE_INFINITY|NAN)/x,
    )
  end
  fix "Use a finite sentinel or score_value before integer coercion; never call to_i/to_int on a non-finite float."
  bad "Float::INFINITY.to_i"
  good "UNMEASURED_SCORE = 1_000_000_000"
end
