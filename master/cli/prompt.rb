# frozen_string_literal: true

require "socket"

module Cli
  # The OpenBSD operator prompt, host:path$ - e.g. vm23:~/pub5$. Ported from
  # pub4 MASTER/lib/face.rb#shell_prompt, where the operator tuned it: the
  # host is its first name, the path is home-relative and narrows to where
  # you are standing when it must, and the whole line stays within budget.
  module Prompt
    HOST_MAX = 8
    PATH_SOFT_MAX = 24
    PROMPT_MAX_CH = 72 # pub4 face.yml#prompt.max_ch, its default here

    module_function

    def shell_prompt(path: Dir.pwd, host: Socket.gethostname)
      name = host.to_s.split(".").first.to_s.split("-").first.to_s[0, HOST_MAX]
      name = "openbsd" if name.empty?
      home = Dir.home
      dir = path.to_s == home ? "~" : path.to_s.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
      budget = [PROMPT_MAX_CH - name.length - 3, 1].max
      if dir.length > PATH_SOFT_MAX && dir.count("/") > 2
        dir = "~/.../#{dir.split('/').last(2).join('/')}"
      end
      dir = dir[-budget, budget] if dir.length > budget
      "#{name}:#{dir}$"
    end
  end
end
