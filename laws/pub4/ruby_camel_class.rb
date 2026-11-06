# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:284 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1a7619dbddea03c1
require_relative "master/law/ruby"

Law.define(:RUBY_CAMEL_CLASS) do
  source "Ruby Style Guide / RuboCop Naming/ClassAndModuleCamelCase"
  # A declaration ends the line, or continues only into a superclass. A sentence
  # keeps going, and prose in a heredoc is not blanked the way a comment is:
  # "module into shared/vendor/javascript, or pin it preload: false and" is a
  # wrapped line of advice inside importmap_external_hosts_examples.rb, read as
  # a module named `into`.
  detect { |line| line.match?(/^\s*(class|module)\s+([a-z]\w*|[A-Z]\w*_\w*)\s*(?:<\s*[\w:]+\s*)?$/) }
  fix "Rename to CamelCase: class Album_store -> class AlbumStore."
  bad  "class Album_store"
  good "class AlbumStore"
end
