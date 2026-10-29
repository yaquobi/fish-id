import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/ledger.dart';
import 'package:fish_id_server/staff.dart';
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

  // ما يرجّعه RevenueCat لكل حساب في الاختبارات.
  final subscribers = <String, Map<String, dynamic>>{};
  FishIdApp app({String admin = 'secret-token', Notify? notify}) {
    final accounts = AccountStore.open(dir.path)!;
    return FishIdApp(
      identify: fakeIdentify,
      accounts: accounts,
      ledger: Ledger.open(accounts),
      staff: StaffStore.open(accounts.dir),
      adminToken: admin,
      revenueCat: (id) async => {'subscriber': {'entitlements': subscribers[id] ?? {}}},
      notify: notify,
      clock: () => t,
    );
  }

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
    Future<Response> rc(Map<String, Object> event) async =>
        a.handler(Request('POST', Uri.parse('http://x/api/revenuecat'), body: jsonEncode({'event': event})));
    // الحدث وحده ما يكفي: RevenueCat يقول إن الحساب ما عنده اشتراك.
    await rc({'type': 'INITIAL_PURCHASE', 'app_user_id': user, 'product_id': 'fishid_yearly'});
    expect((await scan(a)).statusCode, 402);
    subscribers[user] = {
      'FISH ID Pro': {'product_identifier': 'fishid_monthly:monthly', 'expires_date': t.add(const Duration(days: 30)).toIso8601String()},
    };
    await rc({'type': 'INITIAL_PURCHASE', 'app_user_id': user});
    final r = await scan(a);
    expect(r.statusCode, 200);
    expect(r.headers['x-fishid-remaining'], '14');
    final me = await a.handler(Request('GET', Uri.parse('http://x/api/fishId/me'), headers: {'x-fishid-user': user}));
    expect(jsonDecode(await me.readAsString())['plan'], 'monthly');
    // بعد تاريخ الانتهاء يرجع مجاني، والمجانية مستخدمة.
    t = t.add(const Duration(days: 31));
    expect((await scan(a)).statusCode, 402);
  });

  test('the app syncs after buying, and a refund ends only store plans', () async {
    final a = app();
    Future<Response> sync() async =>
        a.handler(Request('POST', Uri.parse('http://x/api/fishId/sync'), headers: {'x-fishid-user': user}));
    subscribers[user] = {
      'FISH ID Pro': {'product_identifier': 'fishid_yearly', 'expires_date': t.add(const Duration(days: 365)).toIso8601String()},
    };
    expect(jsonDecode(await (await sync()).readAsString())['remaining'], 15);
    expect(a.accounts!.find(user)!['plan'], 'yearly');
    subscribers.remove(user);
    await sync();
    expect(a.accounts!.find(user)!['plan'], 'free');
    // باقة من الأدمن تبقى حتى لو ما له اشتراك في المتجر.
    await a.accounts!.update(user, t, plan: 'shop', until: t.add(const Duration(days: 31)));
    await sync();
    expect(a.accounts!.find(user)!['plan'], 'shop');
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

  test('accounting: store sales, refunds, Claude cost and admin entries make the monthly statement', () async {
    final a = app();
    Future<void> rc(Map<String, Object> event) async =>
        a.handler(Request('POST', Uri.parse('http://x/api/revenuecat'), body: jsonEncode({'event': {'app_user_id': user, ...event}})));
    final sale = {
      'id': 'ev1',
      'type': 'INITIAL_PURCHASE',
      'product_id': 'fishid_monthly',
      'price': 6.67,
      'currency': 'SAR',
      'price_in_purchased_currency': 25,
      'tax_percentage': 0.1304,
      'commission_percentage': 0.1304,
      'event_timestamp_ms': t.millisecondsSinceEpoch,
    };
    // بيعة ما أكدها RevenueCat ما تنحسب، ولا استرجاع بدون بيعة قبله.
    await rc(sale);
    await rc({...sale, 'id': 'ev0', 'price': -6.67, 'price_in_purchased_currency': -25});
    subscribers[user] = {
      'FISH ID Pro': {'product_identifier': 'fishid_monthly', 'expires_date': t.add(const Duration(days: 30)).toIso8601String()},
    };
    await rc(sale);
    await rc(sale); // نفس الحدث مرتين ينحسب مرة.
    await rc({...sale, 'id': 'ev2', 'environment': 'SANDBOX'});
    await scan(a);
    await admin(a, 'ledger', body: {
      'add': {'kind': 'expense', 'provider': 'Hostinger', 'label': 'الخادم', 'amount': 20, 'currency': 'USD', 'date': '2026-09-15', 'repeat': 'monthly'},
    });
    await admin(a, 'ledger', body: {
      'add': {'kind': 'income', 'provider': 'محل', 'label': 'باقة محل بتحويل', 'amount': 350, 'date': '2026-10-02'},
    });
    expect((await admin(a, 'ledger', body: {'add': {'kind': 'expense', 'label': 'x', 'amount': -5, 'date': '2026-10-01'}})).statusCode, 400);

    var s = jsonDecode(await (await admin(a, 'ledger?month=2026-10')).readAsString());
    expect(s['paidSales'], 1);
    expect(s['sandboxSales'], 1);
    final store = (s['income'] as List).firstWhere((i) => i['auto'] == true);
    expect(store['grossSar'], 25);
    expect(store['sar'], closeTo(18.48, 0.01));
    expect(s['incomeSar'], closeTo(368.48, 0.01));
    final claude = (s['expenses'] as List).firstWhere((e) => e['provider'] == 'Anthropic (Claude)');
    expect(claude['n'], 1);
    expect(s['expensesSar'], closeTo(75 + claude['sar'], 0.01));
    expect((s['history'] as List).length, 12);
    expect((s['history'] as List)[10]['expensesSar'], 75); // سبتمبر: الخادم بس.

    // استرجاع بعد البيعة ينقص الدخل.
    await rc({...sale, 'id': 'ev3', 'type': 'CANCELLATION', 'price': -6.67, 'price_in_purchased_currency': -25});
    s = jsonDecode(await (await admin(a, 'ledger?month=2026-10')).readAsString());
    expect(s['incomeSar'], closeTo(350, 0.01));

    // إيقاف المصروف المتكرر بعد أكتوبر.
    final id = (s['entries'] as List).firstWhere((e) => e['provider'] == 'Hostinger')['id'];
    await admin(a, 'ledger', body: {'stop': id, 'last': '2026-10'});
    s = jsonDecode(await (await admin(a, 'ledger?month=2026-11')).readAsString());
    expect(s['expensesSar'], 0);
    final stats = jsonDecode(await (await admin(a, 'stats')).readAsString());
    expect(stats['ledger']['incomeSar'], closeTo(350, 0.01));
    expect((stats['daily'] as List).length, 30);
  });

  test('staff tokens get only their role\'s sections', () async {
    final a = app();
    final acc = jsonDecode(await (await admin(a, 'staff', body: {'add': {'name': 'المحاسب', 'role': 'accountant'}})).readAsString());
    final inv = jsonDecode(await (await admin(a, 'staff', body: {'add': {'name': 'مستثمر', 'role': 'investor'}})).readAsString());
    expect(acc['token'], startsWith('fs_'));
    Future<int> as(Map t, String path, {Object? body}) async => (await admin(a, path, body: body, token: t['token'] as String)).statusCode;
    expect(await as(acc, 'ledger'), 200);
    expect(await as(acc, 'users'), 403);
    expect(await as(acc, 'staff'), 403);
    expect(await as(inv, 'report?period=month&key=2026-10'), 200);
    expect(await as(inv, 'ledger'), 403);
    expect(await as(inv, 'alerts', body: {'balanceUsd': 5}), 403);
    final me = jsonDecode(await (await admin(a, 'me', token: inv['token'] as String)).readAsString());
    expect(me, {'id': inv['id'], 'name': 'مستثمر', 'role': 'investor', 'created': isA<String>()});
    // بعد الحذف يوقف الرمز.
    await admin(a, 'staff', body: {'delete': inv['id']});
    expect(await as(inv, 'report?period=month&key=2026-10'), 401);
  });

  test('period reports compare with the previous period', () async {
    final a = app();
    await scan(a);
    await scan(a, id: 'u_second_account_123456');
    t = DateTime.utc(2026, 9, 3, 12);
    await scan(a, id: 'u_third_account_1234567');
    t = DateTime.utc(2026, 10, 28, 12);
    var r = jsonDecode(await (await admin(a, 'report?period=month&key=2026-10')).readAsString());
    expect(r['scans'], 2);
    expect(r['newUsers'], 2);
    expect(r['activeUsers'], 2);
    expect(r['users'], 3);
    expect(r['previous']['scans'], 1);
    expect((r['series'] as List).length, 31);
    r = jsonDecode(await (await admin(a, 'report?period=year&key=2026')).readAsString());
    expect(r['scans'], 3);
    expect((r['series'] as List).length, 12);
    r = jsonDecode(await (await admin(a, 'report?period=day&key=2026-10-28')).readAsString());
    expect(r['scans'], 2);
    expect((r['series'] as List)[12]['scans'], 2);
    expect((await admin(a, 'report?period=week&key=2026')).statusCode, 400);
  });

  test('alerts: Claude refusing, a low balance and bills due soon', () async {
    final a = FishIdApp(
      identify: (_) async => throw const FishIdError('claude_credit', 'x', status: 503),
      accounts: AccountStore.open(dir.path),
      ledger: Ledger.open(AccountStore.open(dir.path)!),
      adminToken: 'secret-token',
      clock: () => t,
    );
    expect((await scan(a)).statusCode, 503);
    var al = jsonDecode(await (await admin(a, 'alerts')).readAsString());
    expect([for (final x in al['alerts']) x['code']], ['claude_credit', 'balance_unset']);
    await admin(a, 'alerts', body: {'balanceUsd': 0.05});
    await admin(a, 'ledger', body: {
      'add': {'kind': 'expense', 'provider': 'Hostinger', 'label': 'الخادم', 'amount': 20, 'currency': 'USD', 'date': '2026-06-02', 'repeat': 'monthly'},
    });
    // فحص ناجح يمسح تنبيه الرصيد اللي خلص، وتكلفته 0.073 دولار تخلّص الرصيد.
    final b = app();
    t = t.add(const Duration(minutes: 1));
    await scan(b);
    al = jsonDecode(await (await admin(b, 'alerts')).readAsString());
    expect([for (final x in al['alerts']) x['code']], ['balance_out', 'bill_due']);
    expect(al['upcoming'][0]['due'], '2026-11-02');
  });

  test('telegram: confirmed sales, Claude refusing once per 3 hours, and the daily summary', () async {
    final sent = <String>[];
    final a = app(notify: sent.add);
    Future<void> rc(Map<String, Object> event) async =>
        a.handler(Request('POST', Uri.parse('http://x/api/revenuecat'), body: jsonEncode({'event': {'app_user_id': user, ...event}})));
    final sale = {'id': 'ev1', 'type': 'INITIAL_PURCHASE', 'product_id': 'fishid_yearly', 'price': 53, 'currency': 'SAR', 'price_in_purchased_currency': 199.99};
    // حدث ما أكده RevenueCat ما يوصل تنبيهه.
    await rc(sale);
    expect(sent, isEmpty);
    subscribers[user] = {
      'FISH ID Pro': {'product_identifier': 'fishid_yearly', 'expires_date': t.add(const Duration(days: 365)).toIso8601String()},
    };
    await rc(sale);
    expect(sent.single, contains('اشتراك جديد'));
    expect(sent.single, contains('سنوي · 199.99 SAR'));
    await rc(sale); // نفس الحدث ما يتكرر.
    expect(sent, hasLength(1));

    final b = FishIdApp(
      identify: (_) async => throw const FishIdError('claude_credit', 'x', status: 503),
      accounts: AccountStore.open(dir.path),
      ledger: Ledger.open(AccountStore.open(dir.path)!),
      notify: sent.add,
      clock: () => t,
    );
    await scan(b);
    await scan(b);
    expect(sent.where((m) => m.contains('رصيد Claude خلص')), hasLength(1));
    t = t.add(const Duration(hours: 3));
    await scan(b);
    expect(sent.where((m) => m.contains('رصيد Claude خلص')), hasLength(2));

    final summary = b.dailySummary(t)!;
    expect(summary, contains('ملخص اليوم'));
    expect(summary, contains('سنوي 1'));
    expect(summary, contains('Claude رافض الطلبات'));
  });
}
