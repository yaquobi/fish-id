"""بصمة: يجهّز مكتبة الصور المرجعية من أرشيف صور الأسماك (الكتاب) بترتيب أرقام الموسوعة.

لكل سمكة لها اسم محلي في الأرشيف: ننسخ صورها (1..3.jpg) إلى refs/<رقم الموسوعة 4 أرقام>/،
عشان أداة القياس (bench/bioclip/run.py) تبني منها قاعدة البصمات.

docker run --rm -v /opt/fish-id:/w -w /w python:3.12-slim python tool/basma_refs.py data/book/archive data/refs-book
"""
import difflib
import json
import shutil
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
species = json.load(open("assets/data/ksafish.json", encoding="utf-8"))["species"]
# الأسماك بس (الروبيان يشارك نفس الأرقام الأربعة).
sci = {s["sci"].lower().strip(): s["id"].split("-")[-1] for s in species if "FISH" in s["id"] and s.get("sci")}
index = json.load(open(src / "index.json", encoding="utf-8"))
out.mkdir(parents=True, exist_ok=True)
linked = photos = 0
missing = []
for s in index["species"]:
    if not s.get("local") or not s.get("files"):
        continue
    name = " ".join(str(s.get("sci", "")).lower().split())
    sid = sci.get(name)
    if not sid:
        close = difflib.get_close_matches(name, sci, n=1, cutoff=0.9)
        sid = sci[close[0]] if close else None
    if not sid:
        missing.append(name)
        continue
    d = out / sid
    d.mkdir(exist_ok=True)
    for f in s["files"]:
        p = src / s["folder"] / f
        if p.exists():
            shutil.copy(p, d / f"book-{s['n']}-{f}")
            photos += 1
    linked += 1
print(f"{linked} نوع، {photos} صورة → {out}  (بدون رقم موسوعة: {len(missing)})")
