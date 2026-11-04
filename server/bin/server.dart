import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/book.dart';
import 'package:fish_id_server/collectors.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:fish_id_server/gov.dart';
import 'package:fish_id_server/ledger.dart';
import 'package:fish_id_server/refs.dart';
import 'package:fish_id_server/ads.dart';
import 'package:fish_id_server/basma.dart';
import 'package:fish_id_server/basma_api.dart';
import 'package:fish_id_server/mailer.dart';
import 'package:fish_id_server/shops.dart';
import 'package:fish_id_server/site.dart';
import 'package:fish_id_server/staff.dart';
import 'package:fish_id_server/waitlist.dart';
import 'package:shelf/shelf_io.dart' as io;

/// الإعدادات من متغيرات البيئة (ملف .env في docker compose):
/// ANTHROPIC_API_KEY إلزامي، و FISHID_MODEL و FISHID_EFFORT و FISHID_PROMPT و FISHID_PER_MINUTE و PORT اختيارية.
/// FISHID_ADMIN_TOKEN يفتح لوحة الأدمن. FISHID_RC_KEY مفتاح RevenueCat العام (نفس اللي في التطبيق) للتأكد من الاشتراكات.
/// FISHID_TELEGRAM_TOKEN و FISHID_TELEGRAM_CHAT لتنبيهات المالك على تليجرام (يضبطها: bash server/telegram.sh).
/// FISHID_MOYASAR_PK و FISHID_MOYASAR_SK مفاتيح ميسر لدفع المحلات (hawat.id/shop)، و FISHID_MOYASAR_WEBHOOK الرمز السري للأحداث،
/// و FISHID_MOYASAR_METHODS طرق الدفع (creditcard,applepay,stcpay). بدون المفاتيح الصفحة تسجّل الطلب وتحوّل للواتساب.
/// FISHID_NTFY_TOPIC لنفس التنبيهات كإشعارات على الجوال عن طريق ntfy (يضبطها: bash server/ntfy.sh).
Future<void> main() async {
  final env = Platform.environment;
  final key = env['ANTHROPIC_API_KEY'] ?? '';
  final dataPath = env['KSAFISH_JSON'] ?? 'data/ksafish.json';
  final data = jsonDecode(await File(dataPath).readAsString()) as Map<String, dynamic>;

  final ai = key.isEmpty
      ? null
      : FishIdAi(
          key: key,
          speciesList: FishIdAi.speciesListFrom(data),
          model: env['FISHID_MODEL'] ?? 'claude-opus-5-5',
          effort: env['FISHID_EFFORT'] ?? 'high',
          prompt: env['FISHID_PROMPT'] ?? 'v1',
          // الصور المرجعية للأنواع المتشابهة، تنبنى بـ bash server/eval.sh refs. إذا المجلد فاضي تنطفي المرحلة الثانية.
          refs: RefLibrary.load(env['FISHID_REFS'] ?? 'refs', data),
          refsBelow: int.tryParse(env['FISHID_REFS_BELOW'] ?? '') ?? 80,
          fast: env['FISHID_SPEED'] == 'fast',
        );
  if (ai == null) stderr.writeln('FishId: ANTHROPIC_API_KEY غير موجود، الخدمة ترجع «غير مفعّلة».');

  // الحسابات والفحوصات والإعدادات (مربوطة بـ data/accounts على السيرفر)، والمحاسبة في نفس المجلد.
  final accounts = AccountStore.open(env['FISHID_ACCOUNTS'] ?? 'accounts');
  // بصمة في الظل (خدمة basma في docker-compose). بدون الرابط ما تشتغل.
  final basma = accounts == null || (env['FISHID_BASMA_URL'] ?? '').isEmpty ? null : BasmaShadow.http(accounts.dir, Uri.parse(env['FISHID_BASMA_URL']!));
  final notify = _both(_telegram(env['FISHID_TELEGRAM_TOKEN'] ?? '', env['FISHID_TELEGRAM_CHAT'] ?? ''), _ntfy(env['FISHID_NTFY_TOPIC'] ?? ''));
  final app = FishIdApp(
    identify: ai?.identify,
    box: ai?.box,
    // مجلد مساهمات المستخدمين (مربوط بـ data/contrib على السيرفر في docker-compose).
    contrib: ContribStore.open(env['FISHID_CONTRIB'] ?? 'contrib'),
    collectors: accounts == null ? null : CollectorStore.open(accounts.dir),
    // أرشيف كتاب أسماك البحر الأحمر (data/book/archive على السيرفر)، يبنيه tool/book_extract.py.
    book: BookArchive.open(env['FISHID_BOOK'] ?? 'book', {for (final s in data['species'] as List) '${s['sci']}'.toLowerCase().trim(): s['id'] as String}),
    accounts: accounts,
    ledger: accounts == null ? null : Ledger.open(accounts),
    staff: accounts == null ? null : StaffStore.open(accounts.dir),
    site: accounts == null ? null : SiteStats.open(accounts.dir),
    waitlist: accounts == null ? null : Waitlist.open(accounts.dir),
    ads: accounts == null ? null : AdStore.open(accounts.dir),
    shops: accounts == null ? null : ShopStore.open(accounts.dir),
    gov: accounts == null ? null : GovStore.open(accounts.dir),
    gateway: _moyasar(env),
    basma: basma,
    // بصمة API للعملاء (hawat.id/api/basma/v1/identify) على نفس الخدمة.
    basmaApi: basma == null ? null : BasmaApi(BasmaClients.open(accounts!.dir), basma.rank, BasmaApi.speciesFrom(data), notify: notify, mail: _mailer(env)?.send),
    adminToken: env['FISHID_ADMIN_TOKEN'] ?? '',
    revenueCat: _revenueCat(env['FISHID_RC_KEY'] ?? 'goog_hbGYTrOvVqpREIzVQGfbduJsozZ'),
    speciesNames: {
      for (final s in data['species'] as List) (s['id'] as String).split('-').last: '${[s['red'], s['gulf'], s['sci']].firstWhere((n) => '${n ?? ''}'.isNotEmpty)}'.split('|').first.trim(),
    },
    perMinute: int.tryParse(env['FISHID_PER_MINUTE'] ?? '') ?? 30,
    notify: notify,
  );
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FishId: يستمع على المنفذ ${server.port}، ${(data['species'] as List).length} نوعًا');

  // أرقام الإعلانات: سحب من المنصات كل ساعة (الدقيقة 50)، وقبل كل بريف.
  if (app.ads != null) {
    unawaited(app.pullAds(DateTime.now()));
  }
  if (notify != null) {
    notify('✅ FISH ID: السيرفر اشتغل${ai == null ? '، لكن مفتاح Claude ناقص والفحوصات متوقفة' : ''}.');
  }
  // البريف اليومي على تليجرام: 6 الصبح عن أمس كامل، و9 الليل عن اليوم لين الحين (بتوقيت السعودية).
  final sent = <String>{};
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final now = DateTime.now();
    final riyadh = now.toUtc().add(const Duration(hours: 3));
    final day = riyadh.toIso8601String().substring(0, 10);
    if (app.ads != null && riyadh.minute == 50) await app.pullAds(now);
    // تجديد باقات المحلات بالبطاقة المحفوظة، والتذكير بالمنتهية (كل ساعة، الدقيقة 20).
    if (riyadh.minute == 20) await app.renewShops(now);
    if (notify == null || (riyadh.hour != 6 && riyadh.hour != 21) || !sent.add('$day-${riyadh.hour}')) return;
    if (app.ads != null) await app.pullAds(now);
    if (riyadh.hour == 6) {
      notify(app.briefText(SiteStats.dayOf(now.subtract(const Duration(days: 1))), now, full: true));
    } else {
      notify(app.briefText(day, now));
      // ملخص التطبيق والتنبيهات المفتوحة (رصيد Claude، فواتير) يبقى الساعة 9.
      if (app.dailySummary(now, withSite: false) case final String text) notify(text);
    }
  });
}

