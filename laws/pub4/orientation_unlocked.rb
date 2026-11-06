# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:543 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e3621c789190366e
require_relative "master/law/javascript"

module Law
  ::Law.define(:ORIENTATION_UNLOCKED) do
    source "WCAG 1.3.4 Orientation, AA"
    tags %i[ACCESSIBILITY]
    path %r{manifest(?:\.json)?(?:\.erb)?\z|\.webmanifest\z|\.js\z}
    example_path "/repo/app/views/pwa/manifest.json.erb"
    fix "Drop the orientation key (or use any); lock only where the task needs it, noting `orientation: essential`."
    bad "{\n  \"name\": \"brgen\",\n  \"orientation\": \"portrait\"\n}\n"
    good "{\n  \"name\": \"brgen\",\n  \"display\": \"standalone\"\n}\n"
    check do |src, _path|
      next [] if src.match?(/orientation:\s*essential/)

      src.each_line.with_index(1).filter_map do |line, n|
        finding(line: n, message: "the screen orientation is locked") if line.match?(S::LOCKED)
      end
    end
  end
end
