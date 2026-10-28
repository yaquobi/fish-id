"""قياس BioCLIP 2 على نفس صور اختبار FISH ID، ومقارنته بـ Claude بعدل.

يقيس ثلاث طرق، كلها بدون تدريب (zero-shot):
  text:   صورة السمكة مقابل أسماء الـ447 نوعًا في الموسوعة.
  refs:   أقرب جار في مكتبة الصور المرجعية (data/refs).
  mix:    مجموع الاثنين.
وطريقة هجينة: من مرشحي Claude الثلاثة في سجل التجربة، يختار اللي يعطيه BioCLIP أعلى درجة.

التشغيل على السيرفر: bash server/eval.sh bioclip
"""

import argparse
import hashlib
import io
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

import open_clip
import torch
from PIL import Image


def load_species(path):
    data = json.load(open(path, encoding="utf-8"))
    out = []
    for s in data["species"]:
        sid = s["id"].split("-")[-1]
        out.append({"id": sid, "sci": s.get("sci", ""), "en": s.get("en", ""), "fam": s.get("fam", "")})
    return out


def prompt(s):
    # BioCLIP تدرب على نصوص مختلطة: الاسم العلمي والاسم الشائع والتصنيف. نستخدم الثلاثة.
    fam = s["fam"].capitalize()
    common = f" with common name {s['en']}" if s["en"] else ""
    return f"a photo of Actinopterygii {fam} {s['sci']}{common}."


def fetch(url, cache):
    cache.mkdir(parents=True, exist_ok=True)
    f = cache / (hashlib.sha1(url.encode()).hexdigest() + ".jpg")
    if not f.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "FISH-ID-bench/1.0 (hawat.id)"})
        f.write_bytes(urllib.request.urlopen(req, timeout=30).read())
        time.sleep(0.3)
    return Image.open(io.BytesIO(f.read_bytes())).convert("RGB")


@torch.no_grad()
def embed_images(model, preprocess, images, batch=16):
    feats = []
    for i in range(0, len(images), batch):
        x = torch.stack([preprocess(im) for im in images[i : i + batch]])
        f = model.encode_image(x)
        feats.append(f / f.norm(dim=-1, keepdim=True))
    return torch.cat(feats) if feats else torch.empty(0)