/// يرسل التنبيه لكل القنوات المضبوطة، أو null إذا ما فيه ولا وحدة.
Notify? _both(Notify? a, Notify? b) => a == null
    ? b
    : b == null
    ? a
    : (text) {
        a(text);
        b(text);
      };

/// إشعار على جوال المالك عن طريق ntfy.sh: يفتح رابط الموضوع مرة وحدة ويثبته على الشاشة الرئيسية أو في تطبيق ntfy.
/// اسم الموضوع عشوائي وطويل، وهو اللي يحمي الإشعارات، فما ينكتب في المستودع.
Notify? _ntfy(String topic) {
  if (topic.isEmpty) return null;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  return (text) => unawaited(() async {
    try {
      final req = await http.postUrl(Uri.https('ntfy.sh', '/$topic'));
      req.headers
        ..set('title', 'FISH ID')
        ..set('tags', text.startsWith('🔴') ? 'rotating_light' : 'fish')
        ..set('priority', text.startsWith('🔴') ? '5' : '3')
        ..contentType = ContentType('text', 'plain', charset: 'utf-8');
      req.add(utf8.encode(text));
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode != 200) stderr.writeln('FishId: ntfy رد ${res.statusCode}');
    } on Object catch (e) {
      stderr.writeln('FishId: تعذّر إرسال إشعار ntfy: $e');
    }
  }());
}

