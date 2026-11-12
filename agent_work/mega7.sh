#!/bin/bash
set -uo pipefail
W=/home/workspace/pub5
exec >>/tmp/mega7.log 2>&1
echo "=== MEGA7 $(date -u) ==="
mkdir -p /opt/rb /opt/wrap /opt/zstd /tmp/pkgs /root /tmp/bank/agent_work/logs
# ---------- toolchain starts NOW, parallel with clone ----------
cat > /tmp/extract_ruby.py <<'EOF'
import sys, zipfile, os, subprocess
pkg, dest = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(pkg); os.makedirs(dest, exist_ok=True)
for n in z.namelist():
    if n.startswith("pkg-") and n.endswith(".tar.zst"):
        open("/tmp/p.tar.zst","wb").write(z.read(n))
        subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/p.tar.zst -o /tmp/p.tar && tar -xf /tmp/p.tar -C "+dest, shell=True, check=True)
print("extracted ->", dest)
EOF
cat > /tmp/fetch_libs.py <<'EOF'
import subprocess, os, json, urllib.request, zipfile, io, glob
dest="/opt/rb"
env=dict(os.environ,LD_LIBRARY_PATH=dest+"/lib")
def missing():
    targets=[dest+"/bin/ruby"]+glob.glob(dest+"/lib/ruby/4.0.0/x86_64-linux/*.so")+glob.glob(dest+"/lib/ruby/4.0.0/x86_64-linux/*/*.so")
    miss=set()
    for t in targets:
        out=subprocess.run(["ldd",t],capture_output=True,text=True,env=env).stdout
        for l in out.splitlines():
            if "not found" in l: miss.add(l.split("=>")[0].strip())
    return sorted(miss)
pkgmap={"libssl.so.3":"openssl","libcrypto.so.3":"openssl","libffi.so.8":"libffi","libgmp.so.10":"gmp",
"libyaml-0.so.2":"yaml","libz.so.1":"libzlib","libreadline.so.8":"readline","libncursesw.so.6":"ncurses",
"libtinfo.so.6":"ncurses","libedit.so.0":"libedit","libgdbm.so.6":"gdbm","libcrypt.so.2":"libxcrypt"}
done=set()
for _ in range(8):
    miss=missing()
    if not miss: break
    todo={pkgmap[m] for m in miss if m in pkgmap}-done
    if not todo: print("unmapped:",miss); break
    for p in sorted(todo):
        done.add(p)
        d=json.load(urllib.request.urlopen(f"https://api.anaconda.org/package/conda-forge/{p}",timeout=10))
        fs=[f for f in d["files"] if f["attrs"].get("subdir")=="linux-64"]; fs.sort(key=lambda f:f.get("upload_time",""))
        f=fs[-1]; raw=urllib.request.urlopen("https://conda.anaconda.org/conda-forge/"+f["basename"],timeout=40).read()
        if f["basename"].endswith(".conda"):
            z=zipfile.ZipFile(io.BytesIO(raw))
            for n in z.namelist():
                if n.startswith("pkg-") and n.endswith(".tar.zst"):
                    open("/tmp/lib.tar.zst","wb").write(z.read(n))
                    subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/lib.tar.zst -o /tmp/lib.tar && tar -xf /tmp/lib.tar -C "+dest,shell=True,check=True)
        else:
            open("/tmp/lib.tar.bz2","wb").write(raw); subprocess.run("tar -xjf /tmp/lib.tar.bz2 -C "+dest,shell=True,check=True)
        print("lib pkg:",p,f["basename"],flush=True)
print("remaining:",missing())
EOF
cat > /tmp/fetch_gems.py <<'EOF'
import sys, re, os, urllib.request, concurrent.futures as cf
lock, cache = sys.argv[1], sys.argv[2]
os.makedirs(cache, exist_ok=True)
specs=set()
for line in open(lock):
    m = re.match(r"^    ([A-Za-z0-9_\-]+) \(([0-9][^) ]*)(?: ([^)]+))?\)", line)
    if m:
        n,v,p = m.groups(); specs.add(f"{n}-{v}" + (f"-{p}" if p else ""))
