import sys, zipfile, os, subprocess
pkg, dest = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(pkg); os.makedirs(dest, exist_ok=True)
for n in z.namelist():
    if n.startswith("pkg-") and n.endswith(".tar.zst"):
        open("/tmp/p.tar.zst","wb").write(z.read(n))
        subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/p.tar.zst -o /tmp/p.tar && tar -xf /tmp/p.tar -C "+dest, shell=True, check=True)
print("extracted ->", dest)
