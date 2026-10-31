"""يحدّث assets/data/ksafish.json من API موسوعة KSAFish العام (https://ksafish.com/api/v1).

- الأسماء المحلية: الموثّقة فقط (may_be_presented_as_name)، ونحدد البحر من نطاقها الجغرافي.
- الاسم العلمي والإنجليزي والعائلة والرقم الوطني والرابط من الموسوعة.
- اللوحات وأسماء العائلات بالعربي تبقى من الملف الحالي (الـ API ما يعطيها بنفس الشكل).
- الحقائق الحالية تبقى، وننضاف لها الحقائق المنشورة الجديدة اللي نعرف عنوانها بالعربي.

python3 tool/sync_ksafish.py            يكتب الملف ويطبع ملخص التغييرات
python3 tool/sync_ksafish.py --dry-run  يطبع الملخص بس
"""

import json
import sys
import time
import urllib.request

API = "https://ksafish.com/api/v1"
PATH = "assets/data/ksafish.json"

# نطاقات الموسوعة الجغرافية ← اسمها بالعربي كما في ملف التصدير.
SCOPES = {
    None: "",
    "GLOBAL": "عالمي",
    "SA": "المملكة العربية السعودية",
    "RED_SEA": "البحر الأحمر",
    "ARABIAN_GULF": "الخليج العربي",
    "SA_RED_SEA": "المياه الإقليمية السعودية — البحر الأحمر",
    "SA_ARABIAN_GULF": "المياه الإقليمية السعودية — الخليج العربي",
    "RED_SEA_AND_GULF": "البحر الأحمر والخليج العربي",
}
RED = {"SA_RED_SEA", "RED_SEA"}
GULF = {"SA_ARABIAN_GULF", "ARABIAN_GULF"}
BOTH = {"RED_SEA_AND_GULF", "SA"}


def get(path):
    for attempt in range(5):
        try:
            req = urllib.request.Request(API + path, headers={"Accept": "application/json", "Accept-Language": "ar", "User-Agent": "fish-id-sync"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            if attempt == 4:
                raise
            print(f"retry {path}: {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    return None


def text(v):
    if isinstance(v, dict):
        return str(v.get("label") or v.get("value") or v.get("code") or "")
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return "" if v is None else str(v)


def names(d, seas):
    out = []
    for n in d["names"]:
        if n["type"] != "local" or not n.get("may_be_presented_as_name") or n.get("superseded"):
            continue
        code = (n.get("geographic_scope") or {}).get("code")
        if code in seas or code in BOTH:
            out.append(n["value"].strip())
    return " | ".join(sorted(set(out)))


def main():
    dry = "--dry-run" in sys.argv
    old = json.load(open(PATH, encoding="utf-8"))
    by_id = {s["id"]: s for s in old["species"]}
    facts = old["facts"]

    codes, page = [], 1
    while True:
        r = get(f"/species?per_page=100&page={page}")
        codes += [s["huwat_code"] for s in r["data"]]
        if page >= r["meta"]["last_page"]:
            break
        page += 1
        time.sleep(0.6)

    details = {}
    for c in codes:
        details[c] = get(f"/species/{c}")["data"]
        time.sleep(0.55)

    # عنوان كل نوع حقيقة بالعربي: نتعلمه من الحقائق الحالية اللي لها نفس القيمة.
    ar_label, en_label = {}, {}
    for c, d in details.items():
        for f in d.get("facts", []):
            en_label[f["key"]] = f.get("label") or f["key"]
            v = text(f.get("value"))
            for lab, val, *_ in facts.get(c, []):
                if v and val == v:
                    ar_label.setdefault(f["key"], lab)

    species, changes, new_facts, unknown_keys = [], [], 0, {}
    for c in codes:
        d = details[c]
        o = by_id.get(c, {})
        fam = (d["taxonomy"].get("family") or {}).get("scientific_name") or o.get("fam", "")
        en = next((n["value"] for n in d["names"] if n["type"] == "english_common" and n.get("is_primary") and n.get("may_be_presented_as_name")), o.get("en", ""))
        nat = [i.get("value") for i in d.get("identifiers", []) if "national" in json.dumps(i.get("type"))]
        s = {
            "id": c,
            "sci": d["identity"]["scientific_name"],
            "fam": fam,
            "famAr": o.get("famAr", "") if o.get("fam") == fam else next((x["famAr"] for x in old["species"] if x["fam"] == fam and x["famAr"]), ""),
            "red": names(d, RED),
            "gulf": names(d, GULF),
            "en": en,
            "code": str(nat[0]) if nat else o.get("code", ""),
            "url": f"https://ksafish.com/ar/species/{d['identity']['slug']}",
            "plate": o.get("plate", ""),
        }
        if not o:
            changes.append(f"+ نوع جديد {c} {s['sci']}")
        else:
            for k in ("sci", "fam", "red", "gulf", "en", "code", "url"):
                if s[k] != o.get(k, ""):
                    changes.append(f"~ {c} {k}: {o.get(k, '')!r} → {s[k]!r}")
        species.append(s)

        have = {v for _, v, *_ in facts.get(c, [])}
        for f in d.get("facts", []):
            v = text(f.get("value"))
            if f.get("status") != "published" or not f.get("has_value") or not v or v in have:
                continue
            if f["key"] not in ar_label:
                unknown_keys[f["key"]] = unknown_keys.get(f["key"], 0) + 1
                continue
            unit = (f.get("unit") or {}).get("symbol") or ""
            scope = SCOPES.get((f.get("geographic_scope") or {}).get("code"), "")
            facts.setdefault(c, []).append([ar_label[f["key"]], v, unit, scope])
            new_facts += 1

    gone = [i for i in by_id if i not in details]
    for i in gone:
        changes.append(f"- {i} مو موجود في الموسوعة الحين (أبقيناه)")
        species.append(by_id[i])

    print(f"الأنواع في الموسوعة: {len(codes)}، في الملف القديم: {len(by_id)}")
    print(f"حقائق جديدة: {new_facts}")
    if unknown_keys:
        print("حقائق ما لها عنوان عربي معروف (ما انضافت):", {k: (en_label.get(k), n) for k, n in unknown_keys.items()})
    print(f"تغييرات ({len(changes)}):")
    for line in changes:
        print(" ", line)

    if not dry:
        with open(PATH, "w", encoding="utf-8") as f:
            json.dump({"species": species, "facts": facts}, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
