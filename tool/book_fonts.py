"""فحص خطوط الكتاب: هل أسماء الحروف (glyph names) في الخط العربي تكفي لفك النص المخربط؟"""
import io
import sys

import fitz
from fontTools.ttLib import TTFont

doc = fitz.open(sys.argv[1])
page = doc[int(sys.argv[2]) - 1]
seen = set()
for f in page.get_fonts(full=True):
    xref, ext, typ, base, name, enc = f[:6]
    if xref in seen:
        continue
    seen.add(xref)
    print("font", xref, ext, typ, base, enc)
    try:
        nm, ext2, _, buf = doc.extract_font(xref)
        if not buf:
            continue
        tt = TTFont(io.BytesIO(buf))
        order = tt.getGlyphOrder()
        print("  glyphs", len(order), order[:40])
    except Exception as e:  # noqa: BLE001
        print("  err", e)
# النص العربي مع الخط لكل مقطع
for b in page.get_text("rawdict")["blocks"]:
    for l in b.get("lines", []):
        for s in l["spans"]:
            t = "".join(c["c"] for c in s["chars"])
            if any("؀" <= ch <= "ۿ" for ch in t):
                print(s["font"], repr(t), [hex(ord(c)) for c in t][:12])
