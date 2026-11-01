"""فحص: يرسل صفحة من الكتاب لـ Claude ويطبع رده على سؤال حر. python book_ask.py pdf page "question"."""
import base64
import io
import os
import sys

import anthropic
import fitz
from PIL import Image

doc = fitz.open(sys.argv[1])
page = doc[int(sys.argv[2]) - 1]
pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
img = Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")
img.save(f"/b/page{sys.argv[2]}.jpg", "JPEG", quality=80)
buf = io.BytesIO()
img.save(buf, "JPEG", quality=85)
msg = anthropic.Anthropic().messages.create(
    model=os.environ.get("BOOK_MODEL", "claude-opus-5-5"), max_tokens=800,
    messages=[{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.b64encode(buf.getvalue()).decode()}},
        {"type": "text", "text": sys.argv[3]},
    ]}],
)
print("".join(b.text for b in msg.content if b.type == "text"))
