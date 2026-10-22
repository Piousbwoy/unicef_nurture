import re, collections, os
BASE = r"C:\Users\Alhaji_stunner\Videos\unicef"
s = open(os.path.join(BASE, "lib", "domain", "governance.dart"), encoding="utf-8").read()

out = []
out.append("SecurityControl constructors: %d" % len(re.findall(r"SecurityControl\(", s)))
c = collections.Counter(re.findall(r"maturity:\s*(ControlMaturity\.\w+)", s))
for k, v in sorted(c.items()):
    out.append("  %-38s %d" % (k, v))
i = s.find("enum ControlMaturity")
out.append("enum ControlMaturity block:")
out.append(s[i:i + 500])

# security control ids only (those appearing after the first SecurityControl() call)
sec = s[s.find("SecurityControl("):]
ids = re.findall(r"id:\s*'([a-z0-9-]+)'", sec)
out.append("security control ids: %d" % len(ids))
out.append(", ".join(ids))

open(os.path.join(BASE, "pitch", "day1", "gov_counts.txt"), "w", encoding="utf-8").write("\n".join(out))
print("\n".join(out[:8]))
