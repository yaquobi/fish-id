import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/basma_api.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:fish_id_server/mailer.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late BasmaClients clients;
  late BasmaApi api;
  final notes = <String>[];
  var now = DateTime.utc(2026, 11, 4, 12);
  var down = false;

  final data = {
    'species': [
      {'id': 'HWT-SHRIMP-0058', 'sci': 'Penaeus sp.', 'en': 'Shrimp', 'red': 'ربيان', 'gulf': '', 'fam': 'PENAEIDAE'},
      {'id': 'HWT-FISH-0058', 'sci': 'Balistoides viridescens', 'en': 'Titan triggerfish', 'red': 'حريد | بغل', 'gulf': '', 'fam': 'BALISTIDAE'},
      {'id': 'HWT-FISH-0365', 'sci': 'Epinephelus coioides', 'en': 'Orange-spotted grouper', 'red': 'هامور', 'gulf': 'هامور', 'fam': 'SERRANIDAE'},
    ],
  };

  setUp(() {
    dir = Directory.systemTemp.createTempSync('basma_api');
    clients = BasmaClients.open(dir.path);
    notes.clear();
    now = DateTime.utc(2026, 11, 4, 12);
    down = false;
    api = BasmaApi(
      clients,
      (photo) async {
        if (down) throw const SocketException('down');
        return {
          'top': [
            {'id': '0058', 'score': 0.9},
            {'id': '0365', 'score': 0.05},
          ],
          'ms': 640,
        };
      },
      BasmaApi.speciesFrom(data),
      perMinute: 3,
      notify: notes.add,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, Map<String, dynamic>)> call(String sub, {String? key, String method = 'POST', List<int>? body, String type = 'image/jpeg', String query = ''}) async {
    final res = await api.handle(
      Request(method, Uri.parse('http://x/api/basma/v1/$sub$query'), body: body, headers: {'content-type': type, 'authorization': ?(key == null ? null : 'Bearer $key')}),
      sub,
      now,
    );
    return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, dynamic>);
  }

  test('identifies with names, counts usage and blocks a finished trial', () async {
    final k = (await clients.add({'name': 'Test Co', 'plan': 'trial'}, now))['key'] as String;
    expect(k, matches(BasmaClients.keyPattern));
    var (s, j) = await call('identify', key: k, body: [1, 2, 3], query: '?top=1');
    expect(s, 200);
    expect(j['model'], 'basma-0.1');
    expect(j['results'], hasLength(1));
    // السمكة تتقدّم على الربيان اللي له نفس الرقم.
    expect(j['results'][0]['scientific'], 'Balistoides viridescens');
    expect(j['results'][0]['red_sea'], 'حريد');
    expect(j['usage']['used'], 1);
    expect(j['usage']['remaining'], 49);

    // الجسم JSON بالـ base64 يشتغل بعد.
    (s, j) = await call(
      'identify',
      key: k,
      type: 'application/json',
      body: utf8.encode(
        jsonEncode({
          'image': base64.encode([1, 2]),
          'mediaType': 'image/png',
        }),
      ),
    );
    expect(s, 200);
    expect(j['results'], hasLength(2));

    // ما نحفظ المفتاح نفسه.
    expect(File('${dir.path}/basma_clients.json').readAsStringSync(), isNot(contains(k)));

    final id = clients.list(now).single['id'] as String;
    await clients.update(id, {'included': 2}, now);
    (s, j) = await call('identify', key: k, body: [1]);
    expect(s, 402);
    expect(j['error']['code'], 'quota');
  });

  test('rejects bad keys, bad images, expiry, rate limit and service outage', () async {
    var (s, j) = await call('identify', key: 'bsk_${'0' * 40}', body: [1]);
    expect(s, 401);
    final k = (await clients.add({'name': 'A', 'plan': 'developer'}, now))['key'] as String;
    (s, j) = await call('identify', key: k, type: 'text/plain', body: [1]);
    expect(j['error']['code'], 'bad_image');
    down = true;
    (s, j) = await call('identify', key: k, body: [1]);
    expect(s, 503);
    expect(clients.list(now).single['used'], 0);
    (s, j) = await call('identify', key: k, body: [1]);
    expect(s, 503);
    (s, j) = await call('identify', key: k, body: [1]);
    expect(s, 429);

    now = now.add(const Duration(minutes: 1));
    final t = (await clients.add({'name': 'B', 'plan': 'trial'}, now))['key'] as String;
    now = now.add(const Duration(days: 31));
    (s, j) = await call('usage', key: t, method: 'GET');
    expect(s, 200);
    (s, j) = await call('identify', key: t, body: [1]);
    expect(j['error']['code'], 'expired');
  });

  test('bills overage, rotates keys and pauses clients', () async {
    final r = await clients.add({'name': 'Fish Co', 'plan': 'developer', 'included': 1}, now);
    final id = r['id'] as String;
    for (var i = 0; i < 3; i++) {
      final (s, _) = await call('identify', key: r['key'] as String, body: [1]);
      expect(s, 200);
      now = now.add(const Duration(minutes: 1));
    }
    expect(notes.first, contains('خلّص'));
    final bill = clients.list(now).single['bill'] as Map;
    expect(bill['extra'], 2);
    expect(bill['amount'], 1499.8);
    expect(bill['total'], 1724.77);

    final k2 = (await clients.rotate(id))['key'] as String;
    expect((await call('usage', key: r['key'] as String, method: 'GET')).$1, 401);
    expect((await call('usage', key: k2, method: 'GET')).$1, 200);
    await clients.update(id, {'active': false, 'invoiced': '2026-11'}, now);
    expect((await call('usage', key: k2, method: 'GET')).$1, 401);
    expect(BasmaClients.open(dir.path).list(now).single['bill']['invoiced'], isTrue);
  });

  test('self signup emails a trial key once per email', () async {
    final sent = <(String, String)>[];
    var fail = false;
    final withMail = BasmaApi(
      clients,
      (_) async => {'top': [], 'ms': 1},
      const {},
      notify: notes.add,
      mail: ({required to, required subject, required html, required text}) async {
        if (fail) throw const SocketException('smtp down');
        sent.add((to, text));
      },
    );
    Future<(int, Map<String, dynamic>)> signup(Map b, {String ip = '1.1.1.1'}) async {
      final res = await withMail.handle(Request('POST', Uri.parse('http://x/api/basma/v1/signup'), body: jsonEncode(b), headers: {'x-forwarded-for': ip}), 'signup', now);
      return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, dynamic>);
    }

    final form = {'name': 'Sara', 'company': 'Red Sea Lab', 'email': 'Sara@Lab.com ', 'country': 'مصر', 'plan': 'developer', 'consent': true};
    var (s, j) = await signup({...form, 'consent': false});
    expect(s, 400);
    (s, j) = await signup(form);
    expect(s, 200);
    expect(j['sent'], isTrue);
    expect(j.containsKey('key'), isFalse);
    expect(sent.single.$1, 'sara@lab.com');
    final key = RegExp(r'bsk_[0-9a-f]{40}').firstMatch(sent.single.$2)![0]!;
    expect(sent.single.$2, contains('مطوّر'));
    final c = clients.list(now).single;
    expect(c['plan'], 'trial');
    expect(c['wants'], 'developer');
    expect(c['contact'], 'sara@lab.com');
    expect(notes.last, contains('يبغى باقة'));
    expect(clients.find(key), isNotNull);

    (s, j) = await signup(form);
    expect(s, 409);

    fail = true;
    (s, j) = await signup({...form, 'email': 'other@lab.com'});
    expect(s, 503);
    expect(clients.list(now), hasLength(1));

    // كل IP له 5 محاولات باليوم.
    (s, j) = await signup({...form, 'email': 'x@lab.com'});
    (s, j) = await signup({...form, 'email': 'y@lab.com'});
    expect(s, 429);
  });

  test('without a mailer the key comes back on the page', () async {
    final res = await api.handle(Request('POST', Uri.parse('http://x/api/basma/v1/signup'), body: jsonEncode({'name': 'A', 'email': 'a@b.co', 'consent': true})), 'signup', now);
    final j = jsonDecode(await res.readAsString()) as Map;
    expect(j['key'], matches(BasmaClients.keyPattern));
  });

  test('mail message is MIME with encoded Arabic subject', () {
    final m = Mailer(host: 'h', from: 'info@hawat.id', fromName: 'بصمة').message(to: 'a@b.co', subject: 'مفتاحك', html: '<b>هلا</b>', text: 'هلا', boundary: 'B');
    expect(m, contains('Subject: =?UTF-8?B?${base64.encode(utf8.encode('مفتاحك'))}?='));
    expect(m, contains('From: =?UTF-8?B?'));
    expect(m, contains(base64.encode(utf8.encode('<b>هلا</b>'))));
    expect(m, contains('--B--'));
  });

  test('a client labels a photo: it joins the review queue and is not counted', () async {
    final cdir = Directory.systemTemp.createTempSync('basma_label');
    addTearDown(() => cdir.deleteSync(recursive: true));
    final store = ContribStore(cdir.path);
    api = BasmaApi(clients, (p) async => {'top': [], 'ms': 1}, BasmaApi.speciesFrom(data), notify: notes.add, contrib: store);
    final k = (await clients.add({'name': 'حوات', 'plan': 'trial'}, now))['key'] as String;
    final jpg = [0xFF, 0xD8, 0xFF, 0xD9];
    Future<(int, Map<String, dynamic>)> label(Map<String, Object?> b) => call('label', key: k, type: 'application/json', body: utf8.encode(jsonEncode({'image': base64.encode(jpg), 'mediaType': 'image/jpeg', ...b})));

    var (s, j) = await label({'species': '0365', 'name': 'هامور', 'verdict': 'correct', 'predicted': ['0365', '0058', 'x'], 'score': 91, 'source': 'hawat-counter', 'place': 'ميناء القنفذة'});
    expect(s, 200);
    expect(j['ok'], isTrue);
    (s, j) = await label({'species': '', 'name': 'شعور', 'verdict': 'corrected', 'predicted': ['0058']});
    expect(s, 200);
    (s, j) = await label({'species': '9999'});
    expect(s, 400);
    expect(j['error']['code'], 'bad_species');
    (s, j) = await label({'species': '', 'name': ''});
    expect(s, 400);

    final items = store.latest();
    expect(items, hasLength(2));
    final first = items.firstWhere((m) => m['verdict'] == 'correct');
    expect(first['source'], 'basma-label');
    expect(first['client'], 'حوات');
    expect(first['place'], 'ميناء القنفذة');
    expect(first['species'], '0365');
    expect(first['species_confirmed'], isTrue);
    expect(first['predicted'], ['0365', '0058']);
    expect(items.firstWhere((m) => m['verdict'] == 'corrected')['species_confirmed'], isFalse);
    // تنبيه واحد في اليوم، والصور ما تنحسب من الباقة.
    expect(notes.where((n) => n.contains('🏷️')), hasLength(1));
    final (_, u) = await call('usage', key: k, method: 'GET');
    expect(u['used'], 0);
  });
}
