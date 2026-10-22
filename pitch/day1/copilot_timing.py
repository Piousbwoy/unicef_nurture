"""Real speaking time for the in-app pitch copilot narration."""
import re, os

BASE = r"C:\Users\Alhaji_stunner\Videos\unicef"
s = open(os.path.join(BASE, "lib", "presentation", "shared", "ai_pitch_copilot.dart"), encoding="utf-8").read()

blocks = re.findall(r"narration:\s*\n\s*'((?:[^'\\]|\\.)*)',", s)
est = re.findall(r"durationEstimate:\s*'~?(\d+)s'", s)
tabs = re.findall(r"shortTab:\s*'([^']+)'", s)

out = []
total_w = 0
for i, b in enumerate(blocks):
    w = len(b.replace("\\'", "Apostrophe").split())
    total_w += w
    claim = est[i] if i < len(est) else "?"
    for rate, lbl in ((150, "measured"), (170, "brisk")):
        pass
    secs150 = w / 150 * 60
    secs170 = w / 170 * 60
    out.append(
        "%-22s %4d words | @150wpm %3ds | @170wpm %3ds | file claims %s"
        % (tabs[i] if i < len(tabs) else "?", w, secs150, secs170, claim + "s")
    )

out.append("")
out.append("TOTAL words: %d" % total_w)
out.append("TOTAL @150 wpm: %ds = %.1f min" % (total_w / 150 * 60, total_w / 150))
out.append("TOTAL @170 wpm: %ds = %.1f min" % (total_w / 170 * 60, total_w / 170))
out.append("Sum of per-scene claims: %ds = %.1f min" % (sum(int(x) for x in est), sum(int(x) for x in est) / 60))
out.append("")
out.append("NOTE: excludes slide transitions, device handling, live tapping through flows,")
out.append("and any answer to a question. The slot is ~6 minutes TOTAL including changeover.")

txt = "\n".join(out)
open(os.path.join(BASE, "pitch", "day1", "copilot_timing.txt"), "w", encoding="utf-8").write(txt)
print(txt)
