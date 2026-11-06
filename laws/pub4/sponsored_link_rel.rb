# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:240 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4389aeab805f357a
require_relative "master/law/html"

Law.define(:SPONSORED_LINK_REL) do
  source "Google Search Central, qualifying outbound links (rel=sponsored); markedsføringsloven § 3"
  tags %i[COMPLIANCE]
  fix "add rel=\"sponsored\" (with noopener) to the affiliate link"
  bad "<a href=\"<%= deal.affiliate_url %>\" target=\"_blank\">Buy</a>\n"
  good "<a href=\"<%= deal.affiliate_url %>\" target=\"_blank\" rel=\"sponsored noopener\">Buy</a>\n"
  check do |src, _path|
    # An <a> tag, stepping over ERB inside its attributes, or one link_to call.
    links = /<a\b(?:<%.*?%>|[^>])*>|<%=\s*link_to\b.*?%>/m
    findings = []
    src.scan(links) do
      link = Regexp.last_match(0)
      next unless link.match?(/outbound[_-]click|affiliate/i) && !link.match?(/\bsponsored\b/)

      line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
      findings << finding(line:, message: "affiliate link without rel=\"sponsored\" - mark it as paid")
    end
    findings
  end
end
