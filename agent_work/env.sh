# source me: . agent_work/env.sh
export RBROOT=/opt/rb
export PATH=/opt/wrap:/opt/zstd/bin:$RBROOT/bin:$PATH
export LD_LIBRARY_PATH=$RBROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export HOME=/root
export BUNDLE_FROZEN=true
export GEM_HOME=$RBROOT/gems
export GEM_PATH=$RBROOT/gems:$RBROOT/lib/ruby/gems/4.0.0
export LANG=C.UTF-8 LC_ALL=C.UTF-8