/// يرسل التنبيه لمحادثة المالك في تليجرام بدون ما ينتظره أحد. أي خطأ ينكتب في السجل بس.
Notify? _telegram(String token, String chat) {
  if (token.isEmpty || chat.isEmpty) return null;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  return (text) => unawaited(() async {
    try {
      final req = await http.postUrl(Uri.https('api.telegram.org', '/bot$token/sendMessage'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'chat_id': chat, 'text': text, 'disable_web_page_preview': true}));
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode != 200) stderr.writeln('FishId: تليجرام رد ${res.statusCode}');
    } on Object catch (e) {
      stderr.writeln('FishId: تعذّر الإرسال لتليجرام: $e');
    }
  }());
}

/// يسأل RevenueCat عن المشترك بالمفتاح العام، مثل ما يسوي التطبيق. المفتاح العام يقرأ بيانات المشترك بس.
SubscriberLookup? _revenueCat(String key) {
  if (key.isEmpty) return null;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  return (user) async {
    try {
      final req = await http.getUrl(Uri.https('api.revenuecat.com', '/v1/subscribers/${Uri.encodeComponent(user)}'));
      req.headers
        ..set('authorization', 'Bearer $key')
        ..set('x-platform', 'android');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        stderr.writeln('FishId: RevenueCat رد ${res.statusCode} للحساب $user');
        return null;
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } on Object catch (e) {
      stderr.writeln('FishId: تعذّر الاتصال بـ RevenueCat: $e');
      return null;
    }
  };
}

/// بوابة ميسر بالمفتاح السري (Basic auth، المفتاح اسم المستخدم وكلمة السر فاضية). null إذا المفاتيح ناقصة.
Gateway? _moyasar(Map<String, String> env) {
  final pk = env['FISHID_MOYASAR_PK'] ?? '', sk = env['FISHID_MOYASAR_SK'] ?? '';
  if (!pk.startsWith('pk_') || !sk.startsWith('sk_')) return null;
  if (pk.startsWith('pk_test') != sk.startsWith('sk_test')) {
    stderr.writeln('FishId: مفاتيح ميسر وحدة تجربة ووحدة حقيقية، الدفع متوقف.');
    return null;
  }
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final auth = 'Basic ${base64Encode(utf8.encode('$sk:'))}';
  Future<Map<String, dynamic>?> send(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      final req = await http.openUrl(method, Uri.https('api.moyasar.com', path));
      req.headers.set('authorization', auth);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 500) {
        stderr.writeln('FishId: ميسر رد ${res.statusCode}');
        return null;
      }
      final out = jsonDecode(text);
      return out is Map ? out.cast<String, dynamic>() : null;
    } on Object catch (e) {
      stderr.writeln('FishId: تعذّر الاتصال بميسر: $e');
      return null;
    }
  }

  final methods = (env['FISHID_MOYASAR_METHODS'] ?? 'creditcard').split(',').map((m) => m.trim()).where({'creditcard', 'applepay', 'stcpay'}.contains).toList();
  return Gateway(
    publishableKey: pk,
    webhookSecret: env['FISHID_MOYASAR_WEBHOOK'] ?? '',
    methods: methods.isEmpty ? const ['creditcard'] : methods,
    fetch: (id) => send('GET', '/v1/payments/${Uri.encodeComponent(id)}'),
    charge: (body) => send('POST', '/v1/payments', body),
  );
}

/// إيميلات الخادم (مفاتيح بصمة). FISHID_SMTP_HOST مثل smtp-relay.gmail.com (Google Workspace يسمح لعنوان السيرفر بدون كلمة سر)،
/// و FISHID_SMTP_FROM المرسل (info@hawat.id)، واختياري FISHID_SMTP_PORT و FISHID_SMTP_USER و FISHID_SMTP_PASS.
Mailer? _mailer(Map<String, String> env) {
  final host = env['FISHID_SMTP_HOST'] ?? '';
  if (host.isEmpty) return null;
  return Mailer(
    host: host,
    port: int.tryParse(env['FISHID_SMTP_PORT'] ?? '') ?? 465,
    from: env['FISHID_SMTP_FROM'] ?? 'info@hawat.id',
    fromName: 'بصمة · حوات',
    user: env['FISHID_SMTP_USER'] ?? '',
    pass: env['FISHID_SMTP_PASS'] ?? '',
  );
}
