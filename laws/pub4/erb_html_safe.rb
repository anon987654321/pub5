# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:166 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 384b3b018b225cf5
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ERB_HTML_SAFE) do
          tags %i[SECURITY]
          fix "html_safe only after sanitize"
          bad %(<%= @post.body.html_safe %>\n)
          good %(<%= sanitize(@post.body).html_safe %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # html_safe is judged per output expression: sanitizing one ERB tag
            # cannot excuse a different tag, and JSON serialization is not HTML
            # escaping. Only a scan: intentional comment associated with the next
            # output can excuse generated markup (the 2FA QR SVG).
            output_pattern = /<%=\s*(.*?)\s*%>/m
            marker_pattern = /<%#.*?\bscan:\s*intentional\b(?!-).*?%>|<!--.*?\bscan:\s*intentional\b(?!-).*?-->/m
            marker_ends = []
            src.scan(marker_pattern) { marker_ends << Regexp.last_match.end(0) }
            marker_index = 0
            previous_output_end = 0
            findings = []

            src.scan(output_pattern) do
              match = Regexp.last_match
              expression = match[1]
              output_start = match.begin(0)
              output_end = match.end(0)
              marker_end = nil

              while marker_index < marker_ends.length && marker_ends[marker_index] < output_start
                marker_end = marker_ends[marker_index]
                marker_index += 1
              end

              if expression.match?(/\.html_safe\b/)
                sanitized_in_this_expression = expression.match?(/\b(?:sanitize|strip_tags)\b/)
                intentional_for_this_expression = marker_end && marker_end > previous_output_end

                unless sanitized_in_this_expression || intentional_for_this_expression
                  line = src[0...output_start].count("\n") + 1
                  findings << finding(
                    line:,
                    message: "raw html_safe in view - prefer auto-escaped output or raw json_escape(valid_json) for script payloads",
                  )
                end
              end

              previous_output_end = output_end
            end

            findings
          end
        end
      end
    end
  end
end