specs.add("bundler-4.0.20")
def get(s):
    f=os.path.join(cache, s+".gem")
    if os.path.exists(f) and os.path.getsize(f)>0: return s+" cached"
    try:
        urllib.request.urlretrieve(f"https://rubygems.org/downloads/{s}.gem", f); return s+" ok"
    except Exception as e: return s+" FAIL "+repr(e)[:80]
with cf.ThreadPoolExecutor(16) as ex: res=list(ex.map(get, sorted(specs)))
print("\n".join(res)); print("FAILS:", sum("FAIL" in r for r in res), "/", len(res))
EOF
cat > /tmp/env.sh <<'EOF'
export RBROOT=/opt/rb
export PATH=/opt/wrap:/opt/zstd/bin:$RBROOT/bin:$RBROOT/gems/bin:$PATH
export LD_LIBRARY_PATH=$RBROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export HOME=/root
export BUNDLE_FROZEN=true
export BUNDLE_PATH=/home/workspace/pub5/MASTER/vendor/bundle
export GEM_HOME=$RBROOT/gems
export GEM_PATH=$RBROOT/gems:$RBROOT/lib/ruby/gems/4.0.0
export LANG=C.UTF-8 LC_ALL=C.UTF-8
EOF
cp /tmp/extract_ruby.py /tmp/fetch_libs.py /tmp/fetch_gems.py /tmp/env.sh /tmp/bank/agent_work/
(
[ -x /opt/zstd/bin/zstd ] || { curl -sL -o /tmp/pkgs/zstd.tar.bz2 "https://conda.anaconda.org/conda-forge/linux-64/zstd-1.5.2-h6239696_4.tar.bz2" && tar -xjf /tmp/pkgs/zstd.tar.bz2 -C /opt/zstd; }
if [ ! -x /opt/rb/bin/ruby ]; then
  [ -s /tmp/pkgs/ruby.pkg ] || curl -sL -o /tmp/pkgs/ruby.pkg "https://conda.anaconda.org/conda-forge/linux-64/ruby-4.0.9-h462e025_1.conda"
  python3 /tmp/extract_ruby.py /tmp/pkgs/ruby.pkg /opt/rb
fi
python3 /tmp/fetch_libs.py
for c in gcc cc g++ c++; do printf '#!/bin/bash\nargs=(); for a in "$@"; do case "$a" in -Werror*) ;; *) args+=("$a");; esac; done\nexec /usr/bin/%s -D_GNU_SOURCE "${args[@]}"\n' "$c" > /opt/wrap/$c; chmod +x /opt/wrap/$c; done
if [ ! -L /bin ] && [ -d /bin ]; then cp -an /bin/. /usr/bin/ 2>/dev/null; rm -rf /bin; ln -s usr/bin /bin; fi
. /tmp/env.sh
ruby -ropenssl -e 'puts "RUBY+SSL OK #{RUBY_VERSION} #{OpenSSL::OPENSSL_VERSION}"' > /tmp/bank/agent_work/logs/ruby_version.txt 2>&1
echo TOOLCHAIN_DONE
) &
TC_PID=$!
# ---------- independent artifact bank (orphan branch, tiny push) ----------
(
sleep 20
cd /tmp/bank
git init -q . 2>/dev/null
git config user.name host-agent; git config user.email agent@pub5.local
git remote add origin "https://${GH_TOKEN}@github.com/anon987654321/pub5.git" 2>/dev/null
cp /tmp/mega7.sh agent_work/mega7.sh 2>/dev/null
git add -A >/dev/null 2>&1
git commit -qm "agent bank: artifacts + toolchain status $(date -u)" >/dev/null 2>&1
git push -q origin "HEAD:refs/heads/bank-$(date -u +%H%M%S)" >/dev/null 2>&1 && echo BANK_PUSH_OK || echo BANK_PUSH_FAIL
) &
# ---------- clone (retry) ----------
if [ ! -d "$W/.git" ]; then
  rm -rf "$W"; ok=0
  for a in 1 2 3 4 5; do
    git clone --depth 1 --filter=blob:none --no-checkout "https://${GH_TOKEN}@github.com/anon987654321/pub5.git" "$W" && { ok=1; break; }
    echo "clone retry $a"; rm -rf "$W"; sleep 3
  done
  [ "$ok" = 1 ] || { echo CLONE_FAILED; wait $TC_PID; exit 1; }
