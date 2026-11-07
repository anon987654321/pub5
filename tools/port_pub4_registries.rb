#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off port of pub4's registry facts into pub5's registry/. Reads pub4's
# files from a git ref so the result is reproducible:
#
#   ruby tools/port_pub4_registries.rb /path/to/pub4 origin/main apps > registry/apps.yml
#   ruby tools/port_pub4_registries.rb /path/to/pub4 origin/main models > registry/models.yml
#
# It prints rather than writes: registry/ is protected, so the operator (or
# gated Claude) redirects the output by hand.
#
# apps.yml keeps pub4's RAILS/apps.yml data as it was. models.yml merges
# pub4's MASTER/data models.yml, providers.yml, lanes.yml, inter_model.yml and
# operator_model.yml into one file under one schema; YAML anchors are
# resolved, comments are not carried (the pub4 ref in the header is where
# they live).
require_relative "../core/core"

pub4, ref, target = ARGV
abort "usage: port_pub4_registries.rb PUB4_DIR REF apps|models" unless pub4 && ref && %w[apps models].include?(target)

WORLD = Core::World.new(manifest: Core::Manifest.new(name: "port", verbs: { exec: ["git"] }),
                        ledger: Core::Ledger.new(Core::Knobs.fetch("PUB5_LEDGER")))

def git(pub4, *args)
  run = WORLD.exec("git", "-C", pub4, *args)
  abort "git #{args.join(" ")}: #{run.err}" unless run.ok?
  run.out
end

def show(pub4, ref, path)
  text = git(pub4, "show", "#{ref}:#{path}")
  Core::Registry.parse(text)
end

sha = git(pub4, "rev-parse", "--short=10", ref)
header = ->(what) { "# Ported from pub4 #{sha.strip} (#{what}) by tools/port_pub4_registries.rb.\n# Edit here from now on; pub4's comments explaining each value live at that commit.\n" }

if target == "apps"
  apps = show(pub4, ref, "RAILS/apps.yml")
  print header.call("RAILS/apps.yml"), YAML.dump(JSON.parse(JSON.generate(apps))).delete_prefix("---\n")
  exit
end

models = JSON.parse(JSON.generate(show(pub4, ref, "MASTER/data/models.yml")))
providers = JSON.parse(JSON.generate(show(pub4, ref, "MASTER/data/providers.yml")))
lanes = show(pub4, ref, "MASTER/data/lanes.yml")
inter_model = JSON.parse(JSON.generate(show(pub4, ref, "MASTER/data/inter_model.yml")))
operator = JSON.parse(JSON.generate(show(pub4, ref, "MASTER/data/operator_model.yml")))

# The HTTP providers Core::LLM can reach. Base URLs are each vendor's public
# API root; providers without a protocol are reached by CLI or not at all.
http = {
  "anthropic" => ["anthropic", "https://api.anthropic.com/v1"],
  "openai" => ["openai", "https://api.openai.com/v1"],
  "openrouter" => ["openai", "https://openrouter.ai/api/v1"],
  "deepseek" => ["openai", "https://api.deepseek.com/v1"],
  "xai" => ["openai", "https://api.x.ai/v1"],
  "mistral" => ["openai", "https://api.mistral.ai/v1"]
}
providers.delete("schema")
http.each { |name, (protocol, base)| providers.fetch(name).merge!("protocol" => protocol, "base" => base) }

models.delete("schema")
tiers = models.delete("models")
inter_model.delete("schema")
merged = {
  "schema" => 1,
  **models.slice("routing", "weights", "fallback_policy", "failover", "defaults", "model_defs"),
  "tiers" => tiers,
  **models.except("routing", "weights", "fallback_policy", "failover", "defaults", "model_defs"),
  "providers" => providers,
  "lanes" => { "dead" => lanes.fetch("dead") },
  "inter_model" => inter_model,
  "operator" => operator,
  "prices" => {}
}
note = "# prices: per model id, prompt_usd_per_m and completion_usd_per_m. Empty until\n# measured from an invoice or a provider's price page; until then the ledger\n# records cost as unmeasured (null), never as zero.\n"
print header.call("MASTER/data models.yml, providers.yml, lanes.yml, inter_model.yml, operator_model.yml"), note,
      YAML.dump(merged).delete_prefix("---\n")
