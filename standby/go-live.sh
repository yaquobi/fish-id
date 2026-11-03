#!/usr/bin/env bash
# الزر: يخلّي سيرفر جوجل هو الأساسي لـ hawat.id و ksafish.com.
# قبله: أوقف خدمة FISH ID على Hostinger (أو اقطعه) عشان ما يشتغل نسختين بنفس الحسابات.
set -euo pipefail
[[ "${1:-}" == "--yes" ]] || { echo "هذا يشغّل النسخة للناس. للتأكيد: sudo bash $0 --yes"; exit 1; }
source "$(dirname "$0")/lib.sh"
# آخر مزامنة قبل التشغيل (لو الأساسي واقف نكمل بآخر نسخة عندنا).
bash ./sync.sh || echo "تعذّرت آخر مزامنة، نكمل بنسخة $(cat $ST/last-sync 2>/dev/null)"
touch $ST/LIVE
ksfish_up
docker compose -f /opt/fish-id/server/docker-compose.yml up -d
# المنافذ 80/443: نوقف بوابة مركز الوكلاء القديم لو كانت ماسكتها (ملفاته وبياناته تبقى).
for c in $(docker ps --format '{{.Names}} {{.Ports}}' | awk '/0.0.0.0:443->/{print $1}'); do docker stop "$c"; done
docker compose --profile live up -d front
echo "شغّال. حوّل DNS: hawat.id و www و ksafish.com و www إلى $(curl -s -H 'Metadata-Flavor: Google' http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)"
echo "Caddy يطلع شهادات HTTPS أول ما يوصل الدومين."
