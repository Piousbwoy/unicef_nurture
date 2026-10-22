import os, glob
BASE = r"C:\Users\Alhaji_stunner\Videos\unicef\assets\audio"
out = []
if os.path.isdir(BASE):
    for d in sorted(os.listdir(BASE)):
        p = os.path.join(BASE, d)
        if not os.path.isdir(p):
            continue
        wavs = glob.glob(os.path.join(p, "**", "*.wav"), recursive=True)
        mp3s = glob.glob(os.path.join(p, "**", "*.mp3"), recursive=True)
        out.append("%-22s wav=%-4d mp3=%-4d" % (d, len(wavs), len(mp3s)))
txt = "\n".join(out)
open(r"C:\Users\Alhaji_stunner\Videos\unicef\pitch\day1\audio_counts.txt", "w", encoding="utf-8").write(txt)
print(txt.encode("ascii", "replace").decode())