def pct(a, n):
    return f"{100 * a / n:.1f}% ({a} من {n})" if n else "—"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", required=True, help="سجل تجربة سابقة (species-….jsonl)")
    ap.add_argument("--species", default="/app/data/ksafish.json")
    ap.add_argument("--refs", default="/data/refs")
    ap.add_argument("--model", default="hf-hub:imageomics/bioclip-2")
    ap.add_argument("--pretrained", default=None, help="للتجربة المحلية بنموذج غير مدرّب")
    ap.add_argument("--cache", default="/out/cache")
    ap.add_argument("--out", default="/out")
    args = ap.parse_args()

    torch.set_num_threads(os.cpu_count() or 4)
    species = load_species(args.species)
    ids = [s["id"] for s in species]
    fam = {s["id"]: s["fam"] for s in species}
    print(f"تحميل {args.model}…", flush=True)
    t0 = time.time()
    model, _, preprocess = open_clip.create_model_and_transforms(args.model, pretrained=args.pretrained)
    tokenizer = open_clip.get_tokenizer(args.model)
    model.eval()
    print(f"انحمل في {time.time() - t0:.0f} ث", flush=True)

    with torch.no_grad():
        tf = model.encode_text(tokenizer([prompt(s) for s in species]))
        text_feats = tf / tf.norm(dim=-1, keepdim=True)

    # مكتبة الصور المرجعية: لكل نوع، أعلى تشابه بين الصورة وأي صورة مرجعية له.
    ref_ids, ref_imgs = [], []
    refs = Path(args.refs)
    if refs.exists():
        for d in sorted(p for p in refs.iterdir() if p.is_dir()):
            for f in sorted(d.glob("*.jpg")):
                try:
                    ref_imgs.append(Image.open(f).convert("RGB"))
                    ref_ids.append(d.name)
                except Exception:
                    pass
    print(f"صور مرجعية: {len(ref_imgs)}", flush=True)
    t0 = time.time()
    ref_feats = embed_images(model, preprocess, ref_imgs)
    if len(ref_imgs):
        print(f"تضمين المكتبة: {time.time() - t0:.0f} ث", flush=True)

    cases = [json.loads(l) for l in open(args.photos, encoding="utf-8") if l.strip()]
    cases = [c for c in cases if not c.get("error")]
    stats = {k: {"top1": 0, "top3": 0, "fam": 0} for k in ["text", "refs", "mix", "claude", "claude+bioclip"]}
    n = 0
    times = []
    log = open(Path(args.out) / f"bioclip-{time.strftime('%Y-%m-%dT%H%M', time.gmtime())}.jsonl", "w", encoding="utf-8")
    for c in cases:
        try:
            img = fetch(c["photo"], Path(args.cache))
        except Exception as e:
            print(f"\n{c['photo']}: {e}", file=sys.stderr)
            continue
        t0 = time.time()
        q = embed_images(model, preprocess, [img])[0]
        text_s = (q @ text_feats.T).tolist()
        refs_s = {}
        if len(ref_imgs):
            for rid, s in zip(ref_ids, (q @ ref_feats.T).tolist()):
                refs_s[rid] = max(refs_s.get(rid, -1.0), s)
        times.append(time.time() - t0)
        scores = {
            "text": dict(zip(ids, text_s)),
            "refs": {i: refs_s.get(i, -1.0) for i in ids},
        }
        scores["mix"] = {i: scores["text"][i] + (scores["refs"][i] if scores["refs"][i] > -1 else min(text_s)) for i in ids}
        ranked = {k: sorted(ids, key=lambda i: -v[i]) for k, v in scores.items()}
        claude = [str(x["id"]).zfill(4) for x in ((c.get("result") or {}).get("candidates") or [])]
        ranked["claude"] = claude
        # هجين: من مرشحي Claude الثلاثة، الأعلى عند BioCLIP (نص + صور).
        ranked["claude+bioclip"] = sorted(claude[:3], key=lambda i: -scores["mix"].get(i, -9)) + claude[3:]
        exp = c["expected"]
        n += 1
        for k, r in ranked.items():
            if not r:
                continue
            stats[k]["top1"] += r[0] == exp
            stats[k]["top3"] += exp in r[:3]
            stats[k]["fam"] += fam.get(r[0]) == fam.get(exp)
        log.write(json.dumps({"expected": exp, "photo": c["photo"], **{k: r[:5] for k, r in ranked.items()}}) + "\n")
        print(f"\r{n}/{len(cases)}", end="", flush=True)

    names = {
        "claude": "Claude (من السجل)",
        "text": "BioCLIP 2: أسماء الأنواع",
        "refs": "BioCLIP 2: الصور المرجعية",
        "mix": "BioCLIP 2: الاثنين",
        "claude+bioclip": "هجين: Claude يرشح و BioCLIP يختار",
    }
    print(f"\n\n## BioCLIP 2 على نفس الصور ({n} صورة)\n")
    print("| الطريقة | top-1 | top-3 | العائلة |\n|---|---|---|---|")
    for k in ["claude", "text", "refs", "mix", "claude+bioclip"]:
        st = stats[k]
        if k == "refs" and not len(ref_imgs):
            continue
        print(f"| {names[k]} | {pct(st['top1'], n)} | {pct(st['top3'], n)} | {pct(st['fam'], n)} |")
    if times:
        times.sort()
        print(f"\nزمن BioCLIP لكل صورة على المعالج: الوسيط {times[len(times) // 2]:.2f} ث")
    print(f"التفاصيل: {log.name}")


if __name__ == "__main__":
    main()
