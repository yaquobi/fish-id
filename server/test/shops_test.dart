import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/ledger.dart';
import 'package:fish_id_server/shops.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]);
  const admin = 'Bearer secret';
  const dev1 = 'device-one-0000000001', dev2 = 'device-two-0000000002', dev3 = 'device-three-00000003';

  late Directory dir;
  late FishIdApp app;
  late AccountStore accounts;
  late ShopStore shops;
  late Ledger ledger;
  var now = DateTime.utc(2026, 11, 2, 9);
  final sent = <String>[];
  // عمليات ميسر المزيفة: رقم العملية ← العملية.
  final payments = <String, Map<String, dynamic>>{};
  final charges = <Map<String, dynamic>>[];
  Map<String, dynamic>? chargeReply;

  FishIdApp build({bool gateway = true}) => FishIdApp(
    identify: (_) async => '{"candidates":[{"id":"HWT-FISH-0220","confidence":90}]}',
    accounts: accounts,
    ledger: ledger,
    shops: shops,
    gateway: gateway
        ? Gateway(
            publishableKey: 'pk_test_x',
            webhookSecret: 'hook',
            fetch: (id) async => payments[id],
            charge: (body) async {
              charges.add(body);
              final r = chargeReply;
              if (r != null) payments['${r['id']}'] = r;
              return r;
            },
          )
        : null,
    adminToken: 'secret',
    notify: sent.add,
    clock: () => now,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shops');
    accounts = AccountStore.open(dir.path)!;
    ledger = Ledger.open(accounts);
    shops = ShopStore.open(dir.path);
    now = DateTime.utc(2026, 11, 2, 9);
    sent.clear();
    payments.clear();
    charges.clear();
    chargeReply = null;
    app = build();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, dynamic, Map<String, String>)> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    final res = await app.handler(Request(method, Uri.parse('http://x/api/$path'), body: body == null ? null : jsonEncode(body), headers: headers));
    final text = await res.readAsString();
    final type = res.headers['content-type'] ?? '';
    return (res.statusCode, type.contains('json') ? jsonDecode(text) : text, res.headers);
  }

  Map<String, dynamic> payment(String id, String shop, {int amount = 35000, String status = 'paid', String? token}) => {
    'id': id,
    'status': status,
    'amount': amount,
    'fee': 450,
    'currency': 'SAR',
    'created_at': now.toIso8601String(),
    'metadata': {'shop': shop},
    'source': {
      'type': 'creditcard',
      'company': 'mada',
      'number': '4201-32XX-XXXX-1234',
      'token': ?token,
      'message': status == 'paid' ? 'APPROVED' : 'INSUFFICIENT_FUNDS',
    },
  };

  Future<(String, String)> register() async {
    final (s, r, _) = await call('POST', 'shop/start', body: {'name': 'أسماك البحر', 'kind': 'shop', 'city': 'جدة', 'phone': '0551234567', 'consent': true});
    expect(s, 200);
    final key = r['key'] as String;
    final (_, me, _) = await call('GET', 'shop/me', headers: {'x-shop': key});
    return (key, me['id'] as String);
  }

  test('page, config and validation', () async {
    var (s, page, _) = await call('GET', 'shop');
    expect(s, 200);
    expect(page, contains('Moyasar.init'));
    final (_, cfg, _) = await call('GET', 'shop/config');
    expect(cfg['price'], 350);
    expect(cfg['cap'], 300);
    expect(cfg['devices'], 5);
    expect(cfg['pay']['key'], 'pk_test_x');
    expect(cfg['pay']['test'], true);

    (s, _, _) = await call('POST', 'shop/start', body: {'name': 'محل', 'city': 'جدة', 'phone': '0551234567'});
    expect(s, 400, reason: 'consent required');
    final (s2, e, _) = await call('POST', 'shop/start', body: {'name': 'محل', 'city': 'جدة', 'phone': '123', 'consent': true});
    expect(s2, 400);
    expect(e['message'], contains('جوال'));
    final (s3, _, _) = await call('GET', 'shop/me', headers: {'x-shop': 's_${'0' * 32}'});
    expect(s3, 401);
  });

  test('pay online, link devices, share one balance, record income', () async {
    final (key, id) = await register();
    expect(sent.last, contains('أسماك البحر'));
    final h = {'x-shop': key};

    // قبل الدفع: الجهاز ينربط بس ما يفحص بالباقة.
    var (s, me, _) = await call('POST', 'shop/devices', body: {'add': dev1}, headers: h);
    expect(s, 200);
    expect(me['active'], false);
    expect(accounts.view(dev1, now)['active'], false);

    // مبلغ ناقص أو محل ثاني ما يفعّل.
    payments['00000000-0000-4000-8000-000000000005'] = payment('00000000-0000-4000-8000-000000000005', id, amount: 100);
    var (st, _, hd) = await call('GET', 'shop/paid?k=$key&id=00000000-0000-4000-8000-000000000005');
    expect(st, 303);
    expect(hd['location'], contains('r=fail'));

    payments['00000000-0000-4000-8000-000000000002'] = payment('00000000-0000-4000-8000-000000000002', id, token: 'token_abc');
    (st, _, hd) = await call('GET', 'shop/paid?k=$key&id=00000000-0000-4000-8000-000000000002');
    expect(hd['location'], contains('r=ok'));
    (_, me, _) = await call('GET', 'shop/me', headers: h);
    expect(me['active'], true);
    expect(me['until'], startsWith('2026-12-02'));
    expect(me['card'], 'mada •••• 1234');
    expect(me['canRenew'], true);
    expect(sent.last, contains('🏪'));

    // نفس العملية مرة ثانية (رجوع المتصفح + الـ webhook) ما تمد مرتين.
    var (hs, _, _) = await call(
      'POST',
      'moyasar',
      body: {
        'type': 'payment_paid',
        'secret_token': 'hook',
        'data': {'id': '00000000-0000-4000-8000-000000000002'},
      },
    );
    expect(hs, 200);
    (hs, _, _) = await call(
      'POST',
      'moyasar',
      body: {
        'type': 'payment_paid',
        'secret_token': 'wrong',
        'data': {'id': 'x'},
      },
    );
    expect(hs, 401);
    (_, me, _) = await call('GET', 'shop/me', headers: h);
    expect(me['until'], startsWith('2026-12-02'));
    expect(me['payments'], hasLength(1));

    // جهاز ثاني برمز المحل من «عندك رمز؟».
    final (rs, red, _) = await call('POST', 'fishId/redeem', body: {'code': '${me['join']}'.toLowerCase()}, headers: {'x-fishid-user': dev2});
    expect(rs, 200);
    expect(red['remaining'], 300);
    expect(red['shop'], 'أسماك البحر');

    // الجهازين يسحبون من نفس الرصيد.
    final photo = {'image': jpeg, 'mediaType': 'image/jpeg'};
    await call('POST', 'fishId/identify', body: photo, headers: {'x-fishid-user': dev1});
    final (_, _, ih) = await call('POST', 'fishId/identify', body: photo, headers: {'x-fishid-user': dev2});
    expect(ih['x-fishid-remaining'], '298');
    (_, me, _) = await call('GET', 'shop/me', headers: h);
    expect(me['used'], 2);
    final (_, mine, _) = await call('GET', 'fishId/me', headers: {'x-fishid-user': dev1});
    expect(mine['plan'], 'shop');
    expect(mine['until'], startsWith('2026-12-02'));

    // المحل الواحد اشتراك واحد في الأرقام.
    expect(accounts.paying(now)['shop'], 1);

    // جهاز في محل ما ينضاف لمحل ثاني.
    final (key2, _) = await register();
    final (ts, te, _) = await call('POST', 'shop/devices', body: {'add': dev1}, headers: {'x-shop': key2});
    expect(ts, 400);
    expect(te['code'], 'shop_taken');

    // شيل الجهاز: يرجع مجاني.
    (_, me, _) = await call('POST', 'shop/devices', body: {'remove': dev1}, headers: h);
    expect(me['devices'], hasLength(1));
    expect(accounts.view(dev1, now)['active'], false);

    // المحاسبة: دفعة ميسر بالرسوم من العملية. مفاتيح التجربة ما تنحسب دخل حقيقي.
    final m = ledger.statement('2026-11');
    expect(m['sandboxSales'], 1);
    expect(m['incomeSar'], 0);
    final line = jsonDecode(File('${dir.path}/sales/2026-11.jsonl').readAsLinesSync().single) as Map;
    expect(line['store'], 'MOYASAR');
    expect(line['product'], 'fishid_shop');
    expect(line['grossSar'], 350);
    expect(line['feeSar'], 4.5);
    expect(line['netSar'], 345.5);
  });

  test('device limit', () async {
    final (key, _) = await register();
    for (var i = 0; i < 5; i++) {
      final (s, _, _) = await call('POST', 'shop/devices', body: {'add': 'device-limit-00000000$i'}, headers: {'x-shop': key});
      expect(s, 200);
    }
    final (s, e, _) = await call('POST', 'shop/devices', body: {'add': dev3}, headers: {'x-shop': key});
    expect(s, 400);
    expect(e['code'], 'shop_full');
  });

  test('auto renewal with the saved card, and alert when it fails', () async {
    final (key, id) = await register();
    payments['00000000-0000-4000-8000-000000000001'] = payment('00000000-0000-4000-8000-000000000001', id, token: 'token_abc');
    await call('GET', 'shop/paid?k=$key&id=00000000-0000-4000-8000-000000000001');

    // قبل الانتهاء بأكثر من يوم: ما نسحب.
    now = DateTime.utc(2026, 11, 30, 9);
    await app.renewShops(now);
    expect(charges, isEmpty);

    // قبل الانتهاء بيوم: البطاقة ترفض، ونبلّغ المالك.
    now = DateTime.utc(2026, 12, 1, 12);
    chargeReply = payment('00000000-0000-4000-8000-000000000003', id, status: 'failed');
    await app.renewShops(now);
    expect(charges.single['source'], {'type': 'token', 'token': 'token_abc'});
    expect(charges.single['metadata'], {'shop': id, 'renew': 'yes'});
    expect(sent.last, contains('ما قدرنا نجدد'));
    expect(shops.byId(id)!['renewError'], 'INSUFFICIENT_FUNDS');

    // بعد ساعة: ما نعيد المحاولة على طول.
    now = now.add(const Duration(hours: 1));
    await app.renewShops(now);
    expect(charges, hasLength(1));

    // بعد 6 ساعات: تنجح وتمد شهر من نهاية الاشتراك.
    now = now.add(const Duration(hours: 6));
    chargeReply = payment('00000000-0000-4000-8000-000000000004', id);
    await app.renewShops(now);
    expect(charges, hasLength(2));
    final s = shops.byId(id)!;
    expect(s['until'], startsWith('2027-01-02'));
    expect(s['renewError'], isNull);
    expect(sent.last, contains('🔁'));
  });

  test('without a gateway: register, owner is told, admin records a bank transfer', () async {
    app = build(gateway: false);
    final (_, cfg, _) = await call('GET', 'shop/config');
    expect(cfg['pay'], isNull);
    final (key, id) = await register();
    expect(sent.last, contains('مو مفعّل'));

    final (s, list, _) = await call('GET', 'admin/shops', headers: {'authorization': admin});
    expect(s, 200);
    expect(list['ready'], false);
    expect((list['items'] as List).single['key'], key);

    final (ps, shop, _) = await call('POST', 'admin/shops', body: {'id': id, 'transfer': 350}, headers: {'authorization': admin});
    expect(ps, 200);
    expect(shop['active'], true);
    expect(shop['payments'].single['method'], 'transfer');
    final income = (ledger.statement('2026-11')['income'] as List).cast<Map>();
    expect(income.single['provider'], 'تحويل بنكي');
    expect(income.single['sar'], 350);

    // المحلات بدون تجديد تلقائي: تذكير مرة وحدة قبل الانتهاء.
    now = DateTime.utc(2026, 11, 30, 9);
    sent.clear();
    await app.renewShops(now);
    await app.renewShops(now);
    expect(sent.where((t) => t.contains('⏰')), hasLength(1));
  });

  test('admin plan change unlinks the device from its shop', () async {
    final (key, id) = await register();
    await call('POST', 'shop/devices', body: {'add': dev1}, headers: {'x-shop': key});
    expect(shops.byId(id)!['devices'], [dev1]);
    final (s, _, _) = await call('POST', 'admin/users/$dev1', body: {'plan': 'monthly', 'days': 30}, headers: {'authorization': admin});
    expect(s, 200);
    expect(shops.byId(id)!['devices'], isEmpty);
    expect(accounts.view(dev1, now)['plan'], 'monthly');
    expect(accounts.find(dev1)!['pool'], isNull);
  });

  test('FishIdError is used for shop errors', () {
    expect(const FishIdError('shop_full', 'x').status, 400);
  });
}
