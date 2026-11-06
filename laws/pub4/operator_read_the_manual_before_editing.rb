# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_read_the_manual_before_editing by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0bba7e9eb9ca5cf0
require_relative "master/lib/master"

Law.define(:OPERATOR_READ_THE_MANUAL_BEFORE_EDITING) do
  source "pub4 MASTER/data/project_context.yml operator_read_the_manual_before_editing"
  practice "Before editing anything under RAILS/ (or MASTER/web), an agent has read the\nlatest Rails style guide (rubocop's rails-style-guide) and the current Rails\nedge guides (edgeguides.rubyonrails.org) for every API the change touches,\nbecause the apps run on Rails edge. Before editing anything under OPENBSD/,\nan agent has read man(1) for every tool, daemon or configuration file the\nchange touches (for example relayd.conf(5), rcctl(8), pf.conf(5), doas.conf(5),\nnewsyslog(8)), on the box or at man.openbsd.org for the running release. A\nchange whose commit cannot name the guide section or man page it followed\nis not ready."
end
