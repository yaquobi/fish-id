"""فحص: النص الأحمر في صفحة من الكتاب (الاسم المحلي) ومكانه، ومكان الصور."""
import sys

import fitz

doc = fitz.open(sys.argv[1])
for p in sys.argv[2:]:
    page = doc[int(p) - 1]
    print("page", p, "imgs", [[round(v) for v in i["bbox"]] for i in page.get_image_info() if i["bbox"][2] - i["bbox"][0] > 40])
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            for s in l["spans"]:
                c = s["color"]
                r, g, bl = c >> 16, (c >> 8) & 255, c & 255
                if r > 150 and g < 100 and bl < 100:
                    print("  red", [round(v) for v in s["bbox"]], hex(c), repr(s["text"][:30]))
    # الرسومات الحمراء (لو الاسم مرسوم كأشكال مو نص)
    reds = [d for d in page.get_drawings() if d.get("fill") and d["fill"][0] > .6 and d["fill"][1] < .4 and d["fill"][2] < .4]
    print("  red drawings", len(reds), [[round(v) for v in d["rect"]] for d in reds[:5]])