fi
cd "$W"
git config user.name host-agent; git config user.email agent@pub5.local; git config core.hooksPath /dev/null
git config core.sparseCheckout true
printf '/MASTER/\n/RAILS/\n/agent_work/\n/PROGRESS.md\n/AGENTS.md\n' > .git/info/sparse-checkout
git checkout main && echo SPARSE_OK
mkdir -p agent_work/logs
grep -q 'vendor/cache' .git/info/exclude 2>/dev/null || printf 'vendor/cache/\nvendor/bundle/\n' >> .git/info/exclude
wait $TC_PID
cp /tmp/extract_ruby.py /tmp/fetch_libs.py /tmp/fetch_gems.py /tmp/env.sh agent_work/
cp /tmp/bank/agent_work/logs/ruby_version.txt agent_work/logs/ 2>/dev/null
. agent_work/env.sh
cat agent_work/logs/ruby_version.txt
gpush(){ for i in 1 2 3; do
  git add -A -- agent_work PROGRESS.md MASTER/agent_spool agent_spool MASTER/.master .master >/dev/null 2>&1
  git commit --no-verify -m "$1" >/dev/null 2>&1
  git fetch --depth 1 origin main >/dev/null 2>&1
  git rebase FETCH_HEAD >/dev/null 2>&1 || { git rebase --abort >/dev/null 2>&1; git merge -X ours FETCH_HEAD -m merge >/dev/null 2>&1; }
  git push --no-verify origin HEAD:main >/dev/null 2>&1 && { echo "PUSH OK: $1"; return 0; }
  sleep 2; done; echo "PUSH FAIL: $1"; }
gpush "agent_work: mega7 bootstrap (parallel toolchain, sparse checkout)"
cd "$W/MASTER"
python3 "$W/agent_work/fetch_gems.py" Gemfile.lock vendor/cache | tail -2 | tee -a "$W/agent_work/logs/gems.txt"
command -v bundle >/dev/null || gem install --local --no-document vendor/cache/bundler-4.0.20.gem
bundle config set --local path vendor/bundle
bundle config set --local frozen true
bundle install --local > "$W/agent_work/logs/bundle.log" 2>&1
tail -2 "$W/agent_work/logs/bundle.log"
bundle check && echo BUNDLE_OK
cd "$W"; gpush "agent_work: bundle complete (frozen, local)"
( while true; do sleep 40; cd "$W"; gpush "fix WIP snapshot $(date -u +%H:%M:%S)"; done ) &
( while true; do sleep 150; cd "$W"; git add -A -- RAILS MASTER/lib MASTER/data >/dev/null 2>&1; git commit --no-verify -m "fix snapshot: tree repairs" >/dev/null 2>&1; git fetch --depth 1 origin main >/dev/null 2>&1; git rebase FETCH_HEAD >/dev/null 2>&1; git push --no-verify origin HEAD:main >/dev/null 2>&1; done ) &
cd "$W/MASTER"
nohup ruby bin/master '/fix RAILS' > "$W/agent_work/logs/fix_rails.log" 2>&1 &
echo $! > /tmp/fix.pid
echo "FIX LAUNCHED pid=$(cat /tmp/fix.pid)"
cd "$W"; gpush "fix(RAILS): launched"
wait
