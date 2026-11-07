# frozen_string_literal: true

# The boot fell out of the tree because nothing failed when it did: the
# operator's tuned console bytes existed in pub5 by memory, and every gate
# stayed green. This Law pins the bytes where PLAN.md section 18 declares
# their homes, so a drop is a failing gate and not a question the operator
# has to ask twice: the boot colours and the dmesg grammar in
# master/data/console.yml, the splash painter in Cli::Terminal, the
# operator prompt shape in Cli::Prompt. A home moves only by editing this
# Law's path list - a recorded move in a reviewable diff - never by silent
# deletion.
Law.define(:PINNED_SURFACE_BYTES_CARRY) do
  source "PLAN.md sections 18 and 19; pub4 MASTER/data/console.yml and MASTER/lib/face.rb#shell_prompt"
  path %r{\Amaster/(data/console\.yml|cli/(terminal|prompt)\.rb)\z}

  # The console's tuned bytes: the 24-bit white on blue the OpenBSD console
  # wears while master boots, its palette fallback for a terminal that does
  # not say truecolor, and the dmesg grammar those lines are written in.
  bad_console = <<~BAD
    dmesg:
      enabled: true
      style: openbsd
  BAD
  good_console = <<~GOOD
    dmesg:
      enabled: true
      style: openbsd
      format: "unitN at parent: detail | unitN: detail"
      boot_sgr: "37;48;2;0;0;255"
      boot_sgr_basic: "37;44"
  GOOD

  adapter(:structured_data, languages: %w[yaml],
          example_path: "master/data/console.yml",
          bad: bad_console, good: good_console) do |text, file|
    next [] unless file == "master/data/console.yml"

    pinned = {
      %r{boot_sgr: "37;48;2;0;0;255"} =>
        "boot_sgr 37;48;2;0;0;255 - the OpenBSD console's white on truecolor blue",
      /boot_sgr_basic: "37;44"/ =>
        "boot_sgr_basic 37;44 - the palette fallback for a terminal without truecolor",
      /format: "unitN at parent: detail \| unitN: detail"/ =>
        "the dmesg grammar - unitN at parent: detail, one factual event per line",
    }
    pinned.filter_map do |pattern, what|
      next if text.match?(pattern)

      finding(line: 1, message: "pinned console byte is gone: #{what}")
    end
  end

  # The splash painter: boot_splash is the declared home of the paint
  # (console.yml's comment and section 18 name it), one line at a time so a
  # reset never spans a newline.
  adapter(:structured_data, languages: %w[ruby],
          example_path: "master/cli/terminal.rb",
          bad: "module Cli\n  module Terminal\n  end\nend\n",
          good: "module Cli\n  module Terminal\n    def boot_splash(lines, io:, colorterm: nil, no_color: nil)\n    end\n  end\nend\n") do |text, file|
    next [] unless file == "master/cli/terminal.rb"
    next [] if text.match?(/def boot_splash/)

    [finding(line: 1, message: "the boot splash painter is gone from Cli::Terminal - the console cannot paint the boot")]
  end

  # The operator prompt: host:path$, home-relative, narrowed to where you
  # stand - the shape pub4's face tuned and UX028's context visibility
  # rests on.
  bad_prompt = "module Cli\n  module Prompt\n  end\nend\n"
  good_prompt = <<~'GOOD'
    module Cli
      module Prompt
        def shell_prompt(path: Dir.pwd, host: Socket.gethostname)
          "#{name}:#{dir}$"
        end
      end
    end
  GOOD

  adapter(:structured_data, languages: %w[ruby],
          example_path: "master/cli/prompt.rb",
          bad: bad_prompt, good: good_prompt) do |text, file|
    next [] unless file == "master/cli/prompt.rb"
    next [] if text.match?(/def shell_prompt/) && text.include?('#{name}:#{dir}$')

    [finding(line: 1, message: "the operator prompt host:path$ is gone from Cli::Prompt")]
  end
end
