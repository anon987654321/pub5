# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:403 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: de3899a47f2830ca
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:DEBUG_OUTPUT) do
    tags %i[FAIL_VISIBLY]
    fix "debug output left in lib/"
    example_path "/repo/lib/example.rb"
    bad "p value\n"
    good "p << value\n"
    check do |src, path|
      next [] unless path.to_s.include?("/lib/")
      next [] if path.to_s.include?("/scan/rules/")

      # `p` is a legal variable name, so a line starting `p <<` is an append to a
      # local, not a Kernel#p call. The old pattern read both the same way and
      # flagged attention_context.rb's `p << "zoom: …"` twice — an error-severity,
      # auto_fix=true rule pointed at correct code. Anything whose next token is an
      # assignment, append or comparison operator is the variable, not the call.
      #
      # `==` and `!=` were named and `<` and `>` were not, so dilla's
      # `p < 0.5 ? (p * 4.0) - 1.0 : 3.0 - (p * 4.0)` — the phase local of a
      # triangle oscillator — was an error-severity finding. `p <expr>` parses as
      # a comparison in every case; a Kernel#p whose argument opens with `<` is
      # `p <<~HEREDOC`, which the `<<` branch already spares.
      findings = scan_lines(src, /^\s*pp?\s+(?!self\b)(?!<<|[<>]|==|!=|\|\|=|&&=|[+\-*\/%|&^]?=)/,
        message: "p/pp debug call - remove or publish via event bus")

      findings += scan_lines(src, /\$stderr\.puts\b/, message: "$stderr.puts - use @bus.publish or $stdout")
      findings
    end
  end
      end
    end
  end
end
