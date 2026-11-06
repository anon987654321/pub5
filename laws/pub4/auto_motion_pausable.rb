# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:504 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3e22db1be0c57d07
require_relative "master/law/javascript"

module Law
  ::Law.define(:AUTO_MOTION_PAUSABLE) do
    source "WCAG 2.2.2 Pause, Stop, Hide, A; visual_identity.motion.default: still"
    tags %i[ACCESSIBILITY]
    path Regexp.union(/\.js\z/, /\.s?css\z/, S::SNAP::SNAPSHOT)
    fix "Hold still by default; anything that advances by itself past five seconds gets a pause button (aria-pressed)."
    carousel = "connect() { this.timer = setInterval(() => this.track.style.transform = next(), 4000) }\n"
    bad carousel
    good "#{carousel}pause() { clearInterval(this.timer) }\n"
    check do |src, _path|
      moving = src.match?(S::TIMER) && src.match?(S::MOVES) && !src.match?(/pause|aria-pressed/i)
      message = "content advances by itself with no pause control"
      moving ? [finding(line: S.line_of(src, S::TIMER), message:)] : []
    end
    adapter(:whole_file, languages: %i[css scss], bad: ".hero-track { animation: drift 8s linear infinite; }\n",
                         good: ".spinner { animation: spin 1s linear infinite; }\n") do |src, _file|
      S.endless(src).map { |hit| finding(**hit) }
    end
    adapter(:rendered_ui, languages: %i[json], example_path: S::SNAP::EXAMPLE, bad: S.motion(40), good: S.motion(0),
                          &S.rendered(:AUTO_MOTION_PAUSABLE))
  end
end
