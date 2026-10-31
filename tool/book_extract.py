"""يستخرج من كتاب «أسماك المياه الإقليمية للمملكة في البحر الأحمر» (مركز أبحاث الثروة السمكية بجدة، 2011)
صورة أو صورتين لكل نوع مع اسمه العلمي والإنجليزي وأسماءه المحلية، ويحفظها في أرشيف.

النص العربي في ملف الـ PDF مخربط (خط قديم بدون جدول حروف صحيح)، فنقرأ الأسماء المحلية بـ Claude من صورة الصفحة.
لكل صفحة فيها أسماء علمية: نرسم مربع مرقّم حول كل صورة مضمّنة، ونسأل Claude أي صور لأي نوع وإيش أسماءه المحلية.
بعدين نقص الصور من الصفحة الأصلية بدقة عالية (بدون المربعات).

docker run --rm --env-file server/.env -v $PWD/data/book:/b python:3.12-slim sh -c \
  "pip -q install pymupdf pillow anthropic && python /b/extract.py /b/redsea.pdf /b/archive [من_صفحة] [إلى_صفحة]"

الناتج: archive/index.json + archive/<رقم>_<Genus_species>/1.jpg ...
"""
import base64
import io
import json
import os
import re
import sys

import anthropic
import fitz
from PIL import Image, ImageDraw, ImageFont

PDF, OUT = sys.argv[1], sys.argv[2]
FIRST = int(sys.argv[3]) if len(sys.argv) > 3 else 1
LAST = int(sys.argv[4]) if len(sys.argv) > 4 else 9999
MODEL = os.environ.get("BOOK_MODEL", "claude-opus-5-5")

# الاسم العلمي في أول السطر وبعده المؤلف (بين قوسين أو بدون).
sci_re = re.compile(r"^\s*([A-Z][a-z]+ [a-z]{3,}(?: [a-z]{3,})?)\s*(?:\(|[A-Z])")
client = anthropic.Anthropic()
doc = fitz.open(PDF)
os.makedirs(OUT, exist_ok=True)
index_path = f"{OUT}/index.json"
index = json.load(open(index_path)) if os.path.exists(index_path) else {"pages": {}, "species": [], "usage": {"in": 0, "out": 0}}

PROMPT = """This is a page from the Saudi book "Fishes from territorial Saudi Red Sea waters" (Jeddah marine research centre, 2011).
Each species on the page has one or more photos, its scientific name and English name in Latin letters, and its local Arabic name(s) printed near its photo.
Some embedded images are outlined in red with a number. Numbers may also outline decorations, logos or parts of a larger photo.

Scientific names found in the page text: {names}

For EACH of these scientific names, return:
- "sci": the name exactly as listed above
- "english": the English common name printed under it ("" if none)
- "local": list of the local Arabic names printed for this species, exactly as printed in Arabic (several names are often separated by commas or on separate lines). [] if none.
- "images": list of the red numbers whose image shows THIS species (all parts of its photo). [] if none.
- "note": anything printed like "P.S : Farasan Islands" or a size, else "".

Reply with JSON only: {{"species": [ ... ]}}"""


def boxes(page):
    out = []
    for info in page.get_image_info(xrefs=True):
        r = fitz.Rect(info["bbox"]) & page.rect
        if r.width < 40 or r.height < 25:
            continue  # شعار الصفحة والزخارف الصغيرة
        out.append(r)
    return out


def render(page, clip=None, zoom=2.0):
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), clip=clip)
    return Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")


def jpeg(img, quality=88):
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    return buf.getvalue()


def ask(page, rects, names):
    img = render(page, zoom=2.0)
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default(size=34)
    for i, r in enumerate(rects, 1):
        x0, y0, x1, y1 = (v * 2 for v in r)
        d.rectangle([x0, y0, x1, y1], outline=(230, 0, 0), width=4)
        d.rectangle([x0, y0, x0 + 46, y0 + 40], fill=(230, 0, 0))
        d.text((x0 + 6, y0 + 2), str(i), fill=(255, 255, 255), font=font)
    msg = client.messages.create(
        model=MODEL,
        max_tokens=3000,
        messages=[{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.b64encode(jpeg(img, 82)).decode()}},
            {"type": "text", "text": PROMPT.format(names=json.dumps(names))},
        ]}],
    )
    index["usage"]["in"] += msg.usage.input_tokens
    index["usage"]["out"] += msg.usage.output_tokens
    text = "".join(b.text for b in msg.content if b.type == "text")
    m = re.search(r"\{.*\}", text, re.S)
    return json.loads(m.group(0))["species"] if m else []


def slug(s):
    return re.sub(r"[^A-Za-z]+", "_", s).strip("_")


for pno in range(FIRST, min(LAST, len(doc)) + 1):
    if str(pno) in index["pages"]:
        continue
    page = doc[pno - 1]
    names = []
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            m = sci_re.match("".join(s["text"] for s in l["spans"]))
            if m and m.group(1) not in names:
                names.append(m.group(1))
    if not names:
        index["pages"][str(pno)] = 0
        continue
    rects = boxes(page)
    try:
        found = ask(page, rects, names)
    except Exception as e:  # noqa: BLE001
        print(f"page {pno}: {e}", flush=True)
        continue
    for sp in found:
        nums = [n for n in sp.get("images", []) if isinstance(n, int) and 1 <= n <= len(rects)]
        if not nums:
            continue  # سطر مو اسم نوع (مقدمة الكتاب) أو نوع بدون صورة
        n = len(index["species"]) + 1
        folder = f"{n:03d}_{slug(sp.get('sci', 'unknown'))}"
        os.makedirs(f"{OUT}/{folder}", exist_ok=True)
        files = []
        # كل صورة مرقّمة لحالها، وإذا الصورة مقسومة قطع متلاصقة نجمعها في وحدة.
        groups = []
        for k in nums:
            r = rects[k - 1]
            for gi, g in enumerate(groups):
                if (g + fitz.Rect(-6, -6, 6, 6)).intersects(r):
                    groups[gi] = g | r
                    break
            else:
                groups.append(fitz.Rect(r))
        for gi, g in enumerate(groups[:3], 1):
            name = f"{gi}.jpg"
            open(f"{OUT}/{folder}/{name}", "wb").write(jpeg(render(page, clip=g, zoom=3.0), 90))
            files.append(name)
        entry = {
            "n": n, "page": pno, "folder": folder,
            "sci": sp.get("sci", ""), "english": sp.get("english", ""),
            "local": sp.get("local", []), "note": sp.get("note", ""), "files": files,
        }
        json.dump(entry, open(f"{OUT}/{folder}/meta.json", "w"), ensure_ascii=False, indent=1)
        index["species"].append(entry)
    index["pages"][str(pno)] = len(found)
    json.dump(index, open(index_path, "w"), ensure_ascii=False, indent=1)
    print(f"page {pno}: {len(found)} species, {sum(len(s.get('images', [])) for s in found)} images", flush=True)

u = index["usage"]
print(f"done: {len(index['species'])} species; tokens in {u['in']} out {u['out']}")
