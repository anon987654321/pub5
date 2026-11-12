import subprocess, os, json, urllib.request, zipfile, io, sys
dest="/opt/rb"; ruby=dest+"/bin/ruby"
if not os.path.exists(ruby): sys.exit(0)
def missing():
    out=subprocess.run(["ldd",ruby],capture_output=True,text=True,env=dict(os.environ,LD_LIBRARY_PATH=dest+"/lib")).stdout
    return [l.split("=>")[0].strip() for l in out.splitlines() if "not found" in l]
pkgmap={"libssl.so.3":"openssl","libcrypto.so.3":"openssl","libffi.so.8":"libffi",
        "libgmp.so.10":"gmp","libyaml-0.so.2":"yaml","libz.so.1":"libzlib",
        "libreadline.so.8":"readline","libncursesw.so.6":"ncurses","libtinfo.so.6":"ncurses",
        "libedit.so.0":"libedit","libgdbm.so.6":"gdbm"}
done=set()
for _ in range(8):
    miss=missing()
    if not miss: break
    todo={pkgmap[m] for m in miss if m in pkgmap} - done
    if not todo: print("unmapped missing:",miss); break
    for p in sorted(todo):
        done.add(p)
        d=json.load(urllib.request.urlopen(f"https://api.anaconda.org/package/conda-forge/{p}",timeout=10))
        fs=[f for f in d["files"] if f["attrs"].get("subdir")=="linux-64"]
        fs.sort(key=lambda f:f.get("upload_time",""))
        f=fs[-1]
        raw=urllib.request.urlopen("https://conda.anaconda.org/conda-forge/"+f["basename"],timeout=40).read()
        if f["basename"].endswith(".conda"):
            z=zipfile.ZipFile(io.BytesIO(raw))
            for n in z.namelist():
                if n.startswith("pkg-") and n.endswith(".tar.zst"):
                    open("/tmp/lib.tar.zst","wb").write(z.read(n))
                    subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/lib.tar.zst -o /tmp/lib.tar && tar -xf /tmp/lib.tar -C "+dest, shell=True, check=True)
        else:
            open("/tmp/lib.tar.bz2","wb").write(raw)
            subprocess.run("tar -xjf /tmp/lib.tar.bz2 -C "+dest, shell=True, check=True)
        print("lib pkg:",p,f["basename"],flush=True)
print("remaining missing:", missing())
