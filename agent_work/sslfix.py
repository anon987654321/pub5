import json, urllib.request, zipfile, io, subprocess
d=json.load(urllib.request.urlopen("https://api.anaconda.org/package/conda-forge/openssl",timeout=10))
fs=[f for f in d["files"] if f["attrs"].get("subdir")=="linux-64" and f["version"].startswith("3.")]
fs.sort(key=lambda f:f.get("upload_time",""))
f=fs[-1]; print("picked", f["basename"])
raw=urllib.request.urlopen("https://conda.anaconda.org/conda-forge/"+f["basename"],timeout=40).read()
if f["basename"].endswith(".conda"):
    z=zipfile.ZipFile(io.BytesIO(raw))
    for n in z.namelist():
        if n.startswith("pkg-") and n.endswith(".tar.zst"):
            open("/tmp/ssl.tar.zst","wb").write(z.read(n))
            subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/ssl.tar.zst -o /tmp/ssl.tar && tar -xf /tmp/ssl.tar -C /opt/rb",shell=True,check=True)
else:
    open("/tmp/ssl.tar.bz2","wb").write(raw); subprocess.run("tar -xjf /tmp/ssl.tar.bz2 -C /opt/rb",shell=True,check=True)
r=subprocess.run("LD_LIBRARY_PATH=/opt/rb/lib /opt/rb/bin/ruby -ropenssl -e 'puts \"RUBY+SSL OK #{RUBY_VERSION} #{OpenSSL::OPENSSL_VERSION}\"'",shell=True,capture_output=True,text=True)
print((r.stdout+r.stderr)[:300])
open("/tmp/bank/agent_work/logs/ruby_version.txt","w").write(r.stdout+r.stderr)
