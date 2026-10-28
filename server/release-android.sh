#!/usr/bin/env bash
# يبني نسخة Google Play ويرفعها للاختبار الداخلي مباشرة، بدون رفع يدوي.
# الاستخدام: cd /opt/fish-id && git pull && bash server/release-android.sh "ملاحظات بالعربي" "English notes"
# أول مرة: bash server/release-android.sh --setup   (يطلب لصق ملف JSON لحساب الخدمة، ويحفظه على السيرفر بس)
set -euo pipefail
cd "$(dirname "$0")/.."
KEYS=${FISHID_KEYS:-/opt/fish-id-keys}
export FISHID_PLAY_KEY=${FISHID_PLAY_KEY:-$KEYS/play-service-account.json}

if [[ ${1:-} == --setup || ! -f $FISHID_PLAY_KEY ]]; then
  mkdir -p "$KEYS" && chmod 700 "$KEYS"
  echo 'الصق محتوى ملف JSON لحساب الخدمة كامل، وبعدها اضغط Enter ثم Ctrl+D:'
  umask 077
  cat > "$FISHID_PLAY_KEY.tmp"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["type"]=="service_account"; print("حساب الخدمة:", d["client_email"])' "$FISHID_PLAY_KEY.tmp"
  mv "$FISHID_PLAY_KEY.tmp" "$FISHID_PLAY_KEY"
  [[ ${1:-} == --setup ]] && exit 0
fi

OUT=$(bash server/build-aab.sh | tee /dev/stderr | grep -o 'fish-id-[0-9]*\.aab' | tail -1)
python3 server/play_upload.py "landing/dl/$OUT" "${1:-}" "${2:-}"
# الملف العام ما نحتاجه بعد الرفع.
rm -f landing/dl/*.aab
