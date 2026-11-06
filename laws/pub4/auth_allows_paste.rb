# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:491 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 704c2f3a23bfc5f2
require_relative "master/law/html"

module Law
  ::Law.define(:AUTH_ALLOWS_PASTE) do
    source "WCAG 2.2 SC 3.3.8 Accessible Authentication (Minimum), AA"
    tags %i[ACCESSIBILITY SECURITY]
    path Regexp.union(M::TEMPLATES, /\.js\z/)
    fix "Let password and one-time-code fields take paste and autofill (current-password, one-time-code); " \
        "no puzzle without an alternative."
    bad "<input type=\"password\" onpaste=\"return false\">\n"
    good "<input type=\"password\" autocomplete=\"current-password\">\n"
    check do |src, path|
      auth = path.to_s.match?(/session|registration|password|login|signup|sign_in|sign_up/)
      src.each_line.with_index(1).filter_map do |line, n|
        (message = M.paste_blocker(line, auth)) && finding(line: n, message:)
      end
    end
    adapter(:whole_file, languages: %i[javascript], bad: "el.addEventListener(\"paste\", (e) => e.preventDefault())\n",
                         good: "el.addEventListener(\"input\", (e) => this.check(e))\n") do |src, _file|
      blocks = src.match?(/addEventListener\(\s*["']paste["']|\.onpaste\s*=/) && src.include?("preventDefault")
      at = src.lines.index { |line| line.include?("paste") }.to_i + 1
      blocks ? [finding(line: at, message: "paste is prevented")] : []
    end
  end
end
