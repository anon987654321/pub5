# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:414 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 729b107d18285433
require_relative "master/law/ruby"

Law.define(:TRANSFORM_KEYS) do
  source "Ruby idiom - Hash#transform_keys/values"
  detect { |line| line.match?(/\.each_with_object\(\{\}\)\s*\{\s*\|\(k,\s*v\),\s*h\|/) }
  fix "Use .transform_values { |v| ... }"
  bad  "h.each_with_object({}) { |(k, v), h| h[k] = v * 2 }"
  good "h.transform_values { |v| v * 2 }"
end
