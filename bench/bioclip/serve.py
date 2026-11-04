"""بصمة في الظل: خدمة صغيرة داخل شبكة Docker (ما تطلع للإنترنت).

POST /basma بجسم الصورة نفسها (jpeg أو png) يرجّع أقرب 5 أنواع من أسماء الـ447 نوعًا في الموسوعة:
  {"top": [{"id": "0365", "score": 0.31}, ...], "ms": 640}
GET /health يرجّع {"ok": true} لما النموذج يكون جاهز.

نفس طريقة "أسماء الأنواع" في run.py (BioCLIP 2.5، بدون تدريب)، اللي أعطت 66% على 306 صورة.
الخادم (server/lib/basma.dart) يرسل لها صورة كل فحص بعد ما يرجع جواب Opus، ويسجّل هل اتفقوا.
"""

import io
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import open_clip
import torch
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from run import load_species, prompt  # noqa: E402

MODEL = os.environ.get("BASMA_MODEL", "hf-hub:imageomics/bioclip-2.5-vith14")
MAX_BYTES = 12 * 1024 * 1024

torch.set_num_threads(int(os.environ.get("BASMA_THREADS", "4")))
species = load_species(os.environ.get("BASMA_SPECIES", "/app/data/ksafish.json"))
ids = [s["id"] for s in species]
print(f"تحميل {MODEL}…", flush=True)
model, _, preprocess = open_clip.create_model_and_transforms(MODEL)
model.eval()
with torch.no_grad():
    tf = model.encode_text(open_clip.get_tokenizer(MODEL)([prompt(s) for s in species]))
    text = tf / tf.norm(dim=-1, keepdim=True)
lock = threading.Lock()  # صورة وحدة في كل مرة، عشان ما ياخذ المعالج كله من الخادم
print(f"بصمة جاهزة: {len(ids)} نوعًا", flush=True)


@torch.no_grad()
def rank(data):
    img = Image.open(io.BytesIO(data)).convert("RGB")
    with lock:
        f = model.encode_image(preprocess(img).unsqueeze(0))
    f = f / f.norm(dim=-1, keepdim=True)
    probs = (100.0 * f @ text.T).softmax(dim=-1)[0]
    top = probs.topk(5)
    return [{"id": ids[i], "score": round(float(p), 4)} for p, i in zip(top.values, top.indices)]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        self._send(200 if self.path == "/health" else 404, {"ok": self.path == "/health"})

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        if self.path != "/basma" or not 0 < n <= MAX_BYTES:
            return self._send(400, {"error": "bad_request"})
        t0 = time.time()
        try:
            top = rank(self.rfile.read(n))
        except Exception as e:  # صورة تالفة مثلًا
            return self._send(400, {"error": str(e)[:200]})
        self._send(200, {"top": top, "ms": int((time.time() - t0) * 1000)})

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8090"))), Handler).serve_forever()
