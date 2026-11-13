export RBROOT=/opt/rb
export PATH=/opt/wrap:/opt/zstd/bin:$RBROOT/bin:$RBROOT/gems/bin:$PATH
export LD_LIBRARY_PATH=$RBROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export HOME=/root
export BUNDLE_FROZEN=true
_PUB5_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export BUNDLE_PATH="$_PUB5_ROOT/MASTER/vendor/bundle"
export GEM_HOME=$RBROOT/gems
export GEM_PATH=$RBROOT/gems:$RBROOT/lib/ruby/gems/4.0.0
export LANG=C.UTF-8 LC_ALL=C.UTF-8
