import sys, re, os, urllib.request, concurrent.futures as cf
lock, cache = sys.argv[1], sys.argv[2]
os.makedirs(cache, exist_ok=True)
specs=set()
for line in open(lock):
    m = re.match(r"^    ([A-Za-z0-9_\-]+) \(([0-9][^) ]*)(?: ([^)]+))?\)", line)
    if m:
        n,v,p = m.groups()
        specs.add(f"{n}-{v}" + (f"-{p}" if p else ""))
specs.add("bundler-4.0.20")
def get(s):
    f=os.path.join(cache, s+".gem")
    if os.path.exists(f) and os.path.getsize(f)>0: return s+" cached"
    try:
        urllib.request.urlretrieve(f"https://rubygems.org/downloads/{s}.gem", f)
        return s+" ok"
    except Exception as e:
        return s+" FAIL "+repr(e)[:80]
with cf.ThreadPoolExecutor(16) as ex:
    res=list(ex.map(get, sorted(specs)))
print("\n".join(res)); print("FAILS:", sum("FAIL" in r for r in res), "/", len(res))
