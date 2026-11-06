# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1971 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: da286795d117b6ee
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LAW_OF_DEMETER) do
          source "Law of Demeter (Ian Holland)"
          ask "Does this code reach through several objects or expose knowledge of a collaborator's internals?"
          tags %i[COUPLING]
          fix "Talk only to immediate collaborators and encapsulate the traversal."
          bad "city = order.buyer.profile.address\n"
          good "names = files.uniq.sort.reject(&:empty?)\n"
          check do |src, path|
            next [] unless %w[ruby javascript html].include?(language(path))
            src.each_line.with_index(1).filter_map do |line, n|
              next if line.lstrip.start_with?("#", "//", "*")

              code = DEMETER_NOISE.reduce(line) { |text, noise| text.gsub(noise, '""') }.gsub(/\([^()]*\)/, "()")
              reach = code.scan(DEMETER_CHAIN).map do |chain|
                head, *steps = chain.gsub("()", "").split(".")
                next 0 if DEMETER_GLOBALS.include?(head)

                [head, *steps.reject { |step| DEMETER_TRANSFORMS.include?(step) }].size
              end
              next unless reach.any? { |size| size >= 4 }

              finding(line: n, message: "4-level chain - introduce a local variable or delegation")
            end
          end
        end
      end
    end
  end
end
