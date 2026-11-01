"""يضيف الأسماء المحلية اللي وافق عليها محمد في صفحة المراجعة (1 نوفمبر 2026) للأسماك اللي ما لها اسم في الكتاب.
python3 book_review.py data/book/archive
"""
import json
import sys

APPROVED = {
    "Anodontostoma chacunda": ["عوفة"],
    "Carcharhinus falciformis": ["جرجور", "قرش"],
    "Carcharhinus sorrah": ["جرجور", "قرش"],
    "Cephalopholis sonnerati": ["عجوز", "هامور"],
    "Epinephelus bleekeri": ["هامور"],
    "Epinephelus epistictus": ["هامور"],
    "Epinephelus flavocaeruleus": ["هامور"],
    "Epinephelus malabaricus": ["هامور", "شهوة", "فرخ توينة"],
    "Epinephelus multinotatus": ["هامور", "بغل"],
    "Epinephelus polylepis": ["هامور"],
    "Epinephelus stoliczkae": ["هامور"],
    "Epinephelus undulosus": ["هامور"],
    "Escualosa thoracata": ["زيناب", "سردين"],
    "Etelis carbunculus": ["فارس"],
    "Gerres argyreus": ["بدح", "مصلخ", "ريشان"],
    "Loxodon macrorhinus": ["جرجور", "قرش"],
    "Lutjanus lunulatus": ["حمرة", "نيسر"],
    "Lutjanus lutjanus": ["نيسرة", "حبارة", "حمرة", "حبر أبو خط أصفر"],
    "Nemipterus peronii": ["بسي", "قزوان", "عندق", "همام"],
    "Nemipterus zysron": ["بسي", "قزوان", "عندق"],
    "Pomadasys kaakan": ["نقرور"],
    "Pomatomus saltatrix": ["غنبر", "تكوة"],
    "Sardinella albella": ["عومة", "سردين"],
    "Siganus spinus": ["صافي", "سيجي"],
    "Sparus aurata": ["دنيس"],
    "Sphyraena putnamae": ["عقام", "جد"],
    "Upeneus subvittatus": ["سلطان إبراهيم", "سبلان"],
}
OUT = sys.argv[1]
index = json.load(open(f"{OUT}/index.json"))
done = set()
for s in index["species"]:
    names = APPROVED.get(s["sci"].strip())
    if names and not s.get("local"):
        s["local"] = names
        s["local_src"] = "review_2026-11-01"
        json.dump(s, open(f"{OUT}/{s['folder']}/meta.json", "w"), ensure_ascii=False, indent=1)
        done.add(s["sci"])
json.dump(index, open(f"{OUT}/index.json", "w"), ensure_ascii=False, indent=1)
print(f"named {len(done)}/{len(APPROVED)}; missing {sorted(set(APPROVED) - done)}")
print(f"with names {sum(1 for s in index['species'] if s.get('local'))}/{len(index['species'])}")
