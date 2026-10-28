#!/usr/bin/env bash
# قياس دقة FISH ID على السيرفر بنفس مفتاح Claude المحفوظ في server/.env.
#   bash server/eval.sh species        # صور iNaturalist لأهم 54 نوعًا في السوق (صورتين لكل نوع)
#   bash server/eval.sh fresh          # مجموعة FFE لطزاجة العين (تنزل تلقائيًا أول مرة)
# النتائج تنحفظ في eval-results/ وتنطبع على الشاشة.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-species}"; shift || true
mkdir -p eval-results data
compose=(docker compose -f server/docker-compose.yml)
"${compose[@]}" build -q

case "$mode" in
  species)
    "${compose[@]}" run --rm --no-deps -v "$PWD/eval-results:/out" fishid /app/fishid-eval species "$@"
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
  *) echo "الاستخدام: bash server/eval.sh species|fresh"; exit 2 ;;
esac
