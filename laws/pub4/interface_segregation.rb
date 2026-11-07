# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:899 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d14ab79c9ef77dac
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:INTERFACE_SEGREGATION) do
          detector InterfaceSegregationLaw
          tags %i[SOLID ISP]
          source "SOLID - Interface Segregation"
          ask "Does an interface force implementations to stub or ignore methods they do not need?"
          fix "Split broad interfaces into focused contracts."
          bad <<~'X'
          class Printer; def print; end; def scan; raise NotImplementedError; end; end
          X
          good <<~'X'
          Printable = Data.define; Scannable = Data.define
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
