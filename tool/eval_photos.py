"""اختبار أكبر لبصمة: يجيب صور iNaturalist جديدة لأنواع eval/species.json بدون Claude وبدون تكلفة.

يكتب سجل بنفس صيغة species-….jsonl (expected, sci, photo, observation, dead) عشان
bench/bioclip/run.py يقيس عليه مباشرة. يستبعد كل ملاحظة موجودة في سجلات الاختبار السابقة
وفي مكتبة الصور المرجعية، ويفضّل الأسماك الميتة (أقرب لصور السوق).
الصور للقياس فقط، ما ندرّب عليها (شروط iNaturalist).

  python3 tool/eval_photos.py --per 6 --out eval-results/species-big.jsonl
"""

import argparse
import glob
import json
import time
import urllib.parse
import urllib.request

LICENSES = "cc0,cc-by,cc-by-nc,cc-by-sa,cc-by-nc-sa,cc-by-nd,cc-by-nc-nd"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "FISH-ID-eval/1.0 (hawat.id)"})
    return json.loads(urllib.request.urlopen(req, timeout=40).read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", default="server/eval/species.json")
    ap.add_argument("--per", type=int, default=6)
    ap.add_argument("--out", required=True)
    ap.add_argument("--exclude", default="eval-results/species-*.jsonl")
    args = ap.parse_args()

    seen = set()
    for f in glob.glob(args.exclude):
        for line in open(f, encoding="utf-8"):
            if line.strip():
                seen.add(json.loads(line).get("observation"))
    try:
        seen.update(m.get("observation") for m in json.load(open("data/refs/manifest.json")))
    except Exception:
        pass
    print(f"مستبعد: {len(seen)} ملاحظة", flush=True)

    species = json.load(open(args.list, encoding="utf-8"))
    total = 0
    with open(args.out, "w", encoding="utf-8") as out:
        for i, s in enumerate(species, 1):
            found = []
            for dead in (True, False):
                page = 1
                while len(found) < args.per and page <= 3:
                    q = {"taxon_name": s["sci"], "quality_grade": "research", "photos": "true",
                         "photo_license": LICENSES, "order_by": "votes", "per_page": "50", "page": str(page)}
                    if dead:
                        q.update({"term_id": "17", "term_value_id": "19"})
                    try:
                        j = get("https://api.inaturalist.org/v1/observations?" + urllib.parse.urlencode(q))
                    except Exception as e:
                        print(f"\n{s['sci']}: {e}", flush=True)
                        break
                    time.sleep(1.1)
                    for o in j.get("results", []):
                        if len(found) >= args.per:
                            break
                        if (o.get("taxon") or {}).get("name", "").lower() != s["sci"].lower():
                            continue
                        obs = f"https://www.inaturalist.org/observations/{o['id']}"
                        if obs in seen or not o.get("photos"):
                            continue
                        seen.add(obs)
                        url = o["photos"][0]["url"].replace("/square.", "/large.")
                        found.append({"expected": s["id"], "sci": s["sci"], "photo": url,
                                      "observation": obs, "dead": dead})
                    if len(j.get("results", [])) < 50:
                        break
                    page += 1
                if len(found) >= args.per:
                    break
            for c in found:
                out.write(json.dumps(c) + "\n")
            total += len(found)
            print(f"\r{i}/{len(species)} نوعًا، {total} صورة", end="", flush=True)
    print(f"\nخلص: {args.out}")


if __name__ == "__main__":
    main()
