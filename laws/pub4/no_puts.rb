# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:118 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: aa3233dae8486afb
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NO_PUTS) do
    tags %i[CLEAN_CODE]
    fix "no puts, p or pp in library code"
    bad "  puts(\"ready\")\n"
    good "  @bus.publish(\"ready\")\n  p = point\n  p.x\n  p == q\n  p\n"
    check do |src, path|
      # The REPL prints for a living, so the path it lives at is exempt. This
      # exemption carries the whole of lib/cli/session/ -- 100 deliberate puts --
      # and it has to move whenever that directory does. An exemption whose
      # subject moves out from under it is a check that starts firing on exactly
      # what it exempted: when lib/now/ became lib/cli/ and this address stayed,
      # 105 findings arrived in selfcheck's largest actionable bucket overnight.
      next [] if path.to_s.match?(%r{/exe/|/spec/|/bin/|/cli/session})

      # A program's output is its interface, and the rule is about library code.
      # Measured over the four trees: 750 of 941 findings sat in a program — a
      # script with a shebang, a file that runs itself under a $PROGRAM_NAME
      # guard, a rake task, a seed file or a test — where `puts "ok: synced"` is
      # the line the operator reads and a logger would hide it.
      next [] if src.start_with?("#!") || src.match?(PROGRAM_GUARD) || path.to_s.match?(PROGRAM_PATH)

      parsed = Prism.parse(src)
      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        # A receiverless call only, so @bus.publish and io.puts are not debug output.
        next unless node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name.to_s.match?(/^(puts|p|pp)$/)

        message = "debug output: #{node.name} - use event bus or logger"
        findings << finding(line: node.location.start_line, message:)
      end

      findings
    end
  end
      end
    end
  end
end
