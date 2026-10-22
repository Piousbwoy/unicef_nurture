"""Exact table census, same way governance_test.dart does it."""
import re, os, glob

BASE = r"C:\Users\Alhaji_stunner\Videos\unicef"
out = []

# --- district: schema.sql + every migration ---
district = set()
files = [os.path.join(BASE, "server", "schema.sql")]
files += sorted(glob.glob(os.path.join(BASE, "server", "migrations", "*.sql")))
for f in files:
    s = open(f, encoding="utf-8").read()
    for m in re.finditer(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([`\w]+)", s, re.I):
        district.add(m.group(1).strip("`").lower())
out.append("DISTRICT files scanned: %d" % len(files))
out.append("DISTRICT distinct tables: %d" % len(district))
out.append(", ".join(sorted(district)))

# --- local: Tables class constants in app_database.dart ---
s = open(os.path.join(BASE, "lib", "data", "local", "app_database.dart"), encoding="utf-8").read()
tbl = re.findall(r"static\s+const\s+\w+\s*=\s*'([^']+)'", s)
out.append("")
out.append("LOCAL Tables-class names: %d" % len(tbl))
out.append(", ".join(sorted(set(tbl))))

# --- local: CREATE TABLE statements actually emitted ---
cre = re.findall(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:\$\{Tables\.(\w+)\}|`?(\w+)`?)", s)
names = [a or b for a, b in cre]
out.append("")
out.append("LOCAL CREATE TABLE count: %d  distinct: %d" % (len(names), len(set(names))))
out.append(", ".join(sorted(set(names))))

open(os.path.join(BASE, "pitch", "day1", "table_census.txt"), "w", encoding="utf-8").write("\n".join(out))
print("\n".join(out[:2]))
print("wrote table_census.txt")
