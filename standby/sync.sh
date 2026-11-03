#!/usr/bin/env bash
# يحدّث النسخة الاحتياطية على Google Cloud من السيرفر الأساسي (Hostinger). ما يكتب شي على الأساسي.
set -euo pipefail
PRIMARY=${PRIMARY:-root@187.7.25.218}
KEY=/root/.ssh/standby
ST=/opt/standby
SSH=(ssh -i $KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
RS=(rsync -a --delete -e "${SSH[*]}")
mkdir -p $ST/ksfish/app $ST/ksfish/db
chmod 700 $ST/ksfish
[[ -f $ST/LIVE ]] && { echo "النسخة شغّالة كأساسية (LIVE)، المزامنة موقوفة."; exit 0; }
exec 9>$ST/sync.lock; flock -n 9 || { echo "مزامنة ثانية شغّالة"; exit 0; }

# 1. الكود من GitHub.
# على main إذا فيه هذي السكربتات (قبل الدمج نبقى على الفرع اللي فيه).
G=(git -C /opt/fish-id)
"${G[@]}" fetch -q origin
if "${G[@]}" cat-file -e origin/main:standby/sync.sh 2>/dev/null; then "${G[@]}" checkout -q -B main origin/main; else "${G[@]}" pull -q --ff-only || true; fi
# 2. FISH ID: الإعدادات (فيها المفتاح، تبقى root فقط) والبيانات. ذاكرة النماذج (data/hf) ما نحتاجها.
"${RS[@]}" $PRIMARY:/opt/fish-id/server/.env /opt/fish-id/server/.env
chmod 600 /opt/fish-id/server/.env
for d in accounts contrib book refs; do
  mkdir -p /opt/fish-id/data/$d
  "${RS[@]}" $PRIMARY:/opt/fish-id/data/$d/ /opt/fish-id/data/$d/
done
# 3. الموسوعة: الإصدار الحالي كامل (الكود، vendor، .env، storage) وقاعدة البيانات.
"${RS[@]}" --chown=33:33 --chmod=D755,F644 --exclude 'storage/logs/*' --exclude 'storage/framework/cache/*' --exclude 'storage/framework/sessions/*' --exclude 'storage/framework/views/*' \
  $PRIMARY:/var/www/ksfish/current/ $ST/ksfish/app/
"${SSH[@]}" $PRIMARY "sudo -u postgres pg_dump -Fc ksfish" > $ST/ksfish/db/ksfish.dump.tmp
mv $ST/ksfish/db/ksfish.dump.tmp $ST/ksfish/db/ksfish.dump
# 4. نبني حاوية FISH ID على آخر كود (بدون تشغيل).
docker compose -f /opt/fish-id/server/docker-compose.yml build -q
date -u +%FT%TZ > $ST/last-sync
echo "تمت المزامنة $(cat $ST/last-sync)"
