import sys, zipfile, io, os, subprocess
pkg, dest = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(pkg)
names = [n for n in z.namelist() if n.startswith("pkg-") and n.endswith(".tar.zst")]
os.makedirs(dest, exist_ok=True)
for n in names:
    open("/tmp/p.tar.zst","wb").write(z.read(n))
    subprocess.run("PATH=/opt/zstd/bin:$PATH zstd -d -f /tmp/p.tar.zst -o /tmp/p.tar && tar -xf /tmp/p.tar -C "+dest, shell=True, check=True)
print("extracted", names, "->", dest)
