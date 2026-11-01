"""ينظّف صور أرشيف الكتاب: يعيد رسم كل صورة من ملف الكتاب بدون أي نص فوقها
(الاسم المحلي بالأحمر، الطول، رقم الصفحة، الاسم العلمي)، ويقص الفراغ الأبيض حولها، ثم يسوي app.jpg من جديد.

الصور الأصلية مقصوصة من الصفحة بحدود صورة السمكة (tool/book_extract.py، تكبير 3)، فنلاقي حدودها
بمطابقة مقاس الملف مع صور الصفحة أو مجموعة صور متلاصقة. صور النسخة الممسوحة (source=scan2) ما نلمسها
لأن النص فيها جزء من الصورة.

docker run --rm -v /opt/fish-id/data/book:/b python:3.12-slim sh -c \
  "pip -q install pymupdf pillow && python /b/clean.py /b/redsea.pdf /b/archive"
"""
import io
import itertools
import json
import os
import sys

import fitz
from PIL import Image, ImageChops

ZOOM = 3.0
pdf = fitz.open(sys.argv[1])
OUT = sys.argv[2]
index = json.load(open(f"{OUT}/index.json"))


def candidates(page):
    rs = [fitz.Rect(i["bbox"]) & page.rect for i in page.get_image_info()]
    rs = [r for r in rs if r.width >= 40 and r.height >= 25]
    out = list(rs)
    for k in range(2, min(len(rs), 4) + 1):
        for combo in itertools.combinations(rs, k):
            u = fitz.Rect(combo[0])
            for r in combo[1:]:
                u |= r
            out.append(u)
    return out


def strip_text(page):
    for b in page.get_text("dict")["blocks"]:
        if b.get("type") == 0:
            page.add_redact_annot(fitz.Rect(b["bbox"]), fill=False)
    try:
        page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE, graphics=fitz.PDF_REDACT_LINE_ART_NONE)
    except (AttributeError, TypeError):
        page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)


def trim(img, pad=12):
    bg = Image.new("RGB", img.size, (255, 255, 255))
    diff = ImageChops.difference(img, bg).convert("L").point(lambda v: 255 if v > 24 else 0)
    box = diff.getbbox()
    if not box:
        return img
    x0, y0, x1, y1 = box
    return img.crop((max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad), min(img.height, y1 + pad)))


cleaned, missed, pages = 0, [], {}
for s in index["species"]:
    if s.get("source") == "scan2" or not s.get("files"):
        continue
    pno = s["page"]
    if pno not in pages:
        page = pdf[pno - 1]
        cands = candidates(page)
        strip_text(page)
        pages[pno] = (page, cands)
    page, cands = pages[pno]
    for name in s["files"]:
        path = f"{OUT}/{s['folder']}/{name}"
        if not os.path.exists(path):
            continue
        w, h = Image.open(path).size
        match = [r for r in cands if abs(r.width * ZOOM - w) <= 3 and abs(r.height * ZOOM - h) <= 3]
        if not match:
            missed.append(f"{s['folder']}/{name}")
            continue
        pix = page.get_pixmap(matrix=fitz.Matrix(ZOOM, ZOOM), clip=match[0])
        img = trim(Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB"))
        img.save(path, "JPEG", quality=90)
        cleaned += 1

total = 0
for s in index["species"]:
    if not s.get("files") or not os.path.exists(f"{OUT}/{s['folder']}/{s['files'][0]}"):
        continue
    img = Image.open(f"{OUT}/{s['folder']}/{s['files'][0]}").convert("RGB")
    img.thumbnail((900, 900))
    path = f"{OUT}/{s['folder']}/app.jpg"
    img.save(path, "JPEG", quality=80, optimize=True, progressive=True)
    total += os.path.getsize(path)

print(f"cleaned {cleaned}, not matched {len(missed)}, app.jpg total {total // 1024} KB")
for m in missed[:20]:
    print("  missed", m)
