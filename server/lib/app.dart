import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_page.dart';
import 'ads.dart';
import 'basma.dart';
import 'basma_api.dart';
import 'book.dart';
import 'claude.dart';
import 'collect_page.dart';
import 'collectors.dart';
import 'contrib.dart';
import 'gov.dart';
import 'gov_page.dart';
import 'ledger.dart';
import 'shop_page.dart';
import 'shops.dart';
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
/// collect?k=... صفحة المصوّرين، و collect/me و collect/join و collect/upload بمفتاح المصوّر في `x-collector` ([collectors]).
/// shop صفحة اشتراك المحلات ولوحة المحل (بمفتاحه في `x-shop`)، و shop/paid رجوع ميسر بعد الدفع، و moyasar أحداث ميسر ([shops]، [gateway]).
/// admin/... لوحة الأدمن ([adminToken])، و revenuecat يستقبل أحداث الاشتراك. الحدث مجرد تنبيه: الخادم ما يصدّق
/// محتواه، ويسأل RevenueCat ([revenueCat]) عن الاشتراك الحقيقي، فما نحتاج سر مشترك.
class FishIdApp {
  FishIdApp({
    required this.identify,
    this.box,
    this.gov,
    this.contrib,
    this.collectors,
    this.book,
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
    this.ads,
    this.shops,
    this.gateway,
    this.basma,
    this.basmaApi,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    ledger?.ads = ads;
    final s = shops;
    if (s != null && accounts != null) {
      accounts!.pool = s.byId;
      accounts!.savePool = s.save;
    }
    if (gov != null) accounts?.unlimited = gov!.unlimited;
  }

  /// صورة الصندوق للدلّال: الأنواع والعدد التقريبي والطزاجة من صورة صندوق أو حمولة ([FishIdAi.box]).
  final Identify? box;

  /// الجهات الرسمية ومفتشينها وزياراتهم ([GovStore]).
  final GovStore? gov;

  /// المحلات المشتركة من الموقع، وأجهزتها تسحب من رصيد واحد.
  final ShopStore? shops;

  /// بوابة الدفع للمحلات. بدونها الصفحة تسجّل الطلب وتحوّل للواتساب والتحويل البنكي.
  final Gateway? gateway;

  final Identify? identify;
  final ContribStore? contrib;

  /// المصوّرين اللي يجمعون صور الأسواق بروابط خاصة، وصورهم تنحفظ في [contrib].
  final CollectorStore? collectors;

  /// أرشيف كتاب أسماك البحر الأحمر (صور وأسماء محلية) للوحة الأدمن.
  final BookArchive? book;
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

  /// أرقام الإعلانات من المنصات، للبريف اليومي والمحاسبة.
  final AdStore? ads;

  /// «بصمة» في الظل: تقارن نموذجنا بـ Opus على كل فحص حقيقي بدون ما تأثر على الجواب (admin/basma).
  final BasmaShadow? basma;

  /// «بصمة API» للعملاء بمفاتيحهم (basma/v1/...)، وإدارتهم من admin/basma-clients.
  final BasmaApi? basmaApi;
  final DateTime Function() _clock;

  static const maxBytes = 5 * 1024 * 1024;
  static const maxPhotos = 3;
  static const types = {'image/jpeg', 'image/png', 'image/webp'};
  static const _cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'POST, GET, OPTIONS',
    'access-control-allow-headers': 'content-type, authorization, x-api-key, x-fishid-user, x-fishid-lang, x-collector, x-shop, x-gov',
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
    if (path.startsWith('basma/v1/') && basmaApi != null) {
      return basmaApi!.handle(req, path.substring(9), _clock());
    }
    if (req.method == 'POST' && path == 'fishId/identify') {
      try {
        final user = _user(req);
        final result = await _identify(req, user, identify);
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
        final inspector = gov?.profile(user, _clock());
        final sid = shops?.shopOf(user);
        final shop = sid == null ? null : shops!.byId(sid);
        return _json(200, {
          'plan': v['from'] == 'owner' ? 'owner' : (inspector?['active'] == true ? 'gov' : (v['active'] == true ? v['plan'] : 'free')),
          'until': v['until'],
          'remaining': v['remaining'],
          // صاحب المحل يشوف رمز محله في التطبيق عشان يعطيه موظفينه.
          if (shop != null && shop['owner'] == user)
            'shop': {'code': shop['join'], 'devices': (shop['devices'] as List).length, 'maxDevices': _shopDevices, 'used': ShopStore.used(shop, _clock()), 'cap': _shopCap},
          // المفتش يشوف بياناته وجهته وزياراته في الوضع الرسمي.
          'gov': ?inspector,
        });
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'fishId/box') {
      try {
        final user = _user(req);
        final result = await _identify(req, user, box);
        return _json(200, result, headers: _remaining(user));
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (path.startsWith('fishId/gov/')) {
      try {
        return await _govApp(req, path.substring(11));
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
        if (shops?.byJoin(code) case (final id, final shop)) {
          await _link(id, shop, user);
          return _json(200, {'remaining': store.remaining(user, _clock()), 'shop': shop['name']}, headers: _remaining(user));
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
    // سكربت Google Ads يرسل أرقام قوقل هنا بمفتاح الدفع (Authorization: Bearer ap_...).
    if (req.method == 'POST' && path == 'ads/push') {
      final store = ads;
      try {
        final key = (req.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
        if (store == null || !store.keys.pushMatches(key)) throw const FishIdError('unauthorized', 'المفتاح غير صحيح', status: 401);
        final text = await req.readAsString();
        final b = text.length > 4000 ? null : jsonDecode(text);
        if (b is! Map) throw const FishIdError('bad_request', 'الطلب غير صالح');
        final now = _clock();
        final platform = '${b['platform'] ?? 'google'}';
        final row = await store.put('${b['day']}', platform, b, usdToSar: _usdToSar, src: 'push', now: now);
        store.keys.status[platform] = {'ok': true, 'at': now.toUtc().toIso8601String()};
        await store.keys.seen(platform, now);
        return _json(200, row);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      } on FormatException {
        return _json(400, {'code': 'bad_request', 'message': 'الطلب غير صالح'});
      }
    }
    // سناب يرجّع المالك هنا بعد الموافقة، ونبدّل الكود بمفتاح دائم.
    if (req.method == 'GET' && path == 'ads/snap') {
      final store = ads;
      final q = req.url.queryParameters;
      var msg = 'تم ربط سناب ✅ ارجع للوحة الإدارة.';
      try {
        if (store == null || q['code'] == null) throw const FishIdError('bad_request', 'ما وصل كود من سناب');
        final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        await store.keys.snapCallback(q['code']!, q['state'] ?? '', snapRedirect, http);
        http.close();
        await store.pull(SiteStats.dayOf(_clock()), usdToSar: _usdToSar, now: _clock());
      } on FishIdError catch (e) {
        msg = e.message;
      } on Object catch (e) {
        stderr.writeln('snap connect: $e');
        msg = 'تعذّر الربط، حاول مرة ثانية';
      }
      return Response.ok(
        '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="font-family:sans-serif;padding:40px;text-align:center" dir="rtl"><h2>${const HtmlEscape().convert(msg)}</h2><a href="/api/admin#brief">لوحة الإدارة</a>',
        headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store'},
      );
    }
    if (path == 'admin' || path.startsWith('admin/')) {
      try {
        return await _admin(req, path);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (path == 'gov' || path.startsWith('gov/')) {
      try {
        return await _govPanel(req, path);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (path == 'shop' || path.startsWith('shop/')) {
      try {
        return await _shop(req, path);
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    if (req.method == 'POST' && path == 'moyasar') {
      try {
        return await _moyasarHook(req);
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
    // صورة النوع للتطبيق: صورنا المقبولة من المصوّرين أولًا، وإلا صورة الكتاب. المصدر في x-photo-source.
    if (req.method == 'GET' && path.startsWith('book/') && path.endsWith('.jpg')) {
      final id = path.substring(5, path.length - 4);
      final m = RegExp(r'^HWT-FISH-([0-9]{4})$').firstMatch(id);
      final mine = m == null ? null : contrib?.bestPhoto(m.group(1)!);
      final f = mine ?? book?.photo(id);
      if (f == null) return Response.notFound('', headers: {'cache-control': 'public, max-age=86400'});
      return Response.ok(
        await f.readAsBytes(),
        headers: {
          'content-type': f.path.endsWith('png') ? 'image/png' : 'image/jpeg',
          'cache-control': 'public, max-age=86400',
          'x-photo-source': mine != null ? 'fishid' : 'book',
          'access-control-expose-headers': 'x-photo-source',
        },
      );
    }
    if (path == 'collect' || path.startsWith('collect/')) {
      try {
        return await _collect(req, path);
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

  Future<String> _identify(Request req, String? user, Identify? run) async {
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
    if (photos.isNotEmpty) basma?.compare(photos.first, result, _clock());
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
      'accountant' => const {'me', 'species', 'stats', 'ledger', 'report', 'alerts', 'brief'}.contains(section),
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
      case ('GET', 'basma') when basma != null:
        return _json(200, basma!.summary());
      case ('GET', 'basma-clients') when basmaApi != null:
        return _json(200, {'plans': BasmaClients.plans, 'vat': BasmaClients.vat, 'clients': basmaApi!.clients.list(now)});
      case ('POST', 'basma-clients') when basmaApi != null && role == 'owner':
        final b = await body();
        final c = basmaApi!.clients;
        if (b['add'] is Map) return _json(200, await c.add(b['add'] as Map, now));
        if (b['id'] is String && b['rotate'] == true) return _json(200, await c.rotate(b['id'] as String));
        if (b['id'] is String && b['delete'] == true) {
          await c.remove(b['id'] as String);
          return _json(200, {'ok': true});
        }
        if (b['id'] is String && b['update'] is Map) return _json(200, await c.update(b['id'] as String, b['update'] as Map, now));
        throw const FishIdError('bad_request', 'الطلب غير صالح');
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
      case ('GET', 'brief'):
        final d = q['day'] ?? '';
        return _json(200, brief(AdStore.dayPattern.hasMatch(d) ? d : SiteStats.dayOf(now), now));
      case ('GET', 'ads') when ads != null:
        return _json(200, {
          'platforms': ads!.keys.view(),
          'tiktok': {'handle': ads!.keys.has('tiktok') ? '${ads!.keys.get('tiktok')['handle']}' : null, 'promos': ads!.keys.promos},
          if (role == 'owner') 'pushKey': await ads!.keys.pushKey(),
        });
      case ('POST', 'ads') when ads != null && role != 'accountant':
        final b = await body();
        if (b['put'] is Map) {
          final p = (b['put'] as Map);
          await ads!.put('${p['day']}', '${p['platform']}', p, usdToSar: _usdToSar, src: 'manual', now: now);
        } else if (b['link'] is Map && role == 'owner') {
          final l = b['link'] as Map;
          await ads!.keys.set('${l['platform']}', l);
          await ads!.pull(SiteStats.dayOf(now), usdToSar: _usdToSar, now: now);
        } else if (b['snapUrl'] == true && role == 'owner') {
          return _json(200, {'url': ads!.keys.snapAuthUrl(snapRedirect)});
        } else if (b['promo'] is Map && role == 'owner') {
          await ads!.keys.addPromo(b['promo'] as Map);
          await ads!.pull(SiteStats.dayOf(now), usdToSar: _usdToSar, now: now);
        } else if (b['unpromo'] is int && role == 'owner') {
          await ads!.keys.removePromo(b['unpromo'] as int);
        } else if (b['unlink'] is String && role == 'owner') {
          await ads!.keys.remove(b['unlink'] as String);
        } else if (b['pull'] == true) {
          final d = '${b['day'] ?? ''}';
          final today = SiteStats.dayOf(now);
          // يوم قديم (من الأيام اللي قبل الربط): يسحب أرقام ذاك اليوم بس، لين 90 يوم ورا.
          if (AdStore.dayPattern.hasMatch(d) && d.compareTo(today) < 0 && d.compareTo(SiteStats.dayOf(now.subtract(const Duration(days: 90)))) >= 0) {
            await ads!.pull(d, usdToSar: _usdToSar, now: now);
          } else {
            await pullAds(now);
          }
        } else {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        return _json(200, {'platforms': ads!.keys.view()});
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
          if (ledger != null)
            'ledger': {
              ...ledger!.statement(Ledger.month(now))
                ..remove('income')
                ..remove('expenses'),
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
          // باقة يدوية من الأدمن تفك الجهاز من محله.
          if (b['plan'] != null || extend != null) {
            if (shops?.shopOf(id) case final sid? when shops!.byId(sid)?['owner'] != id) await _unlink(sid, id);
          }
          DateTime? until = days == null ? null : now.add(Duration(days: days));
          String? plan = b['plan'] as String?;
          // التمديد يضيف أيام على تاريخ الانتهاء الحالي (أو من اليوم إذا انتهى) بنفس الباقة.
          if (extend != null && extend > 0) {
            final a = store.find(id);
            final cur = DateTime.tryParse('${a?['until']}');
            until = (cur != null && cur.isAfter(now) ? cur : now).add(Duration(days: extend));
            plan ??= a?['plan'] == 'free' || a == null ? 'monthly' : a['plan'] as String;
          }
          out.add(
            await store.update(
              id,
              now,
              grant: (b['grant'] as num?)?.toInt(),
              plan: plan,
              until: until,
              blocked: b['blocked'] as bool?,
              owner: b['owner'] as bool?,
              by: by,
            ),
          );
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
      case ('GET', 'book') when book != null && parts.length == 2:
        final ours = contrib?.ours(now: now) ?? const {};
        String? fish(Object? id) => '$id'.startsWith('HWT-FISH-') ? '$id'.substring(9) : null;
        return _json(200, [
          for (final s in book!.species) {...s, 'ours': ours[fish(s['ksafish'])] ?? const []},
        ]);
      case ('GET', 'book') when book != null && parts.length == 4:
        final f = book!.file(parts[2], parts[3]);
        if (f == null) break;
        return Response.ok(await f.readAsBytes(), headers: {'content-type': 'image/jpeg', 'cache-control': 'private, max-age=86400'});
      case ('GET', 'shops') when shops != null:
        return _json(200, {
          'ready': gateway != null,
          'test': gateway?.test ?? false,
          'items': [for (final s in shops!.list()) _shopView(s['id'] as String, s, now, admin: true)],
        });
      case ('POST', 'shops') when shops != null:
        final b = await body();
        final id = '${b['id'] ?? ''}';
        final shop = shops!.byId(id);
        if (shop == null) throw const FishIdError('not_found', 'المحل غير موجود', status: 404);
        final by = '${who['name'] ?? ''}'.isEmpty ? '${who['role']}' : '${who['name']}';
        if (b['transfer'] is num) {
          // تحويل بنكي: يمد شهر ويسجّل الدخل في المحاسبة كقيد يدوي.
          final sar = (b['transfer'] as num).toDouble();
          if (sar <= 0 || sar > 100000) throw const FishIdError('bad_request', 'اكتب المبلغ اللي وصل');
          final pid = 'transfer_${now.microsecondsSinceEpoch.toRadixString(36)}';
          final until = await shops!.paid(id, {'id': pid, 'at': now.toUtc().toIso8601String(), 'sar': sar, 'method': 'transfer', 'by': by}, now);
          await ledger?.add({
            'kind': 'income',
            'provider': 'تحويل بنكي',
            'label': 'باقة محل: ${shop['name']}',
            'amount': sar,
            'date': now.toUtc().toIso8601String().substring(0, 10),
            'note': 'حتى ${until.toIso8601String().substring(0, 10)}',
          }, now);
        } else if (b['stopped'] is bool) {
          shop['stopped'] = b['stopped'];
          await shops!.save();
        } else if (b['autoRenew'] is bool) {
          shop['autoRenew'] = b['autoRenew'];
          await shops!.save();
        } else {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        return _json(200, _shopView(id, shop, now, admin: true));
      case ('GET', 'gov') when gov != null:
        return _json(200, gov!.list(now));
      case ('POST', 'gov') when gov != null:
        final b = await body();
        if (b['add'] is Map) return _json(200, await gov!.addAgency(b['add'] as Map, now));
        if (b['agency'] is String && b['inspector'] is Map) return _json(200, await gov!.addInspector(b['agency'] as String, b['inspector'] as Map, now));
        if (b['agency'] is String && b['update'] is Map) return _json(200, await gov!.updateAgency(b['agency'] as String, b['update'] as Map));
        if (b['inspectorId'] is String && b['update'] is Map) return _json(200, await gov!.updateInspector(b['inspectorId'] as String, b['update'] as Map));
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      case ('GET', 'collectors') when collectors != null:
        return _json(200, [
          for (final c in collectors!.list()) {...c, 'today': collectors!.today(c, now)},
        ]);
      case ('POST', 'collectors') when collectors != null:
        final b = await body();
        if (b['add'] is Map) return _json(200, await collectors!.add('${b['add']['name'] ?? ''}', '${b['add']['city'] ?? ''}', now));
        if (b['invite'] == 'new') return _json(200, {'invite': await collectors!.newInvite()});
        if (b['invite'] == 'show') return _json(200, {'invite': collectors!.invite ?? await collectors!.newInvite()});
        if (b['key'] is String && b['active'] is bool) await collectors!.setActive(b['key'] as String, b['active'] as bool);
        return _json(200, {'ok': true});
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

  /// طلبات تطبيق المفتش: join و leave و visits و visit (الحساب في x-fishid-user).
  Future<Response> _govApp(Request req, String sub) async {
    final store = gov;
    final user = _user(req);
    if (store == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    if (user == null) throw const FishIdError('update_app', 'حدّث التطبيق من المتجر', status: 426);
    final now = _clock();
    switch ((req.method, sub)) {
      case ('POST', 'join'):
        _limit();
        final String code;
        try {
          code = '${(jsonDecode(await req.readAsString()) as Map)['code']}';
        } on Object {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        final p = await store.join(code, user, now);
        _tell('gov:${p['id']}', '🏛️ مفتش دخل التطبيق: ${p['name']} · ${p['agency']}', every: const Duration(days: 1));
        return _json(200, p, headers: _remaining(user));
      case ('POST', 'leave'):
        await store.leave(user);
        return _json(200, {'ok': true}, headers: _remaining(user));
      case ('GET', 'visits'):
        return _json(200, {'profile': store.profile(user, now), 'visits': store.visitsOf(user)});
      case ('POST', 'visit'):
        _limit();
        final (photos, body) = await _readVisit(req);
        final v = await store.addVisit(user, body, photos, now);
        if (v['decision'] == 'violation') {
          _tell('govv:${v['ref']}', '🏛️ مخالفة جديدة ${v['ref']}: ${v['shop']} · ${v['market']} (${v['inspectorName']})', every: const Duration(minutes: 30));
        }
        return _json(200, v);
    }
    throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
  }

  /// جسم الزيارة: الحقول مع صور اختيارية في images (حتى 3).
  Future<(List<Photo>, Map<String, dynamic>)> _readVisit(Request req) async {
    final Map<String, dynamic> body;
    try {
      final raw = await req.read().fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) {
        if (b.length + chunk.length > maxBytes * maxPhotos * 1.4) throw const FishIdError('fishid_size', 'الصور كبيرة، صغّرها وحاول مرة ثانية', status: 413);
        return b..add(chunk);
      });
      body = jsonDecode(utf8.decode(raw.takeBytes())) as Map<String, dynamic>;
    } on FishIdError {
      rethrow;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    final list = body.remove('images');
    final photos = list is List ? [for (final item in list.take(maxPhotos)) _photo(item)] : <Photo>[];
    return (photos, body);
  }

  /// لوحة الجهة الرسمية: الصفحة على gov، والبيانات بمفتاح الجهة في x-gov.
  Future<Response> _govPanel(Request req, String path) async {
    final store = gov;
    if (store == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    if (req.method == 'GET' && path == 'gov') {
      return Response.ok(govPage, headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer'});
    }
    final now = _clock();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (minute != _govMinute) {
      _govMinute = minute;
      _govFails = 0;
    }
    if (_govFails >= 20) throw const FishIdError('busy', 'محاولات كثيرة، حاول بعد دقيقة', status: 429);
    final found = store.byKey(req.headers['x-gov'] ?? req.url.queryParameters['k'] ?? '');
    if (found == null) {
      _govFails++;
      throw const FishIdError('unauthorized', 'رابط اللوحة غير صحيح أو موقوف', status: 401);
    }
    final (id, _) = found;
    final parts = path.split('/');
    switch ((req.method, parts.length > 1 ? parts[1] : '')) {
      case ('GET', 'data'):
        final m = req.url.queryParameters['month'] ?? '';
        return _json(200, store.dashboard(id, RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(m) ? m : now.toUtc().toIso8601String().substring(0, 7), now));
      case ('POST', 'inspectors'):
        final Map b;
        try {
          b = jsonDecode(await req.readAsString()) as Map;
        } on Object {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        if (b['add'] is Map) return _json(200, await store.addInspector(id, b['add'] as Map, now));
        if (b['id'] is String && b['update'] is Map) {
          final u = b['update'] as Map;
          return _json(200, await store.updateInspector(b['id'] as String, {'stopped': ?u['stopped'], 'newCode': ?u['newCode']}, agency: id));
        }
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      case ('GET', 'photo') when parts.length == 4:
        final f = store.photo(id, parts[2], int.tryParse(parts[3]) ?? -1);
        if (f == null) break;
        return Response.ok(await f.readAsBytes(), headers: {'content-type': f.path.endsWith('png') ? 'image/png' : 'image/jpeg', 'cache-control': 'private, max-age=3600'});
    }
    throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
  }

  int _govMinute = 0;
  int _govFails = 0;

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

  /// رابط رجوع سناب بعد الموافقة (لازم يتسجل نفسه في تطبيق سناب).
  static const snapRedirect = 'https://hawat.id/api/ads/snap';

  double get _usdToSar => ((accounts?.settings['usdToSar'] as num?) ?? 3.75).toDouble();

  /// يسحب أرقام اليوم من المنصات المربوطة، وأمس كمان في أول ساعات اليوم (المنصات تكمّل أرقام أمس متأخر).
  Future<Map<String, String>> pullAds(DateTime now) async {
    final store = ads;
    if (store == null) return const {};
    final riyadh = now.toUtc().add(const Duration(hours: 3));
    final errors = await store.pull(SiteStats.dayOf(now), usdToSar: _usdToSar, now: now);
    if (riyadh.hour < 8) await store.pull(SiteStats.dayOf(now.subtract(const Duration(days: 1))), usdToSar: _usdToSar, now: now);
    return errors;
  }

  /// البريف اليومي ليوم [day] (بتوقيت السعودية): الإعلانات لكل منصة، والموقع بالساعة، والتسجيلات، والتطبيق والفلوس.
  Map<String, dynamic> brief(String day, DateTime now) {
    double r(num v) => double.parse(v.toStringAsFixed(2));
    String shift(int d) {
      final p = day.split('-').map(int.parse).toList();
      return DateTime.utc(p[0], p[1], p[2] + d).toIso8601String().substring(0, 10);
    }

    final adsDay = ads?.total(day, day) ?? {'platforms': {}, 'spendSar': 0, 'impressions': 0, 'clicks': 0};
    final rows = ads?.day(day) ?? const {};
    final web = site?.total(day, day) ?? {'visits': 0, 'unique': 0, 'src': {}, 'clicks': {}, 'hours': {}};
    final week = site?.total(shift(-6), day);
    String ksa(Object? at) => SiteStats.dayOf(DateTime.parse('$at'));
    final items = (waitlist?.view(now)['items'] as List? ?? const []).whereType<Map>().toList();
    final signups = items.where((e) => ksa(e['at']) == day).toList();
    final app = ledger?.summary('day', day, now);
    final spend = (adsDay['spendSar'] as num).toDouble();
    final visits = (web['visits'] as num).toInt();
    return {
      'day': day,
      'today': day == SiteStats.dayOf(now),
      'generated': now.toUtc().toIso8601String(),
      'ads': {
        ...adsDay,
        'rows': rows,
        'linked': ads?.keys.view() ?? const {},
        'cpcSar': (adsDay['clicks'] as num) > 0 ? r(spend / (adsDay['clicks'] as num)) : null,
      },
      if (ads?.tiktok(day) case final tt?)
        'tiktok': {
          ...tt,
          'goal': AdStore.tiktokGoal,
          // الزيادة: آخر رقم لهاليوم ناقص آخر رقم قبله.
          'gained': tt['day'] == day && ads!.tiktok(shift(-1)) != null ? (tt['followers'] as int) - (ads!.tiktok(shift(-1))!['followers'] as int) : null,
        },
      'site': web,
      'weekHours': week?['hours'] ?? const {},
      'signups': {
        'count': signups.length,
        'beta': signups.where((e) => e['beta'] == true).length,
        'total': items.length,
        'costSar': signups.isNotEmpty ? r(spend / signups.length) : null,
      },
      'costPerVisitSar': visits > 0 ? r(spend / visits) : null,
      if (app != null)
        'app': {
          for (final k in const ['newUsers', 'users', 'scans', 'newSubs', 'renewals', 'grossSar', 'incomeSar', 'claudeSar', 'expensesSar', 'netSar']) k: app[k],
        },
      // آخر 14 يوم: الصرف والزيارات والتسجيلات، للرسم.
      'series': [
        for (var i = -13; i <= 0; i++)
          () {
            final d = shift(i);
            return {
              'key': d,
              'spendSar': ads?.total(d, d)['spendSar'] ?? 0,
              'visits': site?.total(d, d)['visits'] ?? 0,
              'signups': items.where((e) => ksa(e['at']) == d).length,
            };
          }(),
      ],
    };
  }

  /// نص البريف لتليجرام. [full]: اليوم خلص (بريف الصبح عن أمس).
  String briefText(String day, DateTime now, {bool full = false}) {
    final b = brief(day, now);
    String n(Object? v) {
      final x = (v as num?) ?? 0;
      final s = x is int || x == x.roundToDouble() ? x.round().toString() : x.toStringAsFixed(2);
      return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }

    String sar(Object? v) => ((v as num?) ?? 0).toStringAsFixed(2);
    String hour(int h) => h == 0
        ? '12 الليل'
        : h < 12
        ? '$h الصبح'
        : h == 12
        ? '12 الظهر'
        : h < 16
        ? '${h - 12} العصر'
        : '${h - 12} المساء';
    final ad = b['ads'] as Map;
    final rows = (ad['rows'] as Map).cast<String, dynamic>();
    final linked = (ad['linked'] as Map).cast<String, dynamic>();
    final lines = <String>[
      '📊 بريف FISH ID: $day ${full ? '(اليوم كامل)' : '(لين الساعة ${now.toUtc().add(const Duration(hours: 3)).hour}:00)'}',
      '',
      '💰 الإعلانات: ${sar(ad['spendSar'])} ريال · ${n(ad['impressions'])} ظهور · ${n(ad['clicks'])} ضغطة',
    ];
    for (final p in AdStore.platforms) {
      final row = rows[p] as Map?;
      if (row != null) {
        lines.add('• ${AdStore.names[p]}: ${sar(row['spendSar'])} ريال، ${n(row['impressions'])} ظهور، ${n(row['clicks'])} ضغطة');
      } else if ((linked[p] as Map?)?['linked'] == true) {
        lines.add('• ${AdStore.names[p]}: ما فيه أرقام لهاليوم');
      }
    }
    final off = AdStore.platforms
        .where((p) => p != 'tiktok' && rows[p] == null && (linked[p] as Map?)?['linked'] != true)
        .map((p) => AdStore.names[p])
        .toList();
    if (off.isNotEmpty) lines.add('• غير مربوطة: ${off.join('، ')}');
    for (final e in linked.entries) {
      if ((e.value as Map)['ok'] == false) lines.add('🟠 تعذّر سحب ${AdStore.names[e.key]}: ${(e.value as Map)['error']}');
    }
    if (b['tiktok'] case final Map tt) {
      final g = tt['gained'] as int?;
      lines
        ..add('')
        ..add(
          '🎵 تيك توك: ${n(tt['followers'])} متابع${g == null ? '' : ' (${g >= 0 ? '+' : ''}$g اليوم)'} · باقي ${n(((tt['goal'] as int) - (tt['followers'] as int)).clamp(0, 1 << 30))} على ${n(tt['goal'])} · ${n(tt['likes'])} لايك',
        );
    }
    final web = b['site'] as Map;
    final src = ((web['src'] as Map).cast<String, int>().entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5);
    lines
      ..add('')
      ..add('🌐 الموقع: ${n(web['visits'])} زيارة من ${n(web['unique'])} زائر')
      ..add(src.isEmpty ? 'من وين: لا شيء' : 'من وين: ${src.map((e) => '${SiteStats.sourceName(e.key)} ${e.value}').join('، ')}');
    MapEntry<String, int>? peak(Map m) => m.isEmpty ? null : (m.cast<String, int>().entries.reduce((a, c) => c.value > a.value ? c : a));
    if (peak(web['hours'] as Map) case final p?) lines.add('⏰ أكثر ساعة اليوم: ${hour(int.parse(p.key))} (${p.value} زيارة)');
    if (peak(b['weekHours'] as Map) case final p?) lines.add('⏰ وقت الذروة آخر 7 أيام: ${hour(int.parse(p.key))} (${p.value} زيارة)');
    final s = b['signups'] as Map;
    lines
      ..add('')
      ..add('📝 تسجيلات «بلّغني»: +${s['count']} (المجموع ${s['total']})${(s['beta'] as int) > 0 ? '، منهم ${s['beta']} للتجربة' : ''}');
    if (b['app'] case final Map a) {
      lines.add('📱 التطبيق: مستخدمين جدد ${a['newUsers']} · فحوصات ${a['scans']} · اشتراكات جديدة ${a['newSubs']} · دخل ${sar(a['incomeSar'])} ريال');
    }
    lines.add(
      '💵 تكلفة الزيارة: ${b['costPerVisitSar'] == null ? '-' : '${sar(b['costPerVisitSar'])} ريال'} · تكلفة التسجيل: ${s['costSar'] == null ? '-' : '${sar(s['costSar'])} ريال'}',
    );
    return lines.join('\n');
  }

  /// ملخص اليوم للمالك: الفحوصات والتكلفة والمستخدمين والاشتراكات والتنبيهات المفتوحة. null إذا ما فيه حسابات.
  String? dailySummary(DateTime now, {bool withSite = true}) {
    final store = accounts;
    final web = withSite ? site?.summaryLines(now) ?? const <String>[] : const <String>[];
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
    if (wl != null) {
      lines.add('📝 «بلّغني بالإطلاق»: ${wl['count']} مسجل (اليوم +${wl['today']})، للتجربة المبكرة: أندرويد ${wl['betaAndroid']}، آيفون ${wl['betaIos']}');
    }
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
      // باقة المحلات من المتجر: سجل محل برمز للموظفين، وكل أجهزته على رصيد واحد.
      String? pool;
      if (plan == 'shop' && shops != null) {
        final other = shops!.shopOf(user);
        if (other != null && shops!.byId(other)?['owner'] != user) await _unlink(other, user);
        pool = await shops!.fromStore(user, until, now);
      }
      await store.update(user, now, plan: plan, until: until, source: 'store', pool: pool);
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

  int _collectFails = 0;
  int _collectMinute = 0;

  /// صفحة المصوّرين وطلباتها. المفتاح في `x-collector`، والمحاولات الغلط محدودة بالدقيقة.
  Future<Response> _collect(Request req, String path) async {
    final store = collectors;
    if (store == null || contrib == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    if (req.method == 'GET' && path == 'collect') {
      return Response.ok(
        collectPage,
        headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer'},
      );
    }
    if (req.method == 'GET' && path == 'collect/manifest.webmanifest') {
      // الأيقونة تفتح على نفس رابط المصوّر. المفتاح ينضاف بس إذا شكله صحيح.
      final k = req.url.queryParameters['k'] ?? '';
      return Response.ok(
        jsonEncode({
          'name': 'FISH ID · تصوير الأسماك',
          'short_name': 'FISH ID',
          'lang': 'ar',
          'dir': 'rtl',
          'start_url': CollectorStore.keyPattern.hasMatch(k) ? '/api/collect?k=$k' : '/api/collect',
          'scope': '/api/collect',
          'display': 'standalone',
          'background_color': '#0B2236',
          'theme_color': '#0B2236',
          'icons': [
            {'src': '/img/icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
            {'src': '/img/icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
          ],
        }),
        headers: {'content-type': 'application/manifest+json; charset=utf-8', 'cache-control': 'no-store'},
      );
    }
    final now = _clock();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (minute != _collectMinute) {
      _collectMinute = minute;
      _collectFails = 0;
    }
    if (_collectFails >= 20) throw const FishIdError('busy', 'محاولات كثيرة، حاول بعد دقيقة', status: 429);
    if (req.method == 'POST' && path == 'collect/signup') {
      // كل تسجيل يحسب من حد المحاولات بالدقيقة، عشان ما أحد يغرق القائمة.
      _collectFails++;
      final Map b;
      try {
        b = jsonDecode(await req.readAsString()) as Map;
      } on Object {
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      }
      if (b['consent'] != true) throw const FishIdError('contrib_consent', 'لازم توافق على الشروط');
      final key = await store.signup('${b['invite'] ?? ''}', '${b['name'] ?? ''}', '${b['city'] ?? ''}', '${b['contact'] ?? ''}', now);
      final c = store.find(key)!;
      _tell('collector:$key', '👤 مصوّر جديد سجّل: ${c['name']} (${c['city']})\nعدد المصوّرين: ${store.list().length}');
      return _json(200, {'key': key});
    }
    final key = req.headers['x-collector'] ?? '';
    final c = store.find(key);
    if (c == null) {
      _collectFails++;
      throw const FishIdError('collector', 'الرابط غير صالح، اطلب رابط جديد', status: 401);
    }
    switch ((req.method, path)) {
      case ('GET', 'collect/me'):
        return _json(200, {
          'name': c['name'],
          'city': c['city'],
          'joined': '${c['contact'] ?? ''}'.isNotEmpty,
          'fish': c['fish'] ?? 0,
          'today': store.today(c, now),
          'species': speciesNames,
        });
      case ('POST', 'collect/join'):
        final Map b;
        try {
          b = jsonDecode(await req.readAsString()) as Map;
        } on Object {
          throw const FishIdError('bad_request', 'الطلب غير صالح');
        }
        if (b['consent'] != true) throw const FishIdError('contrib_consent', 'لازم توافق على الشروط');
        await store.join(key, '${b['contact'] ?? ''}', now);
        return _json(200, {'ok': true});
      case ('POST', 'collect/upload'):
        if ('${c['contact'] ?? ''}'.isEmpty) throw const FishIdError('collector_join', 'سجّل جوالك أو إيميلك أول');
        final (photos, body) = await _readPhotos(req, max: CollectorStore.parts.length);
        if (photos.any((p) => p.mediaType == 'image/webp')) throw const FishIdError('fishid_type', 'نوع الصورة غير مدعوم، استخدم JPG أو PNG');
        final typed = '${body['name'] ?? ''}'.trim();
        if (typed.isEmpty || typed.length > 80) throw const FishIdError('bad_request', 'اكتب اسم السمكة');
        final species = '${body['species'] ?? ''}';
        if (species.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(species)) throw const FishIdError('bad_request', 'الطلب غير صالح');
        final items = body['images'] is List ? body['images'] as List : const [];
        final parts = [
          for (final (i, _) in photos.indexed)
            i < items.length && items[i] is Map && CollectorStore.parts.contains(items[i]['part']) ? '${items[i]['part']}' : 'other',
        ];
        final note = '${body['note'] ?? ''}'.trim();
        final id = await contrib!.save(photos, {
          'source': 'collector',
          'collector': c['name'],
          'city': c['city'],
          'typed_name': typed,
          'species': species,
          'species_confirmed': species.isNotEmpty,
          'parts': parts,
          'note': note.length > 200 ? note.substring(0, 200) : note,
          'days_since_catch': -1,
          'storage': parts.contains('ice') ? 'ice' : 'unknown',
          'predicted': const <String>[],
          'app_score': -1,
        }, now);
        await store.counted(key, photos.length, now);
        _tell(
          'collect:${c['name']}',
          '🐟 ${c['name']} (${c['city']}) رفع صور: $typed · ${photos.length} صور. اليوم: ${store.today(c, now)} سمكة.',
          every: const Duration(minutes: 30),
        );
        return _json(200, {'ok': true, 'id': id, 'fish': c['fish'], 'today': store.today(c, now)});
    }
    throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
  }

  // ───────────── المحلات ─────────────

  int get _shopPrice => (accounts?.settings['priceShop'] as num?)?.round() ?? 350;
  int get _shopCap => (accounts?.settings['shopCap'] as num?)?.round() ?? 300;
  int get _shopDevices => (accounts?.settings['shopDevices'] as num?)?.round() ?? 5;

  /// بيانات المحل للوحته (وللأدمن مع المفتاح والجوال).
  Map<String, dynamic> _shopView(String id, Map<String, dynamic> s, DateTime now, {bool admin = false}) {
    final store = accounts;
    return {
      'id': id,
      'name': s['name'],
      'kind': s['kind'],
      'city': s['city'],
      'phone': s['phone'],
      'email': s['email'],
      'cr': s['cr'],
      'join': s['join'],
      'created': s['created'],
      'until': s['until'],
      'active': ShopStore.active(s, now),
      'stopped': s['stopped'] == true,
      'used': ShopStore.used(s, now),
      'cap': _shopCap,
      'maxDevices': _shopDevices,
      'price': _shopPrice,
      'autoRenew': s['autoRenew'] == true,
      'card': s['card'],
      'canRenew': s['token'] != null,
      'renewError': s['renewError'],
      'devices': [
        for (final d in (s['devices'] as List).cast<String>()) {'id': d, 'lastScan': store?.find(d)?['lastScan'], 'scans': store?.find(d)?['scans'] ?? 0},
      ],
      'payments': [
        for (final p in (s['payments'] as List).reversed)
          {
            for (final k in const ['id', 'at', 'sar', 'method', 'card', 'until', 'kind']) k: (p as Map)[k],
          },
      ],
      if (admin) 'key': s['key'],
    };
  }

  /// يربط جهاز (رقم حساب التطبيق) بالمحل، فيصير على باقة المحل ويسحب من رصيده.
  Future<void> _link(String id, Map<String, dynamic> shop, String account) async {
    final store = accounts;
    if (store == null) throw const FishIdError('unavailable', 'الخدمة مو متاحة الحين', status: 503);
    if (!AccountStore.idPattern.hasMatch(account)) throw const FishIdError('bad_request', 'رقم الحساب غير صحيح. انسخه من قائمة التطبيق «رقم حسابك»');
    final devices = (shop['devices'] as List).cast<String>();
    if (devices.contains(account)) return;
    final other = shops!.shopOf(account);
    if (other != null) throw const FishIdError('shop_taken', 'هذا الجوال مربوط بمحل ثاني. يفكّه صاحب المحل الأول من لوحته');
    if (devices.length >= _shopDevices) throw FishIdError('shop_full', 'وصلت الحد ($_shopDevices جوالات). شيل جهاز قديم وأضف الجديد');
    final now = _clock();
    final a = store.find(account);
    if (a != null && a['owner'] == true) throw const FishIdError('bad_request', 'هذا حساب المالك');
    shop['devices'] = [...devices, account];
    await shops!.save();
    await store.update(account, now, plan: 'shop', source: 'shop', pool: id, by: 'shop:${shop['name']}');
    _tell('shopdev:$id', '📱 المحل «${shop['name']}» ربط جهاز. الأجهزة: ${(shop['devices'] as List).length}', every: const Duration(minutes: 30));
  }

  Future<void> _unlink(String id, String account) async {
    final shop = shops!.byId(id);
    if (shop == null) return;
    if (shop['owner'] == account && accounts?.find(account)?['source'] == 'store') {
      throw const FishIdError('bad_request', 'هذا جوال صاحب الاشتراك، ما ينشال');
    }
    shop['devices'] = [...(shop['devices'] as List).where((d) => d != account)];
    await shops!.save();
    final a = accounts?.find(account);
    if (a != null && a['pool'] == id) await accounts!.update(account, _clock(), plan: 'free', pool: '', by: 'shop:${shop['name']}');
  }

  /// يتأكد من عملية الدفع عند ميسر نفسه ويفعّل المحل. يرجّع ok أو dup أو سبب الرفض.
  /// ما نصدّق أي شيء من المتصفح أو من الحدث: نجيب العملية بالمفتاح السري ونتأكد إنها مدفوعة بالمبلغ والعملة ورقم المحل.
  Future<String> _applyPayment(String paymentId, {String? expectShop}) async {
    final g = gateway, store = shops;
    if (g == null || store == null) return 'off';
    if (!RegExp(r'^[0-9a-fA-F-]{20,64}$').hasMatch(paymentId)) return 'bad_id';
    final p = await g.fetch(paymentId);
    if (p == null) return 'unreachable';
    final meta = p['metadata'] is Map ? p['metadata'] as Map : const {};
    final id = '${meta['shop'] ?? ''}';
    final shop = store.byId(id);
    if (shop == null || (expectShop != null && expectShop != id)) return 'wrong_shop';
    if (p['status'] != 'paid') {
      return 'not_paid:${(p['source'] is Map ? (p['source'] as Map)['message'] : null) ?? p['status']}';
    }
    if (p['currency'] != 'SAR' || p['amount'] != _shopPrice * 100) return 'wrong_amount';
    if (ShopStore.hasPayment(shop, paymentId)) return 'dup';
    final now = _clock();
    final src = p['source'] is Map ? (p['source'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final type = '${src['type'] ?? ''}';
    final number = '${src['number'] ?? ''}';
    final card = type == 'creditcard' ? '${src['company'] ?? 'بطاقة'} •••• ${number.length >= 4 ? number.substring(number.length - 4) : ''}' : type;
    final token = '${src['token'] ?? ''}';
    final renewal = (shop['payments'] as List).isNotEmpty;
    final until = await store.paid(
      id,
      {
        'id': paymentId,
        'at': now.toUtc().toIso8601String(),
        'sar': (p['amount'] as num) / 100,
        'method': type,
        'card': card,
        'kind': meta['renew'] == 'yes' ? 'auto' : (renewal ? 'renew' : 'first'),
      },
      now,
      token: token.startsWith('token_') ? token : null,
      card: token.startsWith('token_') ? card : null,
    );
    await ledger?.recordShop(p, shop: id, test: g.test, renewal: renewal, now: now);
    final test = g.test ? ' (تجربة)' : '';
    _tell(
      'shoppay:$paymentId',
      '${renewal ? '🔁 تجديد باقة محل' : '🏪 محل جديد اشترك أونلاين'}$test: ${shop['name']} (${shop['city']}) · $_shopPrice ر.س\n'
          'الجوال: ${shop['phone']} · ينتهي ${until.toIso8601String().substring(0, 10)}',
    );
    return 'ok';
  }

  int _shopFails = 0;
  int _shopMinute = 0;

  /// صفحة المحلات ولوحة كل محل.
  Future<Response> _shop(Request req, String path) async {
    final store = shops;
    if (store == null || accounts == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    const html = {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer'};
    if (req.method == 'GET' && path == 'shop') return Response.ok(shopPage, headers: html);
    final now = _clock();
    final q = req.url.queryParameters;
    if (req.method == 'GET' && path == 'shop/config') {
      return _json(200, {
        'price': _shopPrice,
        'cap': _shopCap,
        'devices': _shopDevices,
        'pay': gateway == null ? null : {'key': gateway!.publishableKey, 'methods': gateway!.methods, 'test': gateway!.test},
      });
    }
    // ميسر يرجّع المتصفح هنا بعد الدفع (أو بعد 3D Secure) ومعه رقم العملية.
    if (req.method == 'GET' && path == 'shop/paid') {
      final key = q['k'] ?? '';
      final found = store.byKey(key);
      var result = 'bad';
      if (found != null) {
        try {
          result = await _applyPayment(q['id'] ?? '', expectShop: found.$1);
        } on Object catch (e) {
          stderr.writeln('shop paid: $e');
          result = 'unreachable';
        }
      }
      final ok = result == 'ok' || result == 'dup';
      final msg = result.startsWith('not_paid:') ? result.substring(9) : (ok ? '' : result);
      final to =
          '/api/shop?k=${Uri.encodeQueryComponent(key)}&r=${ok ? 'ok' : 'fail'}${msg.isEmpty ? '' : '&m=${Uri.encodeQueryComponent(msg.length > 120 ? msg.substring(0, 120) : msg)}'}';
      return Response(303, headers: {'location': to, 'cache-control': 'no-store', 'referrer-policy': 'no-referrer'});
    }
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (minute != _shopMinute) {
      _shopMinute = minute;
      _shopFails = 0;
    }
    if (_shopFails >= 20) throw const FishIdError('busy', 'محاولات كثيرة، حاول بعد دقيقة', status: 429);
    Future<Map> body() async {
      try {
        final text = await req.readAsString();
        if (text.length > 4000) throw const FormatException();
        return jsonDecode(text) as Map;
      } on Object {
        throw const FishIdError('bad_request', 'الطلب غير صالح');
      }
    }

    if (req.method == 'POST' && path == 'shop/start') {
      // كل تسجيل يحسب من حد الدقيقة، عشان ما أحد يغرق القائمة.
      _shopFails++;
      final b = await body();
      if (b['consent'] != true) throw const FishIdError('contrib_consent', 'لازم توافق على الشروط');
      final shop = await store.create(b, now);
      _tell(
        'shopnew:${shop['id']}',
        '📝 محل سجّل في باقة المحلات${gateway == null ? ' (الدفع الإلكتروني مو مفعّل، كلّمه للتحويل)' : ' وراح يدفع'}: ${shop['name']} · ${ShopStore.kindNames[shop['kind']]} · ${shop['city']}\n'
            'الجوال: ${shop['phone']}',
      );
      return _json(200, {'key': shop['key']});
    }
    final found = store.byKey(req.headers['x-shop'] ?? '');
    if (found == null) {
      _shopFails++;
      throw const FishIdError('shop_key', 'رابط لوحة المحل غير صالح. كلّمنا واتساب ونرسل لك الرابط', status: 401);
    }
    final (id, shop) = found;
    switch ((req.method, path)) {
      case ('GET', 'shop/me'):
        return _json(200, _shopView(id, shop, now));
      case ('POST', 'shop/devices'):
        final b = await body();
        if (b['add'] is String) await _link(id, shop, (b['add'] as String).trim());
        if (b['remove'] is String) await _unlink(id, b['remove'] as String);
        return _json(200, _shopView(id, shop, now));
      case ('POST', 'shop/settings'):
        final b = await body();
        if (b['autoRenew'] is bool) shop['autoRenew'] = b['autoRenew'];
        if (b['forgetCard'] == true) {
          shop.remove('token');
          shop.remove('card');
        }
        await store.save();
        return _json(200, _shopView(id, shop, now));
      case ('POST', 'shop/check'):
        // الصفحة تبلّغ عن عملية بعد الدفع مباشرة (Apple Pay ما يرجع على رابط)، ونتأكد منها عند ميسر.
        final b = await body();
        final r = await _applyPayment('${b['id'] ?? ''}', expectShop: id);
        return _json(200, {'result': r, ..._shopView(id, shop, now)});
    }
    throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
  }

  /// أحداث ميسر (payment_paid وغيرها). نتأكد من الرمز السري إذا مضبوط، وبعدها نجيب العملية من ميسر نفسه.
  Future<Response> _moyasarHook(Request req) async {
    final g = gateway;
    if (g == null) throw const FishIdError('not_found', 'المسار غير موجود', status: 404);
    final Map b;
    try {
      b = jsonDecode(await req.readAsString()) as Map;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    if (g.webhookSecret.isNotEmpty && !_same('${b['secret_token'] ?? ''}', g.webhookSecret)) {
      throw const FishIdError('unauthorized', 'الرمز غير صحيح', status: 401);
    }
    final data = b['data'] is Map ? b['data'] as Map : const {};
    if ('${b['type']}' == 'payment_paid' && data['id'] is String) {
      final r = await _applyPayment(data['id'] as String);
      if (r != 'ok' && r != 'dup') stderr.writeln('moyasar hook ${data['id']}: $r');
    }
    return _json(200, {'ok': true});
  }

  /// يمر على المحلات كل ساعة: يجدد بالبطاقة المحفوظة قبل الانتهاء بيوم، ويذكّر المالك بالمحلات اللي بتنتهي بدون تجديد.
  Future<void> renewShops(DateTime now) async {
    final store = shops, g = gateway;
    if (store == null) return;
    for (final e in store.entries.toList()) {
      final (id, s) = (e.key, e.value);
      final until = DateTime.tryParse('${s['until']}');
      // اشتراكات المتجر يجددها المتجر نفسه.
      if (until == null || s['stopped'] == true || s['store'] == true) continue;
      final left = until.difference(now);
      // بعد 3 أيام من الانتهاء نوقف المحاولة.
      if (left < const Duration(days: -3) || left > const Duration(days: 3)) continue;
      final canCharge = g != null && s['autoRenew'] == true && s['token'] is String;
      if (canCharge && left < const Duration(hours: 24)) {
        final last = DateTime.tryParse('${s['renewAt']}');
        final tries = s['renewTries'] as int? ?? 0;
        if (tries >= 4 || (last != null && now.difference(last) < const Duration(hours: 6))) continue;
        s['renewAt'] = now.toUtc().toIso8601String();
        s['renewTries'] = tries + 1;
        await store.save();
        Map<String, dynamic>? p;
        try {
          p = await g.charge({
            'amount': _shopPrice * 100,
            'currency': 'SAR',
            'description': 'FISH ID - باقة المحلات - ${s['name']}',
            'callback_url': 'https://hawat.id/api/shop/paid?k=${s['key']}',
            'source': {'type': 'token', 'token': s['token']},
            'metadata': {'shop': id, 'renew': 'yes'},
          });
        } on Object catch (err) {
          stderr.writeln('shop renew $id: $err');
        }
        final pid = p?['id'];
        final r = p?['status'] == 'paid' && pid is String ? await _applyPayment(pid) : 'failed';
        if (r == 'ok' || r == 'dup') continue;
        final why = '${(p?['source'] is Map ? (p!['source'] as Map)['message'] : null) ?? p?['message'] ?? p?['status'] ?? 'ما رد ميسر'}';
        s['renewError'] = why;
        await store.save();
        _tell(
          'shoprenew:$id:${s['renewTries']}',
          '⚠️ ما قدرنا نجدد باقة المحل «${s['name']}» تلقائيًا (محاولة ${s['renewTries']} من 4): $why\n'
              'كلّمه يجدد من لوحته: ${s['phone']}',
        );
        continue;
      }
      // بدون تجديد تلقائي: تذكير للمالك مرة وحدة قبل الانتهاء بـ 3 أيام، عشان يكلّمه.
      if (!canCharge && s['reminded'] != s['until'] && left > Duration.zero) {
        s['reminded'] = s['until'];
        await store.save();
        _tell('shopremind:$id', '⏰ باقة المحل «${s['name']}» تنتهي ${'${s['until']}'.substring(0, 10)} وما عنده تجديد تلقائي. كلّمه: ${s['phone']}');
      }
    }
  }

  void _limit() {
    final now = _clock().millisecondsSinceEpoch ~/ 60000;
    if (now != _minute) {
      _minute = now;
      _count = 0;
    }
    if (++_count > perMinute) throw const FishIdError('busy', 'الخدمة مشغولة، حاول بعد دقيقة', status: 429);
  }

  Future<(List<Photo>, Map<String, dynamic>)> _readPhotos(Request req, {int max = maxPhotos}) async {
    final Map<String, dynamic> body;
    try {
      // base64 يكبّر الحجم الثلث، فالحد هنا أكبر من حد الصورة.
      final raw = await req.read().fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) {
        if (b.length + chunk.length > maxBytes * max * 1.4) throw const FishIdError('fishid_size', 'الصورة كبيرة، صغّرها وحاول مرة ثانية', status: 413);
        return b..add(chunk);
      });
      body = jsonDecode(utf8.decode(raw.takeBytes())) as Map<String, dynamic>;
    } on FishIdError {
      rethrow;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    final list = body['images'] is List ? body['images'] as List : [body];
    if (list.isEmpty || list.length > max) throw FishIdError('fishid_count', 'أرسل من صورة إلى $max صور لنفس السمكة');
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
