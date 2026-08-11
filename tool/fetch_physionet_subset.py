import urllib.request, os, concurrent.futures, sys
BASE = "https://physionet-open.s3.amazonaws.com/challenge-2019/1.0.0/training/training_setA/p%06d.psv"
DEST = os.path.join("tool", "datasets", "real", "physionet2019_trainingA_subset")
N = 4000
THREADS = 16
os.makedirs(DEST, exist_ok=True)
def fetch(i):
    url = BASE % i
    dst = os.path.join(DEST, "p%06d.psv" % i)
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return (i, True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "CareBridge/1.0"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        with open(dst, "wb") as f:
            f.write(data)
        return (i, True)
    except Exception:
        return (i, False)
with concurrent.futures.ThreadPoolExecutor(max_workers=THREADS) as ex:
    results = list(ex.map(fetch, range(1, N + 1)))
ok = sum(1 for _, s in results if s)
total = sum(os.path.getsize(os.path.join(DEST, "p%06d.psv" % i)) for i, s in results if s)
print("downloaded %d/%d files, %.1f MB" % (ok, N, total / 1e6))
sys.stdout.flush()
