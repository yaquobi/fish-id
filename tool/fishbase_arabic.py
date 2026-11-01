"""يجيب الأسماء العربية لكل نوع من FishBase (صفحة الأسماء الشائعة) مع الدولة اللي يستخدم فيها.
python3 fishbase_arabic.py "Genus species" ... > out.json
"""
import html
import json
import re
import sys
import time
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (FISH ID research)"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read().decode("utf-8", "replace")


out = {}
for sci in sys.argv[1:]:
    g, s = sci.split()[:2]
    try:
        page = get(f"https://www.fishbase.se/summary/{g}-{s}.html")
        m = re.search(r"CommonNamesList\.php\?ID=(\d+)", page)
        if not m:
            out[sci] = {"error": "no id"}
            continue
        names = get(f"https://www.fishbase.se/ComNames/CommonNamesList.php?ID={m.group(1)}&GenusName={g}&SpeciesName={s}&StockCode=1")
        rows = []
        m2 = re.search(r"var table_data_arr = (\{.*?\});\s*\n", names, re.S)
        for r in (json.loads(m2.group(1)).get("table_filter", []) if m2 else []):
            if len(r) >= 3 and "Arabic" in str(r[2]):
                rows.append({"name": html.unescape(re.sub(r"<[^>]+>", "", r[0])).strip(), "country": r[1]})
        out[sci] = {"id": m.group(1), "arabic": rows}
    except Exception as e:  # noqa: BLE001
        out[sci] = {"error": str(e)}
    time.sleep(1)
print(json.dumps(out, ensure_ascii=False, indent=1))
