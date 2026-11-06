# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:425 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6969d0d450f76b00
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:README_PROSE) do
          tags %i[TYPOGRAPHY DOMAIN_LANGUAGE]
          fix "a README is prose - a bold visionary opening, " \
            "tables never, code only under the final heading"
          example_path "/repo/README.md"
          bad "# Title\n\n| one | two |\n"
          good "# Title\n\n**One bold sentence carrying the argument.**\n"
          check do |src, path|
            next [] unless path.to_s.end_with?("README.md")
            findings = []

            lines = src.lines
            # A demonstration — a terminal transcript, one prized source excerpt —
            # earns its place once the argument is made, under the closing heading.
            # A fence before that chops the flowing prose the rest of this rule
            # exists to protect; a table chops it anywhere.
            last_heading = lines.rindex { |line| line.start_with?("## ") } || -1
            lines.each_with_index do |line, index|
              if line.start_with?("```") && index < last_heading
                findings << finding(line: index + 1,
                                    message: "a code block interrupts the prose - a demonstration belongs " \
                                             "under the final heading, not mid-argument")
              end

              if line.match?(/\A\s*\|.*\|\s*\z/)
                findings << finding(line: index + 1, message: "README carries a table - say it in a sentence")
              end
            end
            lead = src.sub(/\A#\s+[^\n]+\n+/, "").lstrip
            # A hero image or video (and its HTML comment) may sit between the
            # title and the opening line — skip it before checking the opening is
            # bold, so the face can lead the page and the prose still has to.
            lead = lead.sub(HERO, "").lstrip

            unless lead.empty? || lead.start_with?("**")
              findings << finding(line: 1,
                                  message: "README opening is not bold - lead with one bold, visionary sentence")
            end
            findings
          end
        end
      end
    end
  end
end
