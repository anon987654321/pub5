# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:107 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: faa79ecc2a75ce06
require_relative "master/law/javascript"

Law.define(:NO_WEBGL_GLOW_PASS) do
  source "pixel_perfection forbidden_css: soft glow - the WebGL spelling of it"
  detect { |line| line.match?(/blending:\s*THREE\.AdditiveBlending/) }
  fix "Delete the additive pass. Brightness states form; a second offset pass is a glow."
  bad  "    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending"
  good "    transparent: true, depthWrite: false"
end
