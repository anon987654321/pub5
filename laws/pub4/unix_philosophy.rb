# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:688 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 990f93b3970cb969
require_relative "master/law/universal"

Law.define(:UNIX_PHILOSOPHY) do
  source "Unix philosophy - do one thing well (Doug McIlroy)"
  ask "Does one module perform several unrelated jobs that could compose through a clear boundary?"
  fix "Split unrelated responsibilities into focused components and compose them."
  bad <<~'X'
    class Report; def query; end; def render; end; def email; end; end
  X
  good <<~'X'
    report = Report.new(data); Email.deliver(report.render)
  X
end
