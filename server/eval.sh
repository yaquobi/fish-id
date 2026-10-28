#!/usr/bin/env bash
# قياس دقة FISH ID على السيرفر بنفس مفتاح Claude المحفوظ في server/.env.
#   bash server/eval.sh species        # صور iNaturalist لأهم 54 نوعًا في السوق (صورتين لكل نوع)
#   bash server/eval.sh fresh          # مجموعة FFE لطزاجة العين (تنزل تلقائيًا أول مرة)
#   bash server/eval.sh refs           # يبني مكتبة الصور المرجعية (data/refs) من iNaturalist، تستبعد صور الاختبار
#   bash server/eval.sh species --photos /out/species-….jsonl --refs /data/refs --refs-below 101
#                                       # نفس صور تجربة سابقة، مع المقارنة بالصور المرجعية
#   bash server/eval.sh bioclip --photos /out/species-….jsonl
#                                       # BioCLIP 2 على المعالج على نفس الصور (بدون Claude، بدون تكلفة)
# النتائج تنحفظ في eval-results/ وتنطبع على الشاشة.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-species}"; shift || true
mkdir -p eval-results data/refs
compose=(docker compose -f server/docker-compose.yml)
"${compose[@]}" build -q

case "$mode" in
  species)
    "${compose[@]}" run --rm --no-deps -v "$PWD/eval-results:/out" -v "$PWD/data/refs:/data/refs:ro" fishid /app/fishid-eval species "$@"
    ;;
  refs)
    "${compose[@]}" run --rm --no-deps -v "$PWD/eval-results:/out:ro" -v "$PWD/data/refs:/data/refs" fishid /app/fishid-eval refs "$@"
    ;;
  fresh)
    if [ ! -d data/ffe ]; then
      echo "تنزيل مجموعة FFE (Mendeley, CC BY 4.0)…"
      curl -fL -o data/ffe.zip "https://data.mendeley.com/public-api/zip/xzyx7pbr3w/download/1" || {
        echo "ما قدرنا ننزلها تلقائيًا. نزّلها من https://data.mendeley.com/datasets/xzyx7pbr3w وفكّها في $PWD/data/ffe"; exit 1; }
      (cd data && mkdir -p ffe && cd ffe && unzip -q ../ffe.zip && find . -name '*.zip' -exec unzip -q -o {} \; ) || true
    fi
    "${compose[@]}" run --rm --no-deps -v "$PWD/eval-results:/out" -v "$PWD/data/ffe:/data/ffe:ro" fishid /app/fishid-eval fresh --dir /data/ffe "$@"
    ;;
  bioclip)
    mkdir -p data/hf
    docker build -q -f bench/bioclip/Dockerfile -t fishid-bioclip . >/dev/null
    docker run --rm -v "$PWD/eval-results:/out" -v "$PWD/data/refs:/data/refs:ro" -v "$PWD/data/hf:/hf" fishid-bioclip "$@"
    ;;
  *) echo "الاستخدام: bash server/eval.sh species|fresh|refs|bioclip"; exit 2 ;;
esac
