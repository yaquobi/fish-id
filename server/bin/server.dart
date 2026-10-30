import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:fish_id_server/ledger.dart';
import 'package:fish_id_server/refs.dart';
import 'package:fish_id_server/site.dart';
import 'package:fish_id_server/staff.dart';
import 'package:fish_id_server/waitlist.dart';
import 'package:shelf/shelf_io.dart' as io;

/// الإعدادات من متغيرات البيئة (ملف .env في docker compose):
/// ANTHROPIC_API_KEY إلزامي، و FISHID_MODEL و FISHID_EFFORT و FISHID_PROMPT و FISHID_PER_MINUTE و PORT اختيارية.
/// FISHID_ADMIN_TOKEN يفتح لوحة الأدمن. FISHID_RC_KEY مفتاح RevenueCat العام (نفس اللي في التطبيق) للتأكد من الاشتراكات.
/// FISHID_TELEGRAM_TOKEN و FISHID_TELEGRAM_CHAT لتنبيهات المالك على تليجرام (يضبطها: bash server/telegram.sh).
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
        );
  if (ai == null) stderr.writeln('FishId: ANTHROPIC_API_KEY غير موجود، الخدمة ترجع «غير مفعّلة».');

  // الحسابات والفحوصات والإعدادات (مربوطة بـ data/accounts على السيرفر)، والمحاسبة في نفس المجلد.
  final accounts = AccountStore.open(env['FISHID_ACCOUNTS'] ?? 'accounts');
  final app = FishIdApp(
    identify: ai?.identify,
    // مجلد مساهمات المستخدمين (مربوط بـ data/contrib على السيرفر في docker-compose).
    contrib: ContribStore.open(env['FISHID_CONTRIB'] ?? 'contrib'),
    accounts: accounts,
    ledger: accounts == null ? null : Ledger.open(accounts),
    staff: accounts == null ? null : StaffStore.open(accounts.dir),
    site: accounts == null ? null : SiteStats.open(accounts.dir),
    waitlist: accounts == null ? null : Waitlist.open(accounts.dir),
    adminToken: env['FISHID_ADMIN_TOKEN'] ?? '',
    revenueCat: _revenueCat(env['FISHID_RC_KEY'] ?? 'goog_hbGYTrOvVqpREIzVQGfbduJsozZ'),
    speciesNames: {
      for (final s in data['species'] as List)
        (s['id'] as String).split('-').last: '${[s['red'], s['gulf'], s['sci']].firstWhere((n) => '${n ?? ''}'.isNotEmpty)}'.split('|').first.trim(),
    },
    perMinute: int.tryParse(env['FISHID_PER_MINUTE'] ?? '') ?? 30,
    notify: _both(_telegram(env['FISHID_TELEGRAM_TOKEN'] ?? '', env['FISHID_TELEGRAM_CHAT'] ?? ''), _ntfy(env['FISHID_NTFY_TOPIC'] ?? '')),
  );
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FishId: يستمع على المنفذ ${server.port}، ${(data['species'] as List).length} نوعًا');

  final notify = app.notify;
  if (notify != null) {
    notify('✅ FISH ID: السيرفر اشتغل${ai == null ? '، لكن مفتاح Claude ناقص والفحوصات متوقفة' : ''}.');
    // ملخص يومي الساعة 9 مساءً بتوقيت السعودية (6 مساءً UTC).
    var sentOn = '';
    Timer.periodic(const Duration(minutes: 1), (_) {
      final riyadh = DateTime.now().toUtc().add(const Duration(hours: 3));
      final day = riyadh.toIso8601String().substring(0, 10);
      if (riyadh.hour != 21 || sentOn == day) return;
      sentOn = day;
      if (app.dailySummary(DateTime.now()) case final String text) notify(text);
    });
  }
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
