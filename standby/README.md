# النسخة الاحتياطية الجاهزة (Google Cloud)

السيرفر الأساسي: Hostinger (187.7.25.218) يخدم hawat.id و ksafish.com.
النسخة الاحتياطية: سيرفر Google Cloud `hawat-app-staging` (34.42.119.112)، **واقفة** وتتحدث كل ساعة.

| الأمر (على سيرفر جوجل) | وش يسوي |
|---|---|
| `sudo bash /opt/fish-id/standby/sync.sh` | يسحب آخر كود من GitHub، وينسخ من Hostinger: إعدادات FISH ID وبياناته، ونسخة الموسوعة الحالية مع قاعدة بياناتها. يشتغل تلقائياً كل ساعة. |
| `sudo bash /opt/fish-id/standby/go-live.sh` | الزر: يوقف المزامنة، يشغّل FISH ID والموسوعة، ويفتح الموقع على 80/443. بعده يتحوّل الدومين (hawat.id و ksafish.com) لعنوان جوجل. |
| `sudo bash /opt/fish-id/standby/test.sh` | يتأكد إن النسخة تقوم وتجاوب على منافذ داخلية، بدون ما تخدم أحد وبدون تنبيهات، وبعدين يطفيها. |

ملاحظات:
- عنوان سيرفر جوجل ثابت: 34.42.119.112 (hawat-standby-ip). المزامنة كل ساعة (`systemctl list-timers standby-sync.timer`).
- قبل go-live: افتح المنافذ 80/443 في جوجل (`gcloud compute firewall-rules create hawat-web --network=hawat-network --allow=tcp:80,tcp:443,udp:443 --target-tags=hawat-server`)، لأن الجدار الناري الحالي يسمح بـ SSH عبر IAP بس.
- الدخول للسيرفر من Cloud Shell: `gcloud compute ssh hawat-app-staging --zone=us-central1-a --tunnel-through-iap`.
- السيرفر الأساسي ما يتغير فيه شي. مفتاح المزامنة على Hostinger مقيّد بعنوان جوجل (`from="34.42.119.112"` في `/root/.ssh/authorized_keys`، سطر gcp-standby).
- حاوية FISH ID فيها مهام دورية (البريف اليومي، تنبيهات تليجرام، تجديد الاشتراكات)، فما تنشغل بمفتاحها الحقيقي إلا بعد go-live، لا تشغّلها والأساسي شغّال.
- الموسوعة على جوجل: الإصدار الحالي (`/var/www/ksfish/current`) + نسخة `pg_dump` لقاعدة `ksfish`، تنشغل في حاويات (php 8.4 + nginx، و postgres 17). نسخ التجارب (ws-*، ksfish_restore_*) ما تنتسخ. ai.ksafish.com و review و ks5 ما هي ضمن النسخة.
- `/opt/standby/LIVE` يعني النسخة صارت هي الأساسية، والمزامنة توقف عشان ما تمسح بيانات جديدة.
