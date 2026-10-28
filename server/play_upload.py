#!/usr/bin/env python3
"""يرفع ملف AAB لمسار الاختبار الداخلي في Google Play عن طريق Play Developer API.

الاستخدام: python3 server/play_upload.py <ملف.aab> [ملاحظات بالعربي] [ملاحظات بالإنجليزي]
المفتاح: ملف حساب الخدمة في $FISHID_PLAY_KEY (الافتراضي /opt/fish-id-keys/play-service-account.json).
ما يحتاج مكتبات: يوقّع بـ openssl ويتصل بـ urllib.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

PACKAGE = os.environ.get('FISHID_PACKAGE', 'sa.hawat.fish_id')
TRACK = os.environ.get('FISHID_TRACK', 'internal')
KEY = os.environ.get('FISHID_PLAY_KEY', '/opt/fish-id-keys/play-service-account.json')
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'
UPLOAD = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}'


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token(sa: dict) -> str:
    now = int(time.time())
    head = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    body = b64(json.dumps({'iss': sa['client_email'], 'scope': 'https://www.googleapis.com/auth/androidpublisher',
                           'aud': sa['token_uri'], 'iat': now, 'exp': now + 3600}).encode())
    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        os.chmod(f.name, 0o600)
        f.write(sa['private_key'])
    try:
        sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', f.name], input=f'{head}.{body}'.encode(),
                             capture_output=True, check=True).stdout
    finally:
        os.unlink(f.name)
    form = f'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={head}.{body}.{b64(sig)}'
    return call('POST', sa['token_uri'], form.encode(), 'application/x-www-form-urlencoded', None)['access_token']


def call(method, url, data, ctype, tok):
    req = urllib.request.Request(url, data=data, method=method)
    if ctype:
        req.add_header('Content-Type', ctype)
    if tok:
        req.add_header('Authorization', f'Bearer {tok}')
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'{method} {url.split("?")[0]} -> {e.code}: {e.read().decode()[:600]}') from None


def release(tok, aab, status, notes):
    edit = call('POST', f'{API}/edits', b'{}', 'application/json', tok)['id']
    with open(aab, 'rb') as f:
        code = call('POST', f'{UPLOAD}/edits/{edit}/bundles?uploadType=media', f.read(), 'application/octet-stream', tok)['versionCode']
    rel = {'versionCodes': [str(code)], 'status': status}
    if notes:
        rel['releaseNotes'] = notes
    call('PUT', f'{API}/edits/{edit}/tracks/{TRACK}', json.dumps({'track': TRACK, 'releases': [rel]}).encode(), 'application/json', tok)
    call('POST', f'{API}/edits/{edit}:commit', None, None, tok)
    return code


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    aab = sys.argv[1]
    notes = [{'language': lang, 'text': text[:500]} for lang, text in (('ar', sys.argv[2] if len(sys.argv) > 2 else ''),
                                                                     ('en-US', sys.argv[3] if len(sys.argv) > 3 else '')) if text]
    with open(KEY) as f:
        sa = json.load(f)
    tok = token(sa)
    try:
        code = release(tok, aab, 'completed', notes)
        print(f'تم ✅ النسخة {code} منشورة في مسار {TRACK}')
    except RuntimeError as e:
        # التطبيق اللي ما انشر للعامة بعد يقبل إصدارات بحالة draft بس.
        if 'draft' not in str(e).lower():
            raise
        code = release(tok, aab, 'draft', notes)
        print(f'تم ✅ النسخة {code} مرفوعة كمسودة في مسار {TRACK}: اضغط Roll out في Play Console')


if __name__ == '__main__':
    try:
        main()
    except RuntimeError as e:
        sys.exit(f'فشل الرفع: {e}')
