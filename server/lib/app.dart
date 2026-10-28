import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_page.dart';
import 'claude.dart';
import 'contrib.dart';

typedef Identify = Future<String> Function(List<Photo> photos);

/// يجيب بيانات المشترك من RevenueCat (GET /v1/subscribers/{id})، و null إذا تعذّر الاتصال.
typedef SubscriberLookup = Future<Map<String, dynamic>?> Function(String user);

/// مسارات الخادم. نفس بروتوكول Serverpod اللي يكلمه التطبيق:
/// POST fishId/identify بجسم `{"image": "decode('BASE64', 'base64')", "mediaType": "image/jpeg"}`،
/// أو `{"images": [{"image": ..., "mediaType": ...}, ...]}` حتى [maxPhotos] صور لنفس السمكة.
/// والرد نص JSON داخل سلسلة JSON. الخطأ 4xx/5xx بجسم {"code", "message"}.
/// POST fishId/contribute: نفس الصور مع النوع المؤكد والأيام وطريقة الحفظ وموافقة المستخدم، وتنحفظ في [contrib].
///
/// التطبيق يرسل رقم حسابه في `x-fishid-user` ولغته في `x-fishid-lang` (ar أو en)، والرد فيه `x-fishid-remaining` (الفحوصات المتبقية).
/// GET fishId/me يرجّع الباقة والمتبقي. إذا خلصت الفحوصات يرجع 402 بالرمز quota.
/// POST fishId/redeem بجسم {"code"} يضيف فحوصات رمز الهدية ويرجّع المتبقي.
/// POST fishId/sync يتأكد من اشتراك الحساب في RevenueCat بعد الشراء ويرجّع المتبقي.
/// admin/... لوحة الأدمن ([adminToken])، و revenuecat يستقبل أحداث الاشتراك. الحدث مجرد تنبيه: الخادم ما يصدّق
/// محتواه، ويسأل RevenueCat ([revenueCat]) عن الاشتراك الحقيقي، فما نحتاج سر مشترك.
class FishIdApp {
  FishIdApp({
    required this.identify,
    this.contrib,
    this.accounts,
    this.adminToken = '',
    this.revenueCat,
    this.speciesNames = const {},
    this.perMinute = 30,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Identify? identify;
  final ContribStore? contrib;
  final AccountStore? accounts;
  final String adminToken;
  final SubscriberLookup? revenueCat;

  /// رقم حوات (4 أرقام) والاسم المحلي، للوحة الأدمن.
  final Map<String, String> speciesNames;
  final int perMinute;
  final DateTime Function() _clock;

  static const maxBytes = 5 * 1024 * 1024;
  static const maxPhotos = 3;
  static const types = {'image/jpeg', 'image/png', 'image/webp'};
  static const _cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'POST, GET, OPTIONS',
    'access-control-allow-headers': 'content-type, x-fishid-user, x-fishid-lang',
    'access-control-expose-headers': 'x-fishid-remaining',
  };

  int _minute = 0;
  int _count = 0;

  Handler get handler => (Request req) async {
    if (req.method == 'OPTIONS') return Response.ok(null, headers: _cors);
    // يقبل المسار مع /api/ أو بدونها، حسب إعداد البروكسي.
    final path = req.url.path.replaceFirst(RegExp(r'^api/'), '');
    if (req.method == 'GET' && (path == '' || path == 'health')) {
      return _json(200, {'ok': true, 'service': 'fish-id', 'ready': identify != null});
    }
    if (req.method == 'POST' && path == 'fishId/identify') {
      try {
        final user = _user(req);
        final result = await _identify(req, user);
        return _json(200, result, headers: _remaining(user));
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'GET' && path == 'fishId/me') {
      try {
        final user = _user(req);
        final store = accounts;
        if (user == null || store == null) return _json(200, {'plan': 'free', 'remaining': null});
        final v = store.view(user, _clock());
        return _json(200, {'plan': v['active'] == true ? v['plan'] : 'free', 'until': v['until'], 'remaining': v['remaining']});
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'fishId/redeem') {
      try {
        final user = _user(req);
        final store = accounts;
        if (user == null || store == null) throw const FishIdError('bad_code', 'الرمز غير صحيح');
        _limit();
        final String code;
        try {
          code = '${(jsonDecode(await req.readAsString()) as Map)['code']}';
        } on Object {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        final v = await store.redeem(user, code, _clock());
        return _json(200, {'remaining': v['remaining']}, headers: _remaining(user));
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'fishId/sync') {
      try {
        final user = _user(req);
        if (user == null || accounts == null || revenueCat == null) return _json(200, {'remaining': null});
        _limit();
        await _syncSubscription(user);
        return _json(200, {'remaining': accounts!.remaining(user, _clock())}, headers: _remaining(user));
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (path == 'admin' || path.startsWith('admin/')) {
      try {
        return await _admin(req, path);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'revenuecat') {
      try {
        return await _revenueCat(req);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'fishId/contribute') {
      try {
        return _json(200, {'ok': true, 'id': await _contribute(req)});
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    return _json(404, {'code': 'not_found', 'message': 'المسار غير موجود'});
  };

  /// رقم الحساب من الطلب. بدون رقم نسمح (للتطبيقات القديمة) إلا إذا الإعداد requireAccount مفعّل.
  String? _user(Request req) {
    final id = req.headers['x-fishid-user'];
    if (id == null || id.isEmpty) {
      if (accounts?.requireAccount == true) throw const FishIdError('update_app', 'حدّث التطبيق من المتجر عشان تكمل الفحص', status: 426);
      return null;
    }
    if (!AccountStore.idPattern.hasMatch(id)) throw const FishIdError('bad_request', 'الطلب غير صالح');
    return id;
  }

  Map<String, String> _remaining(String? user) {
    final store = accounts;
    if (user == null || store == null) return const {};
    return {'x-fishid-remaining': '${store.remaining(user, _clock())}'};
  }

  Future<String> _identify(Request req, String? user) async {
    final run = identify;
    if (run == null) throw const FishIdError('fishid_off', 'خدمة التعرف على الأسماك غير مفعّلة حاليًا', status: 503);
    final (photos, _) = await _readPhotos(req);
    final store = accounts;
    if (user != null) store?.check(user, _clock());
    _limit();
    final usage = <Map<String, dynamic>>[];
    final watch = Stopwatch()..start();
    // كل استدعاء لـ Claude داخل الفحص يضيف استهلاكه لـ usage (claude.dart)، فنعرف تكلفة الفحص كاملة.
    final lang = req.headers['x-fishid-lang'] == 'en' ? 'en' : 'ar';
    final result = await runZoned(() => run(photos), zoneValues: {usageKey: usage, langKey: lang});
    await store?.record(user, _clock(), result: result, usd: usageCost(usage), ms: watch.elapsedMilliseconds, photos: photos.length);
    return result;
  }

  int _adminMinute = 0;
  int _adminFails = 0;

  Future<Response> _admin(Request req, String path) async {
    if (adminToken.isEmpty) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    if (req.method == 'GET' && path == 'admin') {
      return Response.ok(adminPage, headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY'});
    }
    final now = _clock();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (minute != _adminMinute) {
      _adminMinute = minute;
      _adminFails = 0;
    }
    if (_adminFails >= 10) throw const FishIdError('busy', 'محاولات كثيرة، حاول بعد دقيقة', status: 429);
    if (!_same(req.headers['authorization'] ?? '', 'Bearer $adminToken')) {
      _adminFails++;
      throw const FishIdError('unauthorized', 'الرمز غير صحيح', status: 401);
    }
    final store = accounts;
    final parts = path.split('/');
    final q = req.url.queryParameters;
    Future<Map<String, dynamic>> body() async {
      try {
        return jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      } on Object {
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      }
    }

    switch ((req.method, parts.length > 1 ? parts[1] : '')) {
      case ('GET', 'species'):
        return _json(200, speciesNames);
      case ('GET', 'stats') when store != null:
        return _json(200, store.stats(now));
      case ('GET', 'users') when store != null:
        return _json(200, store.users(now, q: q['q'] ?? ''));
      case ('POST', 'users') when store != null && parts.length == 3 && AccountStore.idPattern.hasMatch(parts[2]):
        final b = await body();
        final days = (b['days'] as num?)?.toInt();
        return _json(
          200,
          await store.update(
            parts[2],
            now,
            grant: (b['grant'] as num?)?.toInt(),
            plan: b['plan'] as String?,
            until: days == null ? null : now.add(Duration(days: days)),
            blocked: b['blocked'] as bool?,
          ),
        );
      case ('GET', 'scans') when store != null:
        return _json(200, store.scans(now, months: 2).take(300).toList());
      case ('GET', 'settings') when store != null:
        return _json(200, store.settings);
      case ('POST', 'settings') when store != null:
        await store.saveSettings(await body());
        return _json(200, store.settings);
      case ('GET', 'codes') when store != null:
        return _json(200, store.codes());
      case ('POST', 'codes') when store != null:
        final b = await body();
        await store.saveCode('${b['code']}', scans: (b['scans'] as num?)?.toInt() ?? 0, max: (b['max'] as num?)?.toInt() ?? 0);
        return _json(200, store.codes());
      case ('GET', 'contrib') when contrib != null && parts.length == 2:
        return _json(200, contrib!.latest(status: q['status'] ?? ''));
      case ('GET', 'contrib') when contrib != null && parts.length == 5:
        final f = contrib!.file(parts[2], parts[3], parts[4]);
        if (f == null) break;
        return Response.ok(
          await f.readAsBytes(),
          headers: {'content-type': f.path.endsWith('png') ? 'image/png' : 'image/jpeg', 'cache-control': 'private, max-age=3600'},
        );
      case ('POST', 'contrib') when contrib != null && parts.length == 4:
        final b = await body();
        final m = await contrib!.review(parts[2], parts[3], status: '${b['status']}', species: b['species'] as String?);
        if (m == null) break;
        return _json(200, m);
    }
    throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
  }

  /// أحداث RevenueCat (اشتراك جديد، تجديد، إلغاء، استرجاع). نقرأ منها أرقام الحسابات بس، ونتأكد من كل حساب عند RevenueCat.
  Future<Response> _revenueCat(Request req) async {
    if (revenueCat == null || accounts == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    final Map event;
    try {
      event = (jsonDecode(await req.readAsString()) as Map)['event'] as Map;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    final users = {
      for (final k in const ['app_user_id', 'original_app_user_id']) '${event[k]}',
      for (final k in const ['aliases', 'transferred_from', 'transferred_to'])
        if (event[k] is List) for (final id in event[k] as List) '$id',
    }.where(AccountStore.idPattern.hasMatch).take(5);
    for (final user in users) {
      await _syncSubscription(user);
    }
    return _json(200, {'ok': true});
  }

  /// ياخذ أبعد تاريخ انتهاء من صلاحيات المشترك الفعّالة في RevenueCat ويحطه على الحساب.
  /// إذا ما عنده صلاحية فعّالة (انتهى أو استرجع فلوسه) والباقة جت من المتجر، يرجع مجاني.
  /// الباقات اللي يعطيها الأدمن ما تتأثر.
  Future<void> _syncSubscription(String user) async {
    final store = accounts!;
    final sub = await revenueCat!(user);
    if (sub == null) return;
    final now = _clock();
    final entitlements = (sub['subscriber'] as Map?)?['entitlements'];
    DateTime? until;
    var product = '';
    if (entitlements is Map) {
      for (final e in entitlements.values.whereType<Map>()) {
        // بدون تاريخ انتهاء يعني دائم، فنعطيه سنة ونجدده مع كل حدث.
        final exp = e['expires_date'] == null ? now.add(const Duration(days: 366)) : DateTime.tryParse('${e['expires_date']}');
        if (exp != null && exp.isAfter(now) && (until == null || exp.isAfter(until))) {
          until = exp;
          product = '${e['product_identifier']}'.toLowerCase();
        }
      }
    }
    if (until != null) {
      final plan = product.contains('shop') ? 'shop' : (product.contains('year') || product.contains('annual') ? 'yearly' : 'monthly');
      await store.update(user, now, plan: plan, until: until, source: 'store');
    } else if (store.find(user)?['source'] == 'store') {
      await store.update(user, now, plan: 'free');
    }
  }

  /// مقارنة بوقت ثابت عشان ما ينعرف الرمز من سرعة الرد.
  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static const storages = {'ice', 'fridge', 'room', 'hot', 'frozen', 'unknown'};

  Future<String> _contribute(Request req) async {
    final store = contrib;
    if (store == null) throw const FishIdError('contrib_off', 'المساهمة غير متاحة حاليًا', status: 503);
    final (photos, body) = await _readPhotos(req);
    if (body['consent'] != true) throw const FishIdError('contrib_consent', 'نحتاج موافقتك قبل حفظ الصور');
    // نحذف بيانات الموقع من JPEG و PNG فقط، فما نقبل غيرها هنا.
    if (photos.any((p) => p.mediaType == 'image/webp')) throw const FishIdError('fishid_type', 'نوع الصورة غير مدعوم، استخدم JPG أو PNG');
    final species = '${body['species'] ?? ''}';
    if (species.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(species)) throw const FishIdError('bad_request', 'الطلب غير صالح');
    final days = body['days'] is int ? (body['days'] as int).clamp(-1, 30) : -1;
    final storage = storages.contains(body['storage']) ? body['storage'] as String : 'unknown';
    final predicted = [for (final p in (body['predicted'] is List ? body['predicted'] as List : const [])) '$p'].take(3).toList();
    final score = body['score'] is int ? (body['score'] as int).clamp(-1, 100) : -1;
    _limit();
    return store.save(photos, {
      'species': species,
      'species_confirmed': body['speciesConfirmed'] == true && species.isNotEmpty,
      'days_since_catch': days,
      'storage': storage,
      'predicted': predicted,
      'app_score': score,
    }, _clock());
  }

  void _limit() {
    final now = _clock().millisecondsSinceEpoch ~/ 60000;
    if (now != _minute) {
      _minute = now;
      _count = 0;
    }
    if (++_count > perMinute) throw const FishIdError('busy', 'الخدمة مشغولة، حاول بعد دقيقة', status: 429);
  }

  Future<(List<Photo>, Map<String, dynamic>)> _readPhotos(Request req) async {
    final Map<String, dynamic> body;
    try {
      // base64 يكبّر الحجم الثلث، فالحد هنا أكبر من حد الصورة.
      final raw = await req.read().fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) {
        if (b.length + chunk.length > maxBytes * maxPhotos * 1.4) throw const FishIdError('fishid_size', 'الصورة كبيرة، صغّرها وحاول مرة ثانية', status: 413);
        return b..add(chunk);
      });
      body = jsonDecode(utf8.decode(raw.takeBytes())) as Map<String, dynamic>;
    } on FishIdError {
      rethrow;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    final list = body['images'] is List ? body['images'] as List : [body];
    if (list.isEmpty || list.length > maxPhotos) throw const FishIdError('fishid_count', 'أرسل من صورة إلى 3 صور لنفس السمكة');
    return ([for (final item in list) _photo(item)], body);
  }

  static Photo _photo(Object? item) {
    if (item is! Map) throw const FishIdError('bad_request', 'الطلب غير صالح');
    final mediaType = item['mediaType'];
    if (mediaType is! String || !types.contains(mediaType)) throw const FishIdError('fishid_type', 'نوع الصورة غير مدعوم، استخدم JPG أو PNG');
    final image = _decodeImage(item['image']);
    if (image == null || image.isEmpty) throw const FishIdError('fishid_empty', 'الصورة فاضية');
    if (image.length > maxBytes) throw const FishIdError('fishid_size', 'الصورة كبيرة، صغّرها وحاول مرة ثانية', status: 413);
    return Photo(image, mediaType);
  }

  /// يقبل ترميز Serverpod لـ ByteData، أو base64 عادي.
  static Uint8List? _decodeImage(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r"^decode\('(.*)', 'base64'\)$", dotAll: true).firstMatch(v);
    try {
      return base64Decode(m?.group(1) ?? v);
    } on FormatException {
      return null;
    }
  }

  static Response _json(int status, Object? body, {Map<String, String> headers = const {}}) =>
      Response(status, body: jsonEncode(body), headers: {..._cors, ...headers, 'content-type': 'application/json; charset=utf-8'});
}
