#!/usr/bin/env bash
# يبني نسخة Google Play (AAB) على السيرفر وتوقّع بمفتاح الرفع. المفتاح وكلمة سره في /opt/fish-id-keys وما يطلعون من السيرفر.
# الاستخدام: cd /opt/fish-id && bash server/build-aab.sh
# الناتج: https://hawat.id/dl/fish-id-<رقم>.aab (للرفع في Play Console).
set -euo pipefail
cd "$(dirname "$0")/.."
KEYS=${FISHID_KEYS:-/opt/fish-id-keys}
IMAGE=${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:3.47.8}

# 1. مفتاح الرفع: ينشأ مرة وحدة بكلمة سر عشوائية. لو ضاع، Google يقدر يغيّره (Play App Signing يحفظ مفتاح التطبيق الأصلي).
mkdir -p "$KEYS" && chmod 700 "$KEYS"
if [[ ! -f $KEYS/upload.jks ]]; then
  PASS=$(openssl rand -hex 16)
  docker run --rm -v "$KEYS":/keys eclipse-temurin:17-jdk keytool -genkeypair -keystore /keys/upload.jks \
    -storepass "$PASS" -keypass "$PASS" -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=HUWAT FISH ID, O=HUWAT, C=SA" >/dev/null
  printf 'storeFile=/keys/upload.jks\nstorePassword=%s\nkeyAlias=upload\nkeyPassword=%s\n' "$PASS" "$PASS" > "$KEYS/key.properties"
  chmod 600 "$KEYS"/*
  echo "مفتاح رفع جديد في $KEYS"
fi

# 2. البناء داخل حاوية Flutter. رقم النسخة من التاريخ والساعة، فكل نسخة أكبر من اللي قبلها.
BUILD=${BUILD:-$(date -u +%y%m%d%H)}
docker pull -q "$IMAGE" >/dev/null || IMAGE=ghcr.io/cirruslabs/flutter:stable
docker run --rm -v "$PWD":/app -v "$KEYS":/keys -v fishid-pub-cache:/root/.pub-cache -v fishid-gradle:/root/.gradle \
  -e FISHID_UPLOAD_KEY=/keys/key.properties -w /app "$IMAGE" \
  bash -c "git config --global --add safe.directory /app && flutter pub get && flutter build appbundle --release --build-number=$BUILD"

# 3. ننسخها لمجلد التحميل في صفحة الهبوط.
mkdir -p landing/dl
cp build/app/outputs/bundle/release/app-release.aab "landing/dl/fish-id-$BUILD.aab"
echo "تم ✅ https://hawat.id/dl/fish-id-$BUILD.aab"
