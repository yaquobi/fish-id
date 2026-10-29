#!/usr/bin/env bash
# يربط تنبيهات FISH ID ببوت تليجرام: اشتراكات جديدة، مساهمات بالصور، رفض Claude، وملخص يومي الساعة 9 مساءً.
# الاستخدام: cd /opt/fish-id && bash server/telegram.sh
# التوكن ما يطلع على الشاشة، وينحفظ في server/.env بصلاحية للمالك فقط.
set -euo pipefail
cd "$(dirname "$0")"

read -rsp 'الصق توكن البوت من BotFather: ' TOKEN; echo
NAME=$(curl -fsS "https://api.telegram.org/bot$TOKEN/getMe" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["username"])') || {
  echo 'التوكن غير صحيح.'; exit 1;
}
echo "البوت: @$NAME"

read -rp 'رقم محادثتك (chat id). اتركه فاضي وأرسل /start للبوت من جوالك ثم اضغط Enter: ' CHAT
if [[ -z $CHAT ]]; then
  # إذا البوت مربوط بـ webhook (مثل بوت الموسوعة) تليجرام يرفض getUpdates، فنطلب الرقم يدويًا.
  CHAT=$(curl -sS "https://api.telegram.org/bot$TOKEN/getUpdates?limit=20" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ids = [u["message"]["chat"]["id"] for u in d.get("result", []) if "message" in u]
print(ids[-1] if ids else "")') || CHAT=''
fi
if [[ -z $CHAT ]]; then
  echo 'ما لقيت رقم المحادثة. أرسل أي رسالة لـ @userinfobot في تليجرام، وانسخ الرقم اللي يرد فيه، وشغّل السكربت مرة ثانية.'
  exit 1
fi

umask 077
touch .env
sed -i '/^FISHID_TELEGRAM_TOKEN=/d;/^FISHID_TELEGRAM_CHAT=/d' .env
printf 'FISHID_TELEGRAM_TOKEN=%s\nFISHID_TELEGRAM_CHAT=%s\n' "$TOKEN" "$CHAT" >> .env
unset TOKEN

# الحاوية تقرأ .env وقت التشغيل، فنعيد تشغيلها. السيرفر يرسل «السيرفر اشتغل» أول ما يقوم.
docker compose up -d --force-recreate
echo 'تم. لازم توصلك رسالة «✅ FISH ID: السيرفر اشتغل» على تليجرام خلال ثواني.'
