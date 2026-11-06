# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:90 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e6f1f9459d619d41
require_relative "master/law/javascript"

Law.define(:FACE_POINT_IS_ONE_PIXEL) do
  source "pixel_perfection - MASTER/data/laws.yml, extended to WebGL"
  detect do |line|
    line.match?(/gl_PointSize\s*=/) && !line.match?(/gl_PointSize\s*=\s*1\.0\s*;/)
  end
  fix "One point, one pixel: gl_PointSize=1.0. Put depth and curvature into brightness, not size."
  bad  "  gl_PointSize=clamp(uSize*(260./-mv.z)*sizeBoost,2.0,4.0);"
  good "  gl_PointSize=1.0;"
end
