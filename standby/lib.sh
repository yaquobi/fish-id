# مشترك بين test.sh و go-live.sh: يجهّز الموسوعة من آخر نسخة ويشغّلها على 127.0.0.1:18500.
ST=/opt/standby
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -f $ST/ksfish/db/ksfish.dump ]] || { echo "ما فيه نسخة. شغّل sync.sh أول."; exit 1; }
if [[ ! -f .env ]]; then umask 077; echo "KSFISH_DB_PASSWORD=$(openssl rand -hex 20)" > .env; umask 022; fi
ksfish_up() {
  rm -f $ST/ksfish/app/bootstrap/cache/config.php
  chmod -R a+rwX $ST/ksfish/app/storage $ST/ksfish/app/bootstrap/cache
  docker compose up -d --wait ksfish-db
  # نسترجع في قاعدة جديدة، وما نبدّلها بالقديمة إلا إذا نجح الاسترجاع.
  if docker compose exec -T ksfish-db sh -c 'dropdb -U ksfish --if-exists -f ksfish_new && createdb -U ksfish -T template0 ksfish_new && pg_restore -U ksfish -d ksfish_new --no-owner --no-acl --exit-on-error /dump/ksfish.dump'; then
    docker compose exec -T ksfish-db sh -c 'dropdb -U ksfish --if-exists -f ksfish && psql -U ksfish -d postgres -qc "alter database ksfish_new rename to ksfish"'
  else
    echo "تعذّر استرجاع قاعدة الموسوعة، بقيت النسخة السابقة"
  fi
  docker compose up -d ksfish-web
  for _ in $(seq 1 30); do curl -fsS -o /dev/null http://127.0.0.1:18500/ 2>/dev/null && break; sleep 2; done
  echo "الموسوعة: $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: ksafish.com' http://127.0.0.1:18500/ar)"
}
