import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'claude.dart';

/// أرقام الإعلانات لكل يوم (بتوقيت السعودية) ولكل منصة: الصرف والظهور والضغطات.
///
/// الأرقام حقيقية من المنصات نفسها: الخادم يسحب ميتا وسناب وإكس كل ساعة بمفاتيحها ([AdKeys])،
/// وقوقل يرسلها سكربت داخل حساب Google Ads على `ads/push` بمفتاح الدفع.
/// الملف `ads.json` في مجلد الحسابات: {يوم: {منصة: {spend, currency, spendSar, impressions, clicks, reach, at, src}}}.
class AdStore {
  AdStore._(this.dir, this._days, this.keys);

  final String dir;
  final Map<String, Map<String, dynamic>> _days;
  final AdKeys keys;

  static const platforms = ['meta', 'snapchat', 'x', 'google', 'tiktok'];
  static const names = {'meta': 'ميتا (فيسبوك وإنستغرام)', 'snapchat': 'سناب شات', 'x': 'إكس', 'google': 'قوقل', 'tiktok': 'تيك توك'};
  static final dayPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$');

  static AdStore open(String dir) {
    final f = File('$dir/ads.json');
    final m = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) : <String, Map<String, dynamic>>{};
    return AdStore._(dir, m, AdKeys.open(dir));
  }

  /// يحفظ أرقام [platform] ليوم [day]. المنصة ترجّع مجموع اليوم كامل، فالسطر الجديد يحل محل القديم.
  Future<Map<String, dynamic>> put(String day, String platform, Map b, {required double usdToSar, required String src, required DateTime now}) async {
    if (!dayPattern.hasMatch(day) || !platforms.contains(platform)) throw const FishIdError('bad_request', 'اليوم أو المنصة غير صحيحة');
    num n(String k) {
      final v = b[k];
      final x = v is num ? v : num.tryParse('${v ?? ''}');
      if (x == null || x < 0 || x > 1e9) return 0;
      return x;
    }

    final currency = '${b['currency'] ?? 'SAR'}'.toUpperCase() == 'USD' || b['usd'] == 1 ? 'USD' : 'SAR';
    final spend = n('spend');
    final row = {
      'spend': _r(spend),
      'currency': currency,
      'spendSar': _r(currency == 'USD' ? spend * usdToSar : spend),
      'impressions': n('impressions').round(),
      'clicks': n('clicks').round(),
      if (b['reach'] != null) 'reach': n('reach').round(),
      'at': now.toUtc().toIso8601String(),
      'src': src,
    };
    _days.putIfAbsent(day, () => {})[platform] = row;
    await _save();
    return row;
  }

  static double _r(num v) => double.parse(v.toStringAsFixed(2));

  Map<String, Map<String, dynamic>> day(String day) => {for (final e in (_days[day] ?? const {}).entries) e.key: (e.value as Map).cast<String, dynamic>()};

  /// مجموع أيام [from] إلى [to] لكل منصة، ومجموع الكل.
  Map<String, dynamic> total(String from, String to) {
    final per = <String, Map<String, num>>{};
    for (final e in _days.entries) {
      if (e.key.compareTo(from) < 0 || e.key.compareTo(to) > 0) continue;
      e.value.forEach((p, row) {
        final t = per.putIfAbsent(p, () => {'spendSar': 0, 'impressions': 0, 'clicks': 0});
        for (final k in t.keys.toList()) {
          t[k] = t[k]! + ((row as Map)[k] as num? ?? 0);
        }
      });
    }
    num sum(String k) => per.values.fold<num>(0, (t, r) => t + r[k]!);
    return {
      'platforms': {
        for (final e in per.entries) e.key: {...e.value, 'spendSar': _r(e.value['spendSar']!)},
      },
      'spendSar': _r(sum('spendSar')),
      'impressions': sum('impressions'),
      'clicks': sum('clicks'),
    };
  }

  /// صرف كل منصة في شهر [m] (YYYY-MM) بالريال، للمحاسبة.
  Map<String, double> monthSpend(String m) {
    final out = <String, double>{};
    for (final e in _days.entries.where((e) => e.key.startsWith(m))) {
      e.value.forEach((p, row) => out[p] = (out[p] ?? 0) + (((row as Map)['spendSar'] as num?) ?? 0));
    }
    return out.map((k, v) => MapEntry(k, _r(v)));
  }

  Future<void> _queue = Future.value();

  Future<void> _save() {
    final text = jsonEncode(_days);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/ads.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/ads.json');
    });
  }

  /// يسحب أرقام [day] من كل منصة مربوطة ويحفظها. يرجّع الأخطاء لكل منصة (فاضي إذا كله تمام).
  Future<Map<String, String>> pull(String day, {required double usdToSar, required DateTime now, HttpClient? client}) async {
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));
    final errors = <String, String>{};
    final jobs = <String, Future<Map<String, num>?> Function()>{
      if (keys.has('meta')) 'meta': () => _meta(http, day),
      if (keys.has('snapchat')) 'snapchat': () => _snap(http, day),
      if (keys.has('x')) 'x': () => _x(http, day),
    };
    for (final j in jobs.entries) {
      try {
        final row = await j.value().timeout(const Duration(seconds: 60));
        if (row != null) await put(day, j.key, row, usdToSar: usdToSar, src: 'api', now: now);
        keys.status[j.key] = {'ok': true, 'at': now.toUtc().toIso8601String()};
      } on Object catch (e) {
        final msg = '$e'.replaceAll(RegExp(r'access_token=[^&\s]+'), 'access_token=…');
        errors[j.key] = msg.substring(0, min(msg.length, 300));
        keys.status[j.key] = {'ok': false, 'at': now.toUtc().toIso8601String(), 'error': errors[j.key]};
      }
    }
    if (client == null) http.close();
    return errors;
  }

  static Future<Map<String, dynamic>> _get(HttpClient http, Uri url, {Map<String, String> headers = const {}}) async {
    final req = await http.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('${url.host} ${res.statusCode}: ${body.substring(0, min(body.length, 400))}');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// بداية ونهاية يوم السعودية [day] (منتصف الليل لمنتصف الليل، +03:00).
  static (String, String) _ksaDay(String day) {
    final p = day.split('-').map(int.parse).toList();
    final next = DateTime.utc(p[0], p[1], p[2] + 1).toIso8601String().substring(0, 10);
    return ('${day}T00:00:00+03:00', '${next}T00:00:00+03:00');
  }

  /// ميتا: إحصائية اليوم من حساب الإعلانات (بتوقيت الحساب). العملة عملة الحساب.
  Future<Map<String, num>?> _meta(HttpClient http, String day) async {
    final k = keys.get('meta');
    final act = '${k['account']}'.replaceFirst('act_', '');
    final r = await _get(
      http,
      Uri.https('graph.facebook.com', '/v21.0/act_$act/insights', {
        'fields': 'spend,impressions,inline_link_clicks,reach,account_currency',
        'time_range': jsonEncode({'since': day, 'until': day}),
        'access_token': '${k['token']}',
      }),
    );
    final d = (r['data'] as List?) ?? const [];
    if (d.isEmpty) return {'spend': 0, 'impressions': 0, 'clicks': 0};
    final x = d.first as Map;
    num v(String f) => num.tryParse('${x[f] ?? 0}') ?? 0;
    return {'spend': v('spend'), 'impressions': v('impressions'), 'clicks': v('inline_link_clicks'), 'reach': v('reach'), if (x['account_currency'] == 'USD') 'usd': 1};
  }

  /// سناب: بالساعة من منتصف ليل السعودية لمنتصف الليل اللي بعده، فاليوم يطابق يومنا بالضبط.
  Future<Map<String, num>?> _snap(HttpClient http, String day) async {
    final k = keys.get('snapchat');
    // التوكن يعيش ساعة: نجدده من refresh token.
    final req = await http.postUrl(Uri.https('accounts.snapchat.com', '/login/oauth2/access_token'));
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write(Uri(queryParameters: {'grant_type': 'refresh_token', 'client_id': '${k['client']}', 'client_secret': '${k['secret']}', 'refresh_token': '${k['refresh']}'}).query);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('snap token ${res.statusCode}');
    final tok = jsonDecode(body) as Map;
    if (tok['refresh_token'] is String && tok['refresh_token'] != k['refresh']) await keys.set('snapchat', {...k, 'refresh': tok['refresh_token']});
    final (start, end) = _ksaDay(day);
    final auth = {'authorization': 'Bearer ${tok['access_token']}'};
    // إحصائية حساب الإعلانات في سناب ترجع الصرف بس، فنجمع الظهور والضغطات من كل حملة.
    final list = await _get(http, Uri.https('adsapi.snapchat.com', '/v1/adaccounts/${k['account']}/campaigns'), headers: auth);
    num spend = 0, imp = 0, clicks = 0;
    for (final c in (list['campaigns'] as List? ?? const [])) {
      final id = ((c as Map)['campaign'] as Map?)?['id'];
      if (id == null) continue;
      final r = await _get(
        http,
        Uri.https('adsapi.snapchat.com', '/v1/campaigns/$id/stats', {'granularity': 'HOUR', 'fields': 'impressions,swipes,spend', 'start_time': start, 'end_time': end}),
        headers: auth,
      );
      for (final s in (r['timeseries_stats'] as List? ?? const [])) {
        for (final t in ((s as Map)['timeseries_stat']?['timeseries'] as List? ?? const [])) {
          final st = ((t as Map)['stats'] as Map?) ?? const {};
          spend += (st['spend'] as num?) ?? 0;
          imp += (st['impressions'] as num?) ?? 0;
          clicks += (st['swipes'] as num?) ?? 0;
        }
      }
    }
    return {'spend': spend / 1e6, 'impressions': imp, 'clicks': clicks};
  }

  /// إكس: بالساعة ليوم السعودية، والصرف بالدولار (micro). التوقيع OAuth 1.0a.
  Future<Map<String, num>?> _x(HttpClient http, String day) async {
    final k = keys.get('x');
    final (start, end) = _ksaDay(day);
    String iso(String t) => DateTime.parse(t).toUtc().toIso8601String().replaceFirst('.000', '');
    final params = {'entity': 'ACCOUNT', 'entity_ids': '${k['account']}', 'start_time': iso(start), 'end_time': iso(end), 'granularity': 'HOUR', 'metric_groups': 'ENGAGEMENT,BILLING', 'placement': 'ALL_ON_TWITTER'};
    final url = Uri.https('ads-api.x.com', '/12/stats/accounts/${k['account']}', params);
    final r = await _get(http, url, headers: {'authorization': oauth1('GET', url, k)});
    num sum(Map m, String f) => ((m[f] as List?) ?? const []).fold<num>(0, (t, v) => t + ((v as num?) ?? 0));
    num spend = 0, imp = 0, clicks = 0;
    for (final d in (r['data'] as List? ?? const [])) {
      for (final id in ((d as Map)['id_data'] as List? ?? const [])) {
        final m = ((id as Map)['metrics'] as Map?) ?? const {};
        spend += sum(m, 'billed_charge_local_micro');
        imp += sum(m, 'impressions');
        clicks += sum(m, 'url_clicks');
      }
    }
    return {'spend': spend / 1e6, 'impressions': imp, 'clicks': clicks, 'usd': 1};
  }

  /// ترويسة OAuth 1.0a (HMAC-SHA1) لطلب [method] على [url] بمفاتيح التطبيق والمستخدم في [k].
  static String oauth1(String method, Uri url, Map k, {String? nonce, int? timestamp}) {
    String enc(String s) => Uri.encodeComponent(s).replaceAll('!', '%21').replaceAll("'", '%27').replaceAll('(', '%28').replaceAll(')', '%29').replaceAll('*', '%2A');
    final o = {
      'oauth_consumer_key': '${k['consumerKey']}',
      'oauth_nonce': nonce ?? List.generate(32, (_) => Random.secure().nextInt(36).toRadixString(36)).join(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': '${timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'oauth_token': '${k['token']}',
      'oauth_version': '1.0',
    };
    final all = {...url.queryParameters, ...o}.entries.map((e) => '${enc(e.key)}=${enc(e.value)}').toList()..sort();
    final base = '${method.toUpperCase()}&${enc('${url.scheme}://${url.host}${url.path}')}&${enc(all.join('&'))}';
    final key = '${enc('${k['consumerSecret']}')}&${enc('${k['tokenSecret']}')}';
    o['oauth_signature'] = base64.encode(Hmac(sha1, utf8.encode(key)).convert(utf8.encode(base)).bytes);
    return 'OAuth ${o.entries.map((e) => '${enc(e.key)}="${enc(e.value)}"').join(', ')}';
  }
}

/// مفاتيح ربط المنصات، ينحفظ في `ad_keys.json` بصلاحية للمالك بس، وما يرجع للمتصفح أبد (بس هل هو مربوط وآخر سحب).
/// مفتاح الدفع ([pushKey]) يستخدمه سكربت Google Ads عشان يرسل أرقام قوقل.
class AdKeys {
  AdKeys._(this.dir, this._keys);

  final String dir;
  final Map<String, dynamic> _keys;

  /// نتيجة آخر سحب لكل منصة (في الذاكرة).
  final status = <String, Map<String, dynamic>>{};

  /// الحقول المطلوبة لكل منصة.
  static const fields = {
    'meta': ['account', 'token'],
    'snapchat': ['account', 'client', 'secret', 'refresh'],
    'x': ['account', 'consumerKey', 'consumerSecret', 'token', 'tokenSecret'],
  };

  static AdKeys open(String dir) {
    final f = File('$dir/ad_keys.json');
    return AdKeys._(dir, f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>() : {});
  }

  bool has(String p) => _keys[p] is Map && (fields[p] ?? const []).every((f) => '${(_keys[p] as Map)[f] ?? ''}'.isNotEmpty);

  Map get(String p) => (_keys[p] as Map?) ?? const {};

  Future<void> set(String p, Map v) async {
    if (!fields.containsKey(p)) throw const FishIdError('bad_request', 'المنصة غير معروفة');
    // خانة فاضية تبقي القيمة المحفوظة، عشان تقدر تغيّر رقم الحساب بدون ما تعيد لصق المفاتيح.
    final old = get(p);
    _keys[p] = {
      for (final f in fields[p]!) f: '${v[f] ?? ''}'.trim().isEmpty ? '${old[f] ?? ''}' : '${v[f]}'.trim(),
    };
    await _save();
  }

  Future<void> remove(String p) async {
    _keys.remove(p);
    status.remove(p);
    await _save();
  }

  /// ربط سناب: رابط موافقة Snap (OAuth) يرجع لـ [redirect] بكود نبدله بـ refresh token.
  String? _snapState;

  String snapAuthUrl(String redirect) {
    final k = get('snapchat');
    if ('${k['client'] ?? ''}'.isEmpty) throw const FishIdError('bad_request', 'احفظ Client ID و Client secret أول');
    final rnd = Random.secure();
    _snapState = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return Uri.https('accounts.snapchat.com', '/login/oauth2/authorize', {
      'client_id': '${k['client']}',
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': 'snapchat-marketing-api',
      'state': _snapState,
    }).toString();
  }

  /// يبدّل كود الموافقة بـ refresh token ويحفظه. state لازم يطابق آخر رابط طلعناه.
  Future<void> snapCallback(String code, String state, String redirect, HttpClient http) async {
    if (_snapState == null || state != _snapState) throw const FishIdError('bad_request', 'الرابط قديم، ارجع للوحة واضغط «ربط سناب» من جديد');
    _snapState = null;
    final k = get('snapchat');
    final req = await http.postUrl(Uri.https('accounts.snapchat.com', '/login/oauth2/access_token'));
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write(Uri(queryParameters: {'grant_type': 'authorization_code', 'client_id': '${k['client']}', 'client_secret': '${k['secret']}', 'code': code, 'redirect_uri': redirect}).query);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      // نعرض سبب سناب (مثل invalid_client أو redirect_uri) بدون أي مفتاح.
      var why = '';
      try {
        final e = jsonDecode(body) as Map;
        why = [e['error'], e['error_description']].whereType<String>().join(': ');
      } on Object {
        why = '';
      }
      throw FishIdError('bad_request', 'سناب رفض الكود (${res.statusCode}${why.isEmpty ? '' : ' - $why'})');
    }
    final tok = jsonDecode(body) as Map;
    if (tok['refresh_token'] is! String) throw const FishIdError('bad_request', 'سناب ما أرسل مفتاح دائم، تأكد من صلاحية snapchat-marketing-api');
    await set('snapchat', {...k, 'refresh': tok['refresh_token']});
  }

  /// مفتاح الدفع لسكربت قوقل، يتولد أول مرة.
  Future<String> pushKey() async {
    if (_keys['push'] case final String k) return k;
    final rnd = Random.secure();
    final k = 'ap_${List.generate(24, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    _keys['push'] = k;
    await _save();
    return k;
  }

  bool pushMatches(String k) {
    final p = _keys['push'];
    if (p is! String || k.length != p.length) return false;
    var d = 0;
    for (var i = 0; i < p.length; i++) {
      d |= p.codeUnitAt(i) ^ k.codeUnitAt(i);
    }
    return d == 0;
  }

  /// أول مرة يوصل فيها دفع من سكربت المنصة [p]: نعتبرها مربوطة.
  Future<void> seen(String p, DateTime now) async {
    if (_keys['seen_$p'] is String) return;
    _keys['seen_$p'] = now.toUtc().toIso8601String();
    await _save();
  }

  /// للوحة: وش مربوط وآخر نتيجة، بدون أي مفتاح.
  Map<String, dynamic> view() => {
    for (final p in AdStore.platforms) p: {'linked': p == 'google' ? _keys['seen_google'] is String : has(p), ...?status[p]},
  };

  Future<void> _save() async {
    final f = File('$dir/ad_keys.json.tmp');
    await f.writeAsString(jsonEncode(_keys), flush: true);
    await f.rename('$dir/ad_keys.json');
  }
}
