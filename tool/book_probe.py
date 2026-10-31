"""فحص كتاب أسماك البحر الأحمر: كم صورة في كل صفحة وأحجامها، والأسماء العلمية ومواقعها."""
import json
import re
import sys

import fitz

doc = fitz.open(sys.argv[1])
sci = re.compile(r"^\s*([A-Z][a-z]+ [a-z]{3,}(?: [a-z]{3,})?)\s*\(")
out = []
for i, page in enumerate(doc):
    imgs = []
    for info in page.get_image_info(xrefs=True):
        x0, y0, x1, y1 = info["bbox"]
        imgs.append([round(x0), round(y0), round(x1), round(y1), info["width"], info["height"]])
    names = []
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"])
            m = sci.match(t)
            if m:
                names.append([m.group(1), [round(v) for v in l["bbox"]]])
    out.append({"p": i + 1, "imgs": imgs, "names": names})
print("pages", len(doc), "size", doc[100].rect)
for o in out[int(sys.argv[2]):int(sys.argv[3])]:
    print(json.dumps(o, ensure_ascii=False))
print("pages with names:", sum(1 for o in out if o["names"]), "names:", sum(len(o["names"]) for o in out), "imgs:", sum(len(o["imgs"]) for o in out))
