"""يكمّل الأسماء المحلية الناقصة في أرشيف الكتاب: الاسم المحلي مطبوع بالأحمر على صورة السمكة نفسها،
فنعطي Claude الصورة المقصوصة ونطلب النص الأحمر بس.

docker run --rm --env-file server/.env -v /opt/fish-id/data/book:/b python:3.12-slim sh -c \
  "pip -q install anthropic pillow && python /b/names.py /b/archive [all]"
"""
import base64
import io
import json
import os
import re
import sys

import anthropic
from PIL import Image

OUT = sys.argv[1]
ALL = len(sys.argv) > 2 and sys.argv[2] == "all"
MODEL = os.environ.get("BOOK_MODEL", "claude-opus-5-5")
client = anthropic.Anthropic()
index_path = f"{OUT}/index.json"
index = json.load(open(index_path))
usage = index.setdefault("usage_names", {"in": 0, "out": 0})

PROMPT = """This photo is from a Saudi book of Red Sea fishes. The fish's local Arabic name(s) are printed in RED Arabic text on the photo (often in a corner, several names separated by "،" or ","). Ignore black text and numbers.
Reply with JSON only: {"local": ["name1", "name2"]} exactly as printed, or {"local": []} if there is no red Arabic text."""

done = 0
for s in index["species"]:
    if not s.get("files") or (s.get("local") and not ALL):
        continue
    img = Image.open(f"{OUT}/{s['folder']}/{s['files'][0]}").convert("RGB")
    img.thumbnail((1600, 1600))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    try:
        msg = client.messages.create(
            model=MODEL, max_tokens=300,
            messages=[{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.b64encode(buf.getvalue()).decode()}},
                {"type": "text", "text": PROMPT},
            ]}],
        )
    except Exception as e:  # noqa: BLE001
        print(s["folder"], e, flush=True)
        continue
    usage["in"] += msg.usage.input_tokens
    usage["out"] += msg.usage.output_tokens
    text = "".join(b.text for b in msg.content if b.type == "text")
    m = re.search(r"\{.*\}", text, re.S)
    names = [n.strip() for n in (json.loads(m.group(0)).get("local", []) if m else []) if isinstance(n, str) and n.strip()]
    if names:
        s["local"] = names
        s["local_src"] = "red_text"
        meta = f"{OUT}/{s['folder']}/meta.json"
        json.dump(s, open(meta, "w"), ensure_ascii=False, indent=1)
        done += 1
    print(s["folder"], names, flush=True)
    json.dump(index, open(index_path, "w"), ensure_ascii=False, indent=1)

print(f"filled {done}; with names {sum(1 for s in index['species'] if s.get('local'))}/{len(index['species'])}; tokens {usage}")
