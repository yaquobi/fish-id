import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
  const user = 'u_abcdefghijklmnop1234';
  late Directory dir;
  late DateTime t;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('acc');
    t = DateTime.utc(2026, 10, 28, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // يحاكي Claude: يكتب استهلاكه في الـ Zone مثل claude.dart ويرجّع نتيجة فيها نوع.
  Future<String> fakeIdentify(List<Photo> _) async {
    (Zone.current[usageKey] as List<Map<String, dynamic>>?)?.add({'model': 'claude-opus-5-5', 'input_tokens': 2000, 'output_tokens': 3000, 'cache_read_input_tokens': 25000});
    return '{"candidates":[{"id":"0408","confidence":71}]}';
  }

  FishIdApp app({String admin = 'secret-token', String rc = 'rc-secret'}) => FishIdApp(
    identify: fakeIdentify,
    accounts: AccountStore.open(dir.path),
    adminToken: admin,
    revenueCatSecret: rc,
    clock: () => t,
  );

  Future<Response> scan(FishIdApp a, {String? id = user}) async => a.handler(
    Request('POST', Uri.parse('http://x/api/fishId/identify'), body: jsonEncode({'image': jpeg, 'mediaType': 'image/jpeg'}), headers: {'x-fishid-user': ?id}),
  );

  Future<Response> admin(FishIdApp a, String path, {Object? body, String token = 'secret-token'}) async => a.handler(
    Request(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://x/api/admin/$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {'authorization': 'Bearer $token'},
    ),
  );

  test('gives 3 free scans per account, then asks to subscribe', () async {
    final a = app();
    final left = <String?>[];
    for (var i = 0; i < 3; i++) {
      final r = await scan(a);
      expect(r.statusCode, 200);
      left.add(r.headers['x-fishid-remaining']);
    }
    expect(left, ['2', '1', '0']);
    final r = await scan(a);
    expect(r.statusCode, 402);
    expect(jsonDecode(await r.readAsString())['code'], 'quota');
    // التطبيقات القديمة بدون رقم حساب تشتغل لين نفعّل requireAccount.
    expect((await scan(a, id: null)).statusCode, 200);
  });

  test('records the cost of every scan and shows it in the admin stats', () async {
    final a = app();
    await scan(a);
    await scan(a, id: null);
    final s = jsonDecode(await (await admin(a, 'stats')).readAsString());
    expect(s['scansToday'], 2);
    expect(s['users'], 1);
    // 2000×4 + 3000×20 + 25000×0.2 = 73000 دولار لكل مليون = 0.073 دولار للفحص.
    expect((s['costPerScanSar'] as num).toDouble(), closeTo(0.073 * 3.75, 1e-6));
    expect(s['topSpecies'], [
      {'id': '0408', 'n': 2},
    ]);
    // الحسابات تنحفظ في الملف وترجع بعد إعادة تشغيل السيرفر.
    expect(AccountStore.open(dir.path)!.remaining(user, t), 2);
  });

  test('a RevenueCat purchase lifts the free limit to the monthly cap until expiry', () async {
    final a = app();
    for (var i = 0; i < 3; i++) {
      await scan(a);
    }
    Future<Response> rc(Map<String, Object> event, {String secret = 'rc-secret'}) async => a.handler(
      Request('POST', Uri.parse('http://x/api/revenuecat'), body: jsonEncode({'event': event}), headers: {'authorization': 'Bearer $secret'}),
    );
    final until = t.add(const Duration(days: 30)).millisecondsSinceEpoch;
    expect((await rc({'type': 'INITIAL_PURCHASE', 'app_user_id': user, 'product_id': 'fishid_monthly', 'expiration_at_ms': until}, secret: 'x')).statusCode, 401);
    await rc({'type': 'INITIAL_PURCHASE', 'app_user_id': user, 'product_id': 'fishid_monthly', 'expiration_at_ms': until});
    final r = await scan(a);
    expect(r.statusCode, 200);
    expect(r.headers['x-fishid-remaining'], '14');
    final me = await a.handler(Request('GET', Uri.parse('http://x/api/fishId/me'), headers: {'x-fishid-user': user}));
    expect(jsonDecode(await me.readAsString())['plan'], 'monthly');
    // بعد تاريخ الانتهاء يرجع مجاني، والمجانية مستخدمة.
    t = t.add(const Duration(days: 31));
    expect((await scan(a)).statusCode, 402);
  });

  test('admin needs the token, and can gift scans, change plans and settings', () async {
    final a = app();
    expect((await admin(a, 'stats', token: 'wrong')).statusCode, 401);
    final page = await a.handler(Request('GET', Uri.parse('http://x/api/admin')));
    expect(page.headers['content-type'], contains('text/html'));
    for (var i = 0; i < 3; i++) {
      await scan(a);
    }
    var u = jsonDecode(await (await admin(a, 'users/$user', body: {'grant': 2})).readAsString());
    expect(u['remaining'], 2);
    expect((await scan(a)).statusCode, 200);
    u = jsonDecode(await (await admin(a, 'users/$user', body: {'blocked': true})).readAsString());
    expect((await scan(a)).statusCode, 403);
    await admin(a, 'users/$user', body: {'blocked': false, 'plan': 'yearly', 'days': 366});
    await admin(a, 'settings', body: {'monthlyCap': 20, 'requireAccount': true, 'unknown': 5});
    // 20 من السقف ناقص فحص، وفحص الهدية الباقي ينضاف.
    expect((await scan(a)).headers['x-fishid-remaining'], '20');
    expect((await scan(a, id: null)).statusCode, 426);
    final users = jsonDecode(await (await admin(a, 'users?q=yearly')).readAsString()) as List;
    expect(users.single['id'], user);
  });

  test('admin is off without a token', () async {
    final a = app(admin: '');
    expect((await a.handler(Request('GET', Uri.parse('http://x/api/admin')))).statusCode, 404);
  });

  test('a gift code adds scans once per account, up to its limit', () async {
    final a = app();
    Future<Response> redeem(String code, {String id = user}) async =>
        a.handler(Request('POST', Uri.parse('http://x/api/fishId/redeem'), body: jsonEncode({'code': code}), headers: {'x-fishid-user': id}));
    expect((await redeem('NOPE-1234')).statusCode, 400);
    await admin(a, 'codes', body: {'code': 'play-review', 'scans': 50, 'max': 1});
    final r = await redeem(' play-review ');
    expect(r.statusCode, 200);
    expect(jsonDecode(await r.readAsString())['remaining'], 53);
    expect(jsonDecode(await (await redeem('PLAY-REVIEW')).readAsString())['code'], 'code_used');
    expect(jsonDecode(await (await redeem('PLAY-REVIEW', id: 'u_zzzzzzzzzzzzzzzz9999')).readAsString())['code'], 'code_full');
    final codes = jsonDecode(await (await admin(a, 'codes')).readAsString()) as List;
    expect(codes.single, {'code': 'PLAY-REVIEW', 'scans': 50, 'max': 1, 'used': 1});
    expect(AccountStore.open(dir.path)!.codes().single['used'], 1);
  });
}
