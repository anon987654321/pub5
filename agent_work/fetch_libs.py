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
        fs=[f for f in d["files"] if f["attrs"].get("subdir")=="linux-64"]
        if p=="openssl": fs=[f for f in fs if f["version"].startswith("3.")]
        fs.sort(key=lambda f:f.get("upload_time",""))
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
