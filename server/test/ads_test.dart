import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/ads.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/ledger.dart';
import 'package:fish_id_server/site.dart';
import 'package:fish_id_server/staff.dart';
import 'package:fish_id_server/waitlist.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  // 8 مساءً بتوقيت السعودية، 1 نوفمبر.
  final t = DateTime.utc(2026, 11, 1, 17);
  setUp(() => dir = Directory.systemTemp.createTempSync('ads'));
  tearDown(() => dir.deleteSync(recursive: true));

  FishIdApp make() {
    final accounts = AccountStore.open(dir.path)!;
    return FishIdApp(
      identify: null,
      accounts: accounts,
      ledger: Ledger.open(accounts),
      site: SiteStats.open(dir.path),
      waitlist: Waitlist.open(dir.path),
      ads: AdStore.open(dir.path),
      adminToken: 'secret',
      clock: () => t,
    );
  }

  Future<Response> call(FishIdApp app, String method, String path, {Object? body, String auth = 'Bearer secret'}) async =>
      app.handler(Request(method, Uri.parse('http://x/api/$path'), body: body == null ? null : jsonEncode(body), headers: {'authorization': auth, 'x-forwarded-for': '1.2.3.4', 'user-agent': 'Mozilla/5.0'}));
  Future<Map<String, dynamic>> json(Future<Response> r) async => jsonDecode(await (await r).readAsString()) as Map<String, dynamic>;

  test('google pushes with its key, manual entries convert dollars, and the brief adds it all up', () async {
    final app = make();
    final key = (await json(call(app, 'GET', 'admin/ads')))['pushKey'] as String;
    expect(key, startsWith('ap_'));
    expect((await call(app, 'POST', 'ads/push', body: {'day': '2026-11-01', 'spend': 34.53, 'impressions': 232, 'clicks': 10}, auth: 'Bearer wrong')).statusCode, 401);
    expect((await call(app, 'POST', 'ads/push', body: {'day': '2026-11-01', 'spend': 34.53, 'currency': 'SAR', 'impressions': 232, 'clicks': 10}, auth: 'Bearer $key')).statusCode, 200);
    await call(
      app,
      'POST',
      'admin/ads',
      body: {
        'put': {'platform': 'x', 'day': '2026-11-01', 'spend': 6.16, 'currency': 'USD', 'impressions': 29628, 'clicks': 84},
      },
    );
    // نفس اليوم والمنصة يحل محل القديم.
    await call(
      app,
      'POST',
      'admin/ads',
      body: {
        'put': {'platform': 'x', 'day': '2026-11-01', 'spend': 8, 'currency': 'USD', 'impressions': 30000, 'clicks': 90},
      },
    );

    for (final src in ['snapchat', 'snapchat', 'x.com']) {
      await call(app, 'POST', 'track', body: {'e': 'visit', 'src': src});
    }
    await call(app, 'POST', 'waitlist', body: {'contact': 'a@b.co', 'consent': true});

    final b = await json(call(app, 'GET', 'admin/brief?day=2026-11-01'));
    final ads = b['ads'] as Map;
    expect(ads['spendSar'], 64.53);
    expect(ads['impressions'], 30232);
    expect(ads['clicks'], 100);
    expect((ads['rows'] as Map)['x']['spendSar'], 30.0);
    expect((ads['linked'] as Map)['google']['linked'], isTrue);
    expect((ads['linked'] as Map)['meta']['linked'], isFalse);
    expect(b['site']['visits'], 3);
    expect(b['site']['unique'], 1);
    expect(b['site']['hours'], {'20': 3});
    expect(b['signups'], containsPair('count', 1));
    expect(b['signups']['costSar'], 64.53);

    final text = app.briefText('2026-11-01', t);
    expect(text, contains('64.53 ريال'));
    expect(text, contains('إكس: 30.00 ريال، 30,000 ظهور، 90 ضغطة'));
    expect(text, contains('غير مربوطة: ميتا (فيسبوك وإنستغرام)، سناب شات'));
    expect(text, contains('أكثر ساعة اليوم: 8 المساء'));

    // المحاسبة: صرف كل منصة مصروف تلقائي في الشهر.
    final st = await json(call(app, 'GET', 'admin/ledger?month=2026-11'));
    final lines = (st['expenses'] as List).cast<Map>().where((e) => e['ads'] != null).toList();
    expect(lines.map((e) => e['sar']), unorderedEquals([34.53, 30.0]));
    expect(st['expensesSar'], 64.53);
  });

  test('accountants read the brief but cannot change ads; keys never leave the server', () async {
    final app = make();
    final staff = StaffStore.open(dir.path);
    final added = await staff.add('Sara', 'accountant', t);
    final app2 = FishIdApp(identify: null, accounts: AccountStore.open(dir.path), ads: AdStore.open(dir.path), staff: staff, adminToken: 'secret', clock: () => t);
    final auth = 'Bearer ${added['token']}';
    expect((await call(app2, 'GET', 'admin/brief', auth: auth)).statusCode, 200);
    expect((await call(app2, 'POST', 'admin/ads', body: {'pull': true}, auth: auth)).statusCode, 403);
    await call(
      app,
      'POST',
      'admin/ads',
      body: {
        'link': {'platform': 'meta', 'account': '123', 'token': 'very-secret'},
      },
    );
    final view = await (await call(app, 'GET', 'admin/ads')).readAsString();
    expect(view, isNot(contains('very-secret')));
    expect(jsonDecode(view)['platforms']['meta']['linked'], isTrue);
    expect(File('${dir.path}/ad_keys.json').readAsStringSync(), contains('very-secret'));
  });

  test('snapchat connect gives a consent link with a one-time state', () async {
    final app = make();
    expect((await call(app, 'POST', 'admin/ads', body: {'snapUrl': true})).statusCode, 400);
    await call(app, 'POST', 'admin/ads', body: {'link': {'platform': 'snapchat', 'account': 'acc', 'client': 'cid', 'secret': 'sec'}});
    final url = Uri.parse((await json(call(app, 'POST', 'admin/ads', body: {'snapUrl': true})))['url'] as String);
    expect(url.host, 'accounts.snapchat.com');
    expect(url.queryParameters['redirect_uri'], FishIdApp.snapRedirect);
    expect(url.queryParameters['client_id'], 'cid');
    final bad = await (await call(app, 'GET', 'ads/snap?code=x&state=wrong')).readAsString();
    expect(bad, contains('الرابط قديم'));
  });

  test('x request signature follows OAuth 1.0a', () {
    final h = AdStore.oauth1(
      'GET',
      Uri.https('ads-api.x.com', '/12/stats/accounts/abc', {'entity': 'ACCOUNT'}),
      {'consumerKey': 'ck', 'consumerSecret': 'cs', 'token': 'tk', 'tokenSecret': 'ts'},
      nonce: 'n',
      timestamp: 1,
    );
    expect(h, startsWith('OAuth '));
    expect(h, contains('oauth_consumer_key="ck"'));
    expect(h, contains('oauth_signature_method="HMAC-SHA1"'));
    expect(h, matches(RegExp(r'oauth_signature="[A-Za-z0-9%]+"')));
    expect(h, isNot(contains('cs')));
  });
}
