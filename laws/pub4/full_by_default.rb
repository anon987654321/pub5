# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:117 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ae5118e0f7fa9fee
require_relative "master/law/universal"

Law.define(:FULL_BY_DEFAULT) do
  source "MASTER-native (no shallow/lite tiers by default)"
  ask "Does this API expose a do-less tier such as shallow, standard, quick, lite, basic, or light alongside a full tier where users routinely need the full behavior? If the cost tradeoff is real, name the cost rather than the quality."
  # Both words have to be list items, not two adjectives that happen to meet.
  # "sculpted soft key light, deep muted tones" is a prompt describing a
  # photograph and "blue-hour ambient light, deep shadow tones" is a colour
  # grade; the first tier word has to open a list or follow a separator, the way
  # `[shallow, deep]` does.
  detect { |line| line.match?(/(?:\A\s*|[\[(|,=:]\s*)(shallow|standard|quick|lite|basic|light|simple)\b\s*[|,)\]]\s*\b(deep|full|advanced|complete|thorough)\b/) }
  fix "Drop the degraded tier. If a real cost tradeoff exists, rename to surface the cost (lexical < structural < semantic), not the result quality."
  bad "modes = [shallow, deep]"
  good "modes = [deep]"
end
