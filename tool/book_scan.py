"""النسخة الثانية من كتاب أسماك البحر الأحمر (نسخة ممسوحة بالسكانر، بدون نص): نقرأ كل صفحة بـ Claude
ونطلع لكل سمكة اسمها العلمي والإنجليزي واسمها المحلي (المكتوب بالأحمر) ومكان صورتها، وبعدين ندمجها مع الأرشيف:
- سمكة موجودة في الأرشيف بدون اسم محلي ← ناخذ اسمها من النسخة الثانية.
- سمكة موجودة ولها أسماء ← نضيف الأسماء الزيادة.
- سمكة جديدة لها اسم محلي ← نقص صورتها من الصفحة ونضيفها للأرشيف.

docker run --rm --env-file server/.env -v /opt/fish-id/data/book:/b python:3.12-slim sh -c \
  "pip -q install pymupdf pillow anthropic && python /b/scan.py /b/fish2.pdf /b/archive [read|merge]"
"""
import base64
import io
import json
import os
import re
import sys

import anthropic
import fitz
from PIL import Image

PDF, OUT = sys.argv[1], sys.argv[2]
STEP = sys.argv[3] if len(sys.argv) > 3 else "read"
MODEL = os.environ.get("BOOK_MODEL", "claude-opus-5-5")
scan_path = f"{OUT}/scan2.json"
scan = json.load(open(scan_path)) if os.path.exists(scan_path) else {"pages": {}, "usage": {"in": 0, "out": 0}}

PROMPT = """This is a scanned page of the Saudi book "Fishes of the Saudi Red Sea" (Jeddah fisheries research centre).
Species pages show fish photos; under each photo is its scientific name (italic Latin) and English name (blue); the fish's LOCAL Arabic name(s) are printed in RED Arabic text near its photo (several names separated by "،").
For every fish species on this page return:
- "sci": scientific name (genus species) exactly as printed
- "english": English name ("" if none)
- "local": list of the RED Arabic local names for this fish, exactly as printed ([] if none)
- "box": the bounding box of this species' main photo as fractions of the page [x0, y0, x1, y1] (0..1, origin top-left)
If the page has no species photos (introduction, family drawings, text), return an empty list.
Reply with JSON only: {"species": [ ... ]}"""


def jpeg(img, q=85):
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=q)
    return buf.getvalue()


def render(page, zoom):
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom))
    return Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")


doc = fitz.open(PDF)
if STEP == "read":
    client = anthropic.Anthropic()
    for pno in range(1, len(doc) + 1):
        if str(pno) in scan["pages"]:
            continue
        img = render(doc[pno - 1], 1.0)
        img.thumbnail((1568, 1568))
        try:
            msg = client.messages.create(model=MODEL, max_tokens=3000, messages=[{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.b64encode(jpeg(img)).decode()}},
                {"type": "text", "text": PROMPT},
            ]}])
        except Exception as e:  # noqa: BLE001
            print(f"page {pno}: {e}", flush=True)
            continue
        scan["usage"]["in"] += msg.usage.input_tokens
        scan["usage"]["out"] += msg.usage.output_tokens
        text = "".join(b.text for b in msg.content if b.type == "text")
        m = re.search(r"\{.*\}", text, re.S)
        try:
            found = json.loads(m.group(0))["species"] if m else []
        except ValueError:
            found = []
        scan["pages"][str(pno)] = found
        json.dump(scan, open(scan_path, "w"), ensure_ascii=False, indent=1)
        print(f"page {pno}: " + "; ".join(f"{s.get('sci')} {s.get('local')}" for s in found), flush=True)
    print("usage", scan["usage"])

elif STEP == "merge":
    index = json.load(open(f"{OUT}/index.json"))
    key = lambda s: re.sub(r"\s+", " ", s.lower().strip())  # noqa: E731

    def norm(name):
        """نفس الاسم بكتابة مختلفة (همزات، تشكيل، ى/ي، ة/ه، مسافات) يحسب اسم واحد."""
        name = re.sub(r"[\u064B-\u0652\u0640]", "", name)
        name = name.translate(str.maketrans("أإآىة", "ااايه"))
        return re.sub(r"\s+", "", name)

    def dist(a, b):
        prev = list(range(len(b) + 1))
        for i, ca in enumerate(a, 1):
            cur = [i]
            for j, cb in enumerate(b, 1):
                cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
            prev = cur
        return prev[-1]

    by_sci = {}
    for s in index["species"]:
        by_sci.setdefault(key(s["sci"]), s)

    def find(sci):
        if sci in by_sci:
            return by_sci[sci]
        best = min(by_sci, key=lambda k: dist(k, sci) if abs(len(k) - len(sci)) < 4 else 99, default=None)
        return by_sci[best] if best and dist(best, sci) <= 2 else None
    filled = added_names = new = 0
    for pno, found in scan["pages"].items():
        for f in found:
            names = [n.strip() for n in f.get("local", []) if isinstance(n, str) and n.strip()]
            sci = key(f.get("sci", ""))
            if not names or len(sci.split()) < 2:
                continue
            s = find(sci)
            if s is not None:
                if not s.get("local"):
                    s["local"] = names
                    s["local_src"] = "scan2"
                    filled += 1
                else:
                    seen = {norm(n) for n in s["local"]}
                    extra = []
                    for n in names:
                        if norm(n) not in seen:
                            seen.add(norm(n))
                            extra.append(n)
                    if extra:
                        s["local"] = s["local"] + extra
                        added_names += len(extra)
                json.dump(s, open(f"{OUT}/{s['folder']}/meta.json", "w"), ensure_ascii=False, indent=1)
                continue
            # سمكة جديدة: نقص صورتها من الصفحة الممسوحة.
            box = f.get("box")
            if not (isinstance(box, list) and len(box) == 4):
                continue
            img = render(doc[int(pno) - 1], 2.0)
            w, h = img.size
            x0, y0, x1, y1 = (max(0.0, min(1.0, float(v))) for v in box)
            if x1 - x0 < .05 or y1 - y0 < .03:
                continue
            crop = img.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))
            n = len(index["species"]) + 1
            folder = f"{n:03d}_{re.sub(r'[^A-Za-z]+', '_', f['sci']).strip('_')}"
            os.makedirs(f"{OUT}/{folder}", exist_ok=True)
            crop.save(f"{OUT}/{folder}/1.jpg", "JPEG", quality=90)
            thumb = crop.copy()
            thumb.thumbnail((900, 900))
            thumb.save(f"{OUT}/{folder}/app.jpg", "JPEG", quality=80, optimize=True, progressive=True)
            entry = {"n": n, "page": int(pno), "folder": folder, "sci": f["sci"], "english": f.get("english", ""),
                     "local": names, "note": "", "files": ["1.jpg"], "source": "scan2"}
            json.dump(entry, open(f"{OUT}/{folder}/meta.json", "w"), ensure_ascii=False, indent=1)
            index["species"].append(entry)
            by_sci[sci] = entry
            new += 1
    json.dump(index, open(f"{OUT}/index.json", "w"), ensure_ascii=False, indent=1)
    have = sum(1 for s in index["species"] if s.get("local"))
    print(f"filled {filled}, extra names {added_names}, new species {new}; with names {have}/{len(index['species'])}")
    for s in index["species"]:
        if not s.get("local"):
            print("NO NAME", s["sci"])
