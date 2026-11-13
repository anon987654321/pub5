#!/usr/bin/env bash
# Idempotent sandbox setup for pub5 MASTER. Rebuilt 2026-11-13 from banked artifacts.
# GH_TOKEN via env only; never written to disk. Canonical URLs only (conda-forge, rubygems.org).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }
log "tools: $(command -v gcc cc make bash zstd bzip2 tar 2>/dev/null | tr '\n' ' ')"
if ! command -v zstd >/dev/null 2>&1 && [ ! -x /opt/zstd/bin/zstd ]; then
  log "bootstrap zstd from conda-forge"
  python3 - <<'PY'
import json, urllib.request, tarfile, io, os
d=json.load(urllib.request.urlopen("https://conda.anaconda.org/conda-forge/linux-64/repodata.json", timeout=180))
c=sorted(k for k in d.get("packages",{}) if k.startswith("zstd-1.5.2") and k.endswith(".tar.bz2"))
k=c[-1]; print("zstd pkg:", k)
b=urllib.request.urlopen("https://conda.anaconda.org/conda-forge/linux-64/"+k, timeout=180).read()
os.makedirs("/opt/zstd", exist_ok=True)
tarfile.open(fileobj=io.BytesIO(b), mode="r:bz2").extractall("/opt/zstd")
PY
fi
export PATH=/opt/zstd/bin:$PATH
if [ ! -x /opt/rb/bin/ruby ]; then
  U="https://conda.anaconda.org/conda-forge/linux-64/ruby-4.0.9-h462e025_1.conda"
  log "download $U"
  python3 -c "import urllib.request;urllib.request.urlretrieve('$U','/tmp/ruby.conda')" || { log FAIL_RUBY_DL; exit 1; }
  python3 agent_work/extract_ruby.py /tmp/ruby.conda /opt/rb || { log FAIL_EXTRACT; exit 1; }
fi
log "ruby: $(/opt/rb/bin/ruby -v 2>&1 | head -1)"
python3 agent_work/fetch_libs.py || log WARN_FETCH_LIBS
mkdir -p /opt/wrap
for c in gcc cc g++ c++; do
  real="$(command -v $c 2>/dev/null || true)"; [ -n "$real" ] || continue
  printf '#!/usr/bin/env bash\nargs=()\nfor a in "$@"; do [[ $a == -Werror* ]] || args+=("$a"); done\nexec %s -D_GNU_SOURCE "${args[@]}"\n' "$real" > /opt/wrap/$c
  chmod +x /opt/wrap/$c
done
if [ -d /bin ] && [ ! -L /bin ]; then
  log "usr-merge /bin -> /usr/bin"
  cp -an /bin/. /usr/bin/ 2>/dev/null || true
  rm -rf /bin && ln -s usr/bin /bin
fi
. agent_work/env.sh
log "ruby now: $(ruby -v 2>&1 | head -1)"
python3 agent_work/fetch_gems.py MASTER/Gemfile.lock MASTER/vendor/cache || { log FAIL_GEM_FETCH; exit 1; }
gem install --local --no-document MASTER/vendor/cache/bundler-*.gem 2>/dev/null || true
cd MASTER
bundle config set --local frozen true
bundle install --local && log BUNDLE_INSTALL_OK || { log FAIL_BUNDLE_INSTALL; exit 1; }
bundle check && log BUNDLE_CHECK_OK
log SETUP_DONE
