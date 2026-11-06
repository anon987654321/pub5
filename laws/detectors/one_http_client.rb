# frozen_string_literal: true
module Pub5
  module Laws
    class OneHttpClient
      def self.findings(root)
        Dir.glob(File.join(root, "**", "*.rb")).filter_map do |path|
          relative = path.delete_prefix("#{root}/")
          next if relative.start_with?("core/", "laws/fixtures/")
          offenders = File.readlines(path).each_with_index.filter_map do |line, index|
            [index + 1, line.strip] if line.match?(/\bNet::HTTP\b/)
          end
          [relative, offenders] unless offenders.empty?
        end
      end
    end
  end
end
