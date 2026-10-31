import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_page.dart';
import 'claude.dart';
import 'contrib.dart';
import 'ledger.dart';
import 'site.dart';
import 'staff.dart';
import 'waitlist.dart';

typedef Identify = Future<String> Function(List<Photo> photos);

/// يجيب بيانات المشترك من RevenueCat (GET /v1/subscribers/{id})، و null إذا تعذّر الاتصال.
typedef SubscriberLookup = Future<Map<String, dynamic>?> Function(String user);

/// يرسل تنبيه نصي للمالك (تليجرام). ما يرمي أخطاء، وما ينتظره الطلب.
typedef Notify = void Function(String text);

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
/// POST track من صفحة hawat.id: زيارة أو ضغطة ([site])، وتطلع في الملخص اليومي.
/// POST waitlist من نفس الصفحة: {"contact", "consent": true} إيميل أو جوال لقائمة «بلّغني بالإطلاق» ([waitlist]).
/// admin/... لوحة الأدمن ([adminToken])، و revenuecat يستقبل أحداث الاشتراك. الحدث مجرد تنبيه: الخادم ما يصدّق
/// محتواه، ويسأل RevenueCat ([revenueCat]) عن الاشتراك الحقيقي، فما نحتاج سر مشترك.
class FishIdApp {
  FishIdApp({
    required this.identify,
    this.contrib,
    this.accounts,
    this.ledger,
    this.staff,
    this.adminToken = '',
    this.revenueCat,
    this.speciesNames = const {},
    this.perMinute = 30,
    this.notify,
    this.site,
    this.waitlist,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Identify? identify;
  final ContribStore? contrib;
  final AccountStore? accounts;

  /// المحاسبة (الدخل والمصاريف) للوحة الأدمن. تحتاج [accounts].
  final Ledger? ledger;

  /// مستخدمين اللوحة الثانيين (محاسب، مستثمر...) برموزهم.
  final StaffStore? staff;
  final String adminToken;
  final SubscriberLookup? revenueCat;

  /// رقم حوات (4 أرقام) والاسم المحلي، للوحة الأدمن.
  final Map<String, String> speciesNames;
  final int perMinute;

  /// تنبيهات المالك: اشتراكات، مساهمات، رفض Claude، وملخص يومي ([dailySummary]).
  final Notify? notify;

  /// زيارات وضغطات صفحة hawat.id.
  final SiteStats? site;

  /// المسجلين في «بلّغني بالإطلاق».
  final Waitlist? waitlist;
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

  /// آخر وقت انرسل فيه كل نوع تنبيه، عشان ما يتكرر نفس التنبيه كثير.
  final _told = <String, DateTime>{};

  void _tell(String key, String text, {Duration every = Duration.zero}) {
    final send = notify;
    if (send == null) return;
    final now = _clock();
    final last = _told[key];
    if (last != null && now.difference(last) < every) return;
    if (_told.length > 1000) _told.clear();
    _told[key] = now;
    send(text);
  }

  Handler get handler => (Request req) async {
    if (req.method == 'OPTIONS') return Response.ok(null, headers: _cors);
    // يقبل المسار مع /api/ أو بدونها، حسب إعداد البروكسي.
    final path = req.url.path.replaceFirst(RegExp(r'^api/'), '');
    if (req.method == 'GET' && (path == '' || path == 'health')) {
      return _json(200, {'ok': true, 'service': 'fish-id', 'ready': identify != null});
    }
    if (req.method == 'POST' && path == 'track') {
      final stats = site;
      if (stats != null) {
        try {
          final text = await req.readAsString();
          final body = text.length > 2000 ? null : jsonDecode(text);
          if (body is Map) {
            final ip = (req.headers['x-forwarded-for'] ?? '').split(',').first.trim();
            stats.record(body, ip: ip, agent: req.headers['user-agent'] ?? '', now: _clock());
          }
        } on Object {
          // حدث تالف من الصفحة ما يهم.
        }
      }
      return Response(204, headers: _cors);
    }
    if (req.method == 'POST' && path == 'waitlist') {
      final list = waitlist;
      if (list == null) return _json(503, {'code': 'unavailable', 'message': 'التسجيل مو متاح الحين'});
      try {
        final text = await req.readAsString();
        final body = text.length > 2000 ? null : jsonDecode(text);
        if (body is! Map) throw const FishIdError('bad_request', 'الطلب غير صالح');
        final ip = (req.headers['x-forwarded-for'] ?? '').split(',').first.trim();
        final added = await list.add(body, ip: ip, now: _clock());
        // تنبيه لكل تسجيل جديد: التكرار ممنوع من القائمة نفسها، وكل IP له حد باليوم.
        if (added) {
          final beta = body['beta'] == true ? ' · يبغى يجرب على ${body['os'] == 'ios' ? 'آيفون' : 'أندرويد'}' : '';
          final kind = '${body['contact']}'.contains('@') ? 'إيميل' : 'جوال';
          _tell('waitlist:${list.count}', '📝 تسجيل جديد في «بلّغني بالإطلاق» ($kind)$beta\nالمجموع: ${list.count}');
        }
        return _json(200, {'ok': true, 'new': added});
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      } on FormatException {
        return _json(400, {'code': 'bad_request', 'message': 'الطلب غير صالح'});
      }
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
        return _json(200, {'plan': v['from'] == 'owner' ? 'owner' : (v['active'] == true ? v['plan'] : 'free'), 'until': v['until'], 'remaining': v['remaining']});
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
    final String result;
    try {
      result = await runZoned(() => run(photos), zoneValues: {usageKey: usage, langKey: lang});
    } on FishIdError catch (e) {
      if (e.code.startsWith('claude_')) {
        await ledger?.raise(e.code, _clock());
        _tell(
          e.code,
          e.code == 'claude_credit'
              ? '🔴 FISH ID: رصيد Claude خلص والفحوصات متوقفة. اشحن الرصيد من console.anthropic.com وحدّثه في تبويب التنبيهات.'
              : '🔴 FISH ID: Claude رفض المفتاح والفحوصات متوقفة. تأكد من المفتاح في السيرفر.',
          every: const Duration(hours: 3),
        );
      }
      rethrow;
    }
    await store?.record(user, _clock(), result: result, usd: usageCost(usage), ms: watch.elapsedMilliseconds, photos: photos.length);
    // أول فحص ناجح للحساب يعني مستخدم جديد فعلي (الحساب نفسه ينفتح بمجرد فتح التطبيق).
    if (user != null && store != null && store.find(user)?['scans'] == 1) {
      final users = store.all.where((a) => (a['scans'] as int? ?? 0) > 0).length;
      _tell('user:$user', '👤 مستخدم جديد سوّى أول فحص في التطبيق\nعدد المستخدمين: $users');
    }
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
    final auth = req.headers['authorization'] ?? '';
    final Map<String, dynamic> who;
    if (_same(auth, 'Bearer $adminToken')) {
      who = {'role': 'owner', 'name': ''};
    } else if ((auth.startsWith('Bearer fs_') ? staff?.match(auth.substring(7)) : null) case final Map<String, dynamic> m) {
      who = m..remove('token');
    } else {
      _adminFails++;
      throw const FishIdError('unauthorized', 'الرمز غير صحيح', status: 401);
    }
    final store = accounts;
    final parts = path.split('/');
    final section = parts.length > 1 ? parts[1] : '';
    final role = who['role'];
    final allowed = switch (role) {
      'owner' => true,
      'admin' => section != 'staff',
      'accountant' => const {'me', 'species', 'stats', 'ledger', 'report', 'alerts'}.contains(section),
      'investor' => const {'me', 'species', 'report'}.contains(section) && req.method == 'GET',
      _ => false,
    };
    if (!allowed) throw const FishIdError('forbidden', 'ما عندك صلاحية لهذا القسم', status: 403);
    final q = req.url.queryParameters;
    Future<Map<String, dynamic>> body() async {
      try {
        return jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      } on Object {
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      }
    }

    switch ((req.method, parts.length > 1 ? parts[1] : '')) {
      case ('GET', 'me'):
        return _json(200, who);
      case ('GET', 'species'):
        return _json(200, speciesNames);
      case ('GET', 'staff') when staff != null:
        return _json(200, staff!.list());
      case ('POST', 'staff') when staff != null:
        final b = await body();
        if (b['add'] is Map) return _json(200, await staff!.add('${b['add']['name'] ?? ''}', '${b['add']['role'] ?? ''}', now));
        if (b['delete'] is String) await staff!.remove(b['delete'] as String);
        return _json(200, staff!.list());
      case ('GET', 'report') when ledger != null:
        final period = q['period'] ?? 'month';
        final key = q['key'] ?? '';
        if (!Reports.valid(period, key)) throw const FishIdError('bad_request', 'الفترة غير صحيحة');
        return _json(200, ledger!.summary(period, key, now));
      case ('GET', 'alerts') when ledger != null:
        return _json(200, ledger!.alerts(now));
      case ('POST', 'alerts') when ledger != null:
        final b = await body();
        if (b['balanceUsd'] is! num) throw const FishIdError('bad_request', 'الطلب غير صالح');
        await ledger!.setBalance(b['balanceUsd'] as num, now);
        return _json(200, ledger!.alerts(now));
      case ('GET', 'waitlist') when waitlist != null:
        return _json(200, waitlist!.view(now));
      case ('POST', 'waitlist') when waitlist != null:
        final b = await body();
        if (b['delete'] is String) await waitlist!.remove(b['delete'] as String);
        return _json(200, waitlist!.view(now));
      case ('GET', 'site'):
        return _json(200, {
          ...?site?.view(now),
          'status': {'server': true, 'claude': identify != null, 'telegram': notify != null, 'accounts': store != null},
        });
      case ('GET', 'stats') when store != null:
        return _json(200, {
          ...store.stats(now),
          if (ledger != null) 'ledger': {
            ...ledger!.statement(Ledger.month(now))..remove('income')..remove('expenses'),
            'incomeYearSar': ledger!.history(Ledger.month(now)).fold<num>(0, (t, h) => t + (h['incomeSar'] as num)),
          },
        });
      case ('GET', 'ledger') when ledger != null:
        final m = q['month'] ?? '';
        return _json(200, ledger!.report(Ledger.monthPattern.hasMatch(m) ? m : Ledger.month(now)));
      case ('POST', 'ledger') when ledger != null:
        final b = await body();
        if (b['add'] is Map) {
          await ledger!.add((b['add'] as Map).cast<String, dynamic>(), now);
        } else if (b['delete'] is String) {
          await ledger!.remove(b['delete'] as String);
        } else if (b['stop'] is String && Ledger.monthPattern.hasMatch('${b['last']}')) {
          await ledger!.stop(b['stop'] as String, b['last'] as String);
        } else {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        return _json(200, {'ok': true});
      case ('GET', 'users') when store != null && parts.length == 3:
        final d = store.detail(parts[2], now);
        if (d == null) throw const FishIdError('not_found', 'الحساب غير موجود', status: 404);
        return _json(200, d);
      case ('GET', 'users') when store != null:
        return _json(
          200,
          store.users(
            now,
            q: q['q'] ?? '',
            tab: q['view'] ?? 'all',
            plan: q['plan'] ?? '',
            from: q['from'] ?? '',
            activity: q['activity'] ?? '',
            page: int.tryParse(q['page'] ?? '') ?? 1,
          ),
        );
      case ('POST', 'users') when store != null && (parts.length == 3 && AccountStore.idPattern.hasMatch(parts[2]) || parts.length == 2):
        final b = await body();
        // حساب واحد من الرابط، أو عدة حسابات دفعة وحدة في ids (حد 200).
        final ids = parts.length == 3 ? [parts[2]] : [...?(b['ids'] as List?)?.whereType<String>().where(AccountStore.idPattern.hasMatch).take(200)];
        if (ids.isEmpty) throw const FishIdError('bad_request', 'الطلب غير صالح');
        final days = (b['days'] as num?)?.toInt();
        final extend = (b['extend'] as num?)?.toInt();
        final by = '${who['name'] ?? ''}'.isEmpty ? '${who['role']}' : '${who['name']}';
        final out = <Map<String, dynamic>>[];
        for (final id in ids) {
          if (parts.length == 2 && store.find(id) == null) continue;
          DateTime? until = days == null ? null : now.add(Duration(days: days));
          String? plan = b['plan'] as String?;
          // التمديد يضيف أيام على تاريخ الانتهاء الحالي (أو من اليوم إذا انتهى) بنفس الباقة.
          if (extend != null && extend > 0) {
            final a = store.find(id);
            final cur = DateTime.tryParse('${a?['until']}');
            until = (cur != null && cur.isAfter(now) ? cur : now).add(Duration(days: extend));
            plan ??= a?['plan'] == 'free' || a == null ? 'monthly' : a['plan'] as String;
          }
          out.add(await store.update(id, now, grant: (b['grant'] as num?)?.toInt(), plan: plan, until: until, blocked: b['blocked'] as bool?, owner: b['owner'] as bool?, by: by));
        }
        return _json(200, parts.length == 3 ? out.single : {'updated': out.length});
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
        if (event[k] is List)
          for (final id in event[k] as List) '$id',
    }.where(AccountStore.idPattern.hasMatch).take(5);
    final buyer = '${event['app_user_id']}';
    Map<String, dynamic>? sub;
    for (final user in users) {
      final s = await _syncSubscription(user);
      if (user == buyer) sub = s;
    }
    // نسجّل المبلغ في المحاسبة بس إذا RevenueCat أكد إن المشتري عنده نفس المنتج.
    if (ledger != null && AccountStore.idPattern.hasMatch(buyer)) {
      final entitlements = (sub?['subscriber'] as Map?)?['entitlements'];
      final confirmed = entitlements is Map && entitlements.values.whereType<Map>().any((e) => e['product_identifier'] == event['product_id']);
      await ledger!.recordSale(event, user: buyer, confirmed: confirmed, now: _clock());
    }
    _tellSale(event, buyer, sub);
    return _json(200, {'ok': true});
  }

  static const _saleTypes = {
    'INITIAL_PURCHASE': '🎉 اشتراك جديد',
    'RENEWAL': '🔁 تجديد اشتراك',
    'PRODUCT_CHANGE': '🔀 تغيير باقة',
    'UNCANCELLATION': '↩️ رجع فعّل التجديد',
    'CANCELLATION': '⚠️ إلغاء تجديد',
    'BILLING_ISSUE': '⚠️ مشكلة في الدفع',
    'EXPIRATION': '⏹️ انتهى اشتراك',
  };

  /// الحدث نفسه ما ينصدّق (الرابط بدون سر)، فما نرسل تنبيه إلا إذا RevenueCat أكد إن الحساب عنده نفس المنتج،
  /// أو كان الحساب معروف عندنا في أحداث الإلغاء والانتهاء.
  void _tellSale(Map event, String buyer, Map<String, dynamic>? sub) {
    final type = '${event['type']}';
    final title = _saleTypes[type];
    if (title == null || sub == null) return;
    final product = '${event['product_id'] ?? ''}';
    final entitlements = (sub['subscriber'] as Map?)?['entitlements'];
    final owns = entitlements is Map && entitlements.values.whereType<Map>().any((e) => e['product_identifier'] == product);
    final known = accounts?.find(buyer) != null;
    if (!(owns || (known && const {'CANCELLATION', 'BILLING_ISSUE', 'EXPIRATION'}.contains(type)))) return;
    final p = product.toLowerCase();
    final plan = p.contains('shop') ? 'محلات' : (p.contains('year') || p.contains('annual') ? 'سنوي' : 'شهري');
    final amount = event['price_in_purchased_currency'];
    final price = amount is num && amount != 0 ? ' · ${amount.toStringAsFixed(2)} ${event['currency'] ?? ''}' : '';
    final test = event['environment'] == 'SANDBOX' ? ' (تجربة)' : '';
    // RevenueCat يعيد إرسال الحدث إذا تأخر الرد، فنفس الحدث ما يتكرر تنبيهه.
    _tell('sale:${event['id'] ?? buyer}', '$title$test: باقة $plan$price\nالحساب: $buyer', every: const Duration(days: 7));
  }

  /// ملخص اليوم للمالك: الفحوصات والتكلفة والمستخدمين والاشتراكات والتنبيهات المفتوحة. null إذا ما فيه حسابات.
  String? dailySummary(DateTime now) {
    final store = accounts;
    final web = site?.summaryLines(now) ?? const <String>[];
    if (store == null) return web.isEmpty ? null : ['📊 FISH ID: ملخص اليوم ${SiteStats.dayOf(now)}', ...web.skip(1)].join('\n');
    final s = store.stats(now);
    String sar(Object? v) => (v as num).toStringAsFixed(2);
    final plans = s['plans'] as Map;
    final lines = [
      '📊 FISH ID: ملخص اليوم ${now.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10)}',
      'الفحوصات اليوم: ${s['scansToday']} (تكلفة ${sar(s['costTodaySar'])} ريال)',
      'فحوصات الشهر: ${s['scansMonth']} (تكلفة ${sar(s['costMonthSar'])} ريال)',
      'مستخدمين جدد اليوم: ${s['newToday']} · الأسبوع: ${s['newWeek']} · الكل: ${s['users']}',
      'المشتركين: ${s['paying']} (شهري ${plans['monthly']}، سنوي ${plans['yearly']}، محلات ${plans['shop']})',
      'الدخل الشهري التقديري: ${sar(s['mrrSar'])} ريال',
    ];
    final alerts = ledger?.alerts(now);
    for (final a in (alerts?['alerts'] as List? ?? const []).whereType<Map>()) {
      switch (a['code']) {
        case 'claude_credit' || 'claude_account':
          lines.add('🔴 Claude رافض الطلبات من ${'${a['at']}'.substring(0, 16)}');
        case 'balance_out':
          lines.add('🔴 رصيد Claude خلص حسب التقدير');
        case 'balance_low':
          lines.add('🟠 رصيد Claude باقي حوالي \$${a['leftUsd']}${a['daysLeft'] == null ? '' : '، يكفي ${a['daysLeft']} يوم'}');
        case 'bill_due':
          lines.add('🟠 فاتورة ${a['label']} (${a['provider']}) تستحق ${a['due']}: ${sar(a['sar'])} ريال');
      }
    }
    final wl = waitlist?.view(now);
    if (wl != null) lines.add('📝 «بلّغني بالإطلاق»: ${wl['count']} مسجل (اليوم +${wl['today']})، للتجربة المبكرة: أندرويد ${wl['betaAndroid']}، آيفون ${wl['betaIos']}');
    return [...lines, ...web].join('\n');
  }

  /// ياخذ أبعد تاريخ انتهاء من صلاحيات المشترك الفعّالة في RevenueCat ويحطه على الحساب.
  /// إذا ما عنده صلاحية فعّالة (انتهى أو استرجع فلوسه) والباقة جت من المتجر، يرجع مجاني.
  /// الباقات اللي يعطيها الأدمن ما تتأثر. يرجّع رد RevenueCat.
  Future<Map<String, dynamic>?> _syncSubscription(String user) async {
    final store = accounts!;
    final sub = await revenueCat!(user);
    if (sub == null) return null;
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
    return sub;
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
    final id = await store.save(photos, {
      'species': species,
      'species_confirmed': body['speciesConfirmed'] == true && species.isNotEmpty,
      'days_since_catch': days,
      'storage': storage,
      'predicted': predicted,
      'app_score': score,
    }, _clock());
    final name = species.isEmpty ? 'بدون نوع' : '${speciesNames[species] ?? species} ($species)';
    _tell(
      'contrib',
      '📸 مساهمة جديدة بصورة: $name · ${photos.length} صور${days >= 0 ? ' · $days يوم من الصيد' : ''}. راجعها من لوحة الأدمن.',
      every: const Duration(minutes: 10),
    );
    return id;
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
