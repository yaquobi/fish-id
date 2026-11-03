#!/usr/bin/env bash
# يجرّب النسخة الاحتياطية على منافذ داخلية بس، بدون ما تخدم أحد، وبعدين يطفيها.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ksfish_up
# FISH ID بإعدادات تجربة: بدون مفتاح Claude وبدون تليجرام، وعلى نسخة مؤقتة من البيانات، عشان ما يرسل شي ولا يجدد اشتراك.
T=$(mktemp -d); cp -a /opt/fish-id/data/accounts $T/accounts
docker run -d --rm --name fishid-test -p 127.0.0.1:18491:8080 -e FISHID_ADMIN_TOKEN=test -v $T/accounts:/app/accounts -v /opt/fish-id/data/book/archive:/app/book:ro server-fishid >/dev/null
sleep 3; echo "FISH ID: $(curl -s http://127.0.0.1:18491/health)"
docker stop fishid-test >/dev/null; rm -rf $T
docker compose stop ksfish-web ksfish-db >/dev/null
echo "انطفت. النسخة الاحتياطية سليمة."
