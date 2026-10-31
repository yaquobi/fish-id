"""قياس نموذج Qwen مفتوح (يشتغل على سيرفرنا بـ llama.cpp) على نفس صور اختبار FISH ID، ومقارنته بـ Claude.

يقرأ صور الاختبار من سجل تجربة سابقة (species-….jsonl)، ويطلب من النموذج يختار النوع من قائمة الموسوعة نفسها،
ويحسب: الأول صح، ضمن أول 3، العائلة صح، ومتوسط الوقت لكل صورة.

قائمة الأنواع في رسالة النظام (ثابتة)، عشان llama.cpp يحفظها ويعالج الصورة بس في كل طلب.

التشغيل على السيرفر:
  python3 bench/qwen/run.py --photos eval-results/species-….jsonl [--limit 10] [--think]
  Gemini: --api https://generativelanguage.googleapis.com/v1beta/openai/chat/completions --model gemini-… (المفتاح في GEMINI_API_KEY)
"""

import argparse
import base64
import io
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def species_list(path):
    data = json.load(open(path, encoding="utf-8"))
    lines, fam = [], {}
    for s in data["species"]:
        sid = s["id"].split("-")[-1]
        fam[sid] = s.get("fam", "")
        names = " | ".join(n for n in (s.get("red", ""), s.get("gulf", "")) if n)
        lines.append("|".join([sid, s.get("sci", ""), s.get("en", ""), names]))
    return "\n".join(lines), fam


SYSTEM = """You are a fish identification expert for Saudi Arabian waters (Red Sea and Arabian Gulf).
You receive a photo of a fish. Identify the species ONLY from the KSAFish list below (format: id|scientific name|English name|Saudi local names).
Work like a taxonomist: family and genus from body shape, mouth, fins and tail, then compare the species of that genus on visible marks.
Answer with JSON only: {"candidates":[{"id":"0086","confidence":70},...]} with 1 to 3 candidates, best first, ids from the list.

KSAFish list:
"""


def fetch_image(url, cache):
    cache.mkdir(parents=True, exist_ok=True)
    import hashlib

    f = cache / (hashlib.sha1(url.encode()).hexdigest() + ".jpg")
    if not f.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "FISH-ID-bench/1.0 (hawat.id)"})
        f.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    from PIL import Image

    im = Image.open(io.BytesIO(f.read_bytes())).convert("RGB")
    im.thumbnail((768, 768))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=85)
    return base64.b64encode(buf.getvalue()).decode()


def ask(api, system, b64, think, model="", key=""):
    body = {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                {"type": "text", "text": "Which species is this? JSON only."},
            ]},
        ],
        "temperature": 0,
        "max_tokens": 4096 if think or model else 300,
    }
    headers = {"Content-Type": "application/json"}
    if model:
        # خدمة سحابية متوافقة مع OpenAI (مثل Gemini): نحدد النموذج والمفتاح.
        body["model"] = model
        headers["Authorization"] = f"Bearer {key}"
    else:
        # llama.cpp على سيرفرنا: نحفظ قائمة الأنواع، ونطفي التفكير إلا إذا طلبناه.
        body["cache_prompt"] = True
        body["chat_template_kwargs"] = {"enable_thinking": think}
    req = urllib.request.Request(api, data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    text = out["choices"][0]["message"].get("content") or ""
    m = re.search(r"\{.*\}", text, re.S)
    ids = []
    if m:
        try:
            ids = [str(c["id"]).zfill(4)[-4:] for c in json.loads(m.group(0)).get("candidates", [])]
        except (ValueError, KeyError, TypeError):
            pass
    return ids, text, out.get("timings", {})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", required=True)
    ap.add_argument("--species", default=str(ROOT / "assets/data/ksafish.json"))
    ap.add_argument("--api", default="http://127.0.0.1:18500/v1/chat/completions")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--think", action="store_true")
    ap.add_argument("--model", default="", help="اسم النموذج في خدمة سحابية، مثل gemini-…")
    ap.add_argument("--key-env", default="GEMINI_API_KEY", help="متغير البيئة اللي فيه مفتاح الخدمة")
    ap.add_argument("--out", default=str(ROOT / "eval-results"))
    a = ap.parse_args()

    listing, fam = species_list(a.species)
    system = SYSTEM + listing
    cases = [json.loads(l) for l in open(a.photos, encoding="utf-8") if l.strip()]
    if a.limit:
        cases = cases[: a.limit]
    stamp = time.strftime("%Y%m%d-%H%M")
    name = a.model or f"qwen-{'think' if a.think else 'fast'}"
    key = os.environ.get(a.key_env, "") if a.model else ""
    log = open(Path(a.out) / f"{name}-{stamp}.jsonl", "w", encoding="utf-8")
    top1 = top3 = famok = n = 0
    secs = []
    for i, c in enumerate(cases, 1):
        exp = str(c["expected"]).split("-")[-1]
        try:
            b64 = fetch_image(c["photo"], ROOT / "data/hf/photos")
        except Exception as e:  # noqa: BLE001
            print(f"[{i}] skip photo: {e}", file=sys.stderr)
            continue
        t = time.time()
        try:
            ids, text, timings = ask(a.api, system, b64, a.think, a.model, key)
        except Exception as e:  # noqa: BLE001
            ids, text, timings = [], f"error: {e}", {}
        dt = time.time() - t
        n += 1
        secs.append(dt)
        top1 += bool(ids) and ids[0] == exp
        top3 += exp in ids[:3]
        famok += bool(ids) and fam.get(ids[0]) == fam.get(exp)
        log.write(json.dumps({"expected": exp, "sci": c.get("sci"), "ids": ids, "s": round(dt, 1), "text": text[-400:], "timings": timings}, ensure_ascii=False) + "\n")
        log.flush()
        print(f"[{i}/{len(cases)}] {c.get('sci')}: {ids} {'✓' if ids[:1] == [exp] else ''} {dt:.1f}s", flush=True)
    if n:
        secs.sort()
        print(f"\n{name}: {n} صورة | الأول صح {100*top1/n:.0f}% | ضمن 3 {100*top3/n:.0f}% | العائلة {100*famok/n:.0f}% | الوقت الوسيط {secs[len(secs)//2]:.1f}ث")


if __name__ == "__main__":
    main()
