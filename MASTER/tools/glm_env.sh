#!/bin/bash
# Session environment for a GLM run of MASTER/RAILS in a sandbox without root.
# Source it: source MASTER/tools/glm_env.sh
#
# The checkout-local Ruby (bin/dev-bootstrap) has the right compiled-in
# prefix, its own openssl/libyaml/zlib, and needs NO RUBYLIB/LD_LIBRARY_PATH
# pollution. Never let a Debian-extracted Ruby wrapper's env vars reach
# MASTER: RUBYLIB pointing at the Debian 3.3 stdlib breaks the tools Ruby's
# gem_prelude, and the version probe then fails, which reads as
# "PUB5_RUBY is not compatible".
unset RUBYLIB RUBYOPT LD_LIBRARY_PATH GEM_HOME GEM_PATH BUNDLE_BIN_PATH BUNDLER_SETUP
PUB5_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_RUBY="$PUB5_ROOT/MASTER/.tools/ruby"
if [ -x "$TOOLS_RUBY/bin/ruby" ]; then
  export PUB5_RUBY="$TOOLS_RUBY/bin/ruby"
  export PUB5_BUNDLE="$TOOLS_RUBY/bin/bundle"
  export PATH="$TOOLS_RUBY/bin:$HOME/bin:$PATH"
  export PKG_CONFIG_PATH="$TOOLS_RUBY/lib/pkgconfig:$HOME/.local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
else
  echo "glm_env.sh: no tools Ruby at $TOOLS_RUBY — run MASTER/bin/dev-bootstrap first" >&2
fi
# Session-scoped GLM reroute: the local loopback gateway fronts the internal
# z.ai endpoint, and gateway:glm-5.3 leads every /fix call as primary #1.
# Start the gateway beside it: node "$PUB5_ROOT/MASTER/tools/glm_gateway.js" &
export MASTER_LLM_GATEWAY_URL="${MASTER_LLM_GATEWAY_URL:-http://127.0.0.1:8787/v1}"
export MASTER_MODEL="${MASTER_MODEL:-gateway:glm-5.3}"
# Chrome for Testing headless shell (installed by MASTER/tools/chrome_install.rb);
# take the newest installed version instead of hardcoding one.
CHROME_BIN="$(ls -1d "$HOME"/.cache/pub5/chrome-headless-shell/*/chrome-headless-shell 2>/dev/null | sort -V | tail -1)"
[ -n "$CHROME_BIN" ] && export CHROME_PATH="$CHROME_BIN"
