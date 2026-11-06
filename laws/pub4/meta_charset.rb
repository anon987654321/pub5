# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:176 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ae069df612bb011
require_relative "master/law/html"

Law.define(:META_CHARSET) do
  source "HTML Living Standard - meta charset utf-8 (WHATWG)"
  scope :file
  # Both spellings count. The http-equiv form is the older one, and mail clients
  # honour it more reliably than the HTML5 short form — so shared/layouts/mailer
  # declares its encoding that way on purpose, and a detector accepting only the
  # short form called the one correct file in the tree an error.
  detect { |text| text.match?(/<html\b|<body\b/) && !text.match?(/<meta\s+charset=|charset=["']?utf-8/i) }
  fix "Add a UTF-8 charset declaration as the first element in head."
  bad  "<html><head><title>x</title></head></html>"
  good "<html><head><meta charset=\"UTF-8\"></head></html>"
end
