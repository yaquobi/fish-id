import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:fish_id_server/refs.dart';
import 'package:shelf/shelf_io.dart' as io;

/// الإعدادات من متغيرات البيئة (ملف .env في docker compose):
/// ANTHROPIC_API_KEY إلزامي، و FISHID_MODEL و FISHID_EFFORT و FISHID_PROMPT و FISHID_PER_MINUTE و PORT اختيارية.
/// FISHID_ADMIN_TOKEN يفتح لوحة الأدمن. FISHID_RC_KEY مفتاح RevenueCat العام (نفس اللي في التطبيق) للتأكد من الاشتراكات.
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

  final app = FishIdApp(
    identify: ai?.identify,
    // مجلد مساهمات المستخدمين (مربوط بـ data/contrib على السيرفر في docker-compose).
    contrib: ContribStore.open(env['FISHID_CONTRIB'] ?? 'contrib'),
    // الحسابات والفحوصات والإعدادات (مربوطة بـ data/accounts على السيرفر).
    accounts: AccountStore.open(env['FISHID_ACCOUNTS'] ?? 'accounts'),
    adminToken: env['FISHID_ADMIN_TOKEN'] ?? '',
    revenueCat: _revenueCat(env['FISHID_RC_KEY'] ?? 'goog_hbGYTrOvVqpREIzVQGfbduJsozZ'),
    speciesNames: {
      for (final s in data['species'] as List)
        (s['id'] as String).split('-').last: '${[s['red'], s['gulf'], s['sci']].firstWhere((n) => '${n ?? ''}'.isNotEmpty)}'.split('|').first.trim(),
    },
    perMinute: int.tryParse(env['FISHID_PER_MINUTE'] ?? '') ?? 30,
  );
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FishId: يستمع على المنفذ ${server.port}، ${(data['species'] as List).length} نوعًا');
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
