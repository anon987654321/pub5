# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:326 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1269fa08ebb2b6e9
require_relative "master/law/ruby"

Law.define(:RUBY_SNAKE_METHODS) do
  source "Ruby Style Guide / RuboCop Naming/MethodName"
  detect { |line| line.match?(/\bdef\s+[a-z][a-z0-9_]*[A-Z]/) }
  fix "Rename to snake_case: def fetchAlbum -> def fetch_album."
  bad  "def fetchAlbum"
  good "def fetch_album"
end
