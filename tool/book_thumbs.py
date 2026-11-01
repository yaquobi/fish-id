"""يصغّر أول صورة لكل نوع في أرشيف الكتاب إلى app.jpg (عرض 900 بكسل) عشان التطبيق يحمّلها بسرعة.

docker run --rm -v /opt/fish-id/data/book:/b python:3.12-slim sh -c "pip -q install pillow && python /b/thumbs.py /b/archive"
"""
import json
import sys

from PIL import Image

OUT = sys.argv[1]
index = json.load(open(f"{OUT}/index.json"))
total = 0
for s in index["species"]:
    if not s.get("files"):
        continue
    img = Image.open(f"{OUT}/{s['folder']}/{s['files'][0]}").convert("RGB")
    img.thumbnail((900, 900))
    path = f"{OUT}/{s['folder']}/app.jpg"
    img.save(path, "JPEG", quality=80, optimize=True, progressive=True)
    total += __import__("os").path.getsize(path)
print(f"{len(index['species'])} species, app.jpg total {total // 1024} KB")
