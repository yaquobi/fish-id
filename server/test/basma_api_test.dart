import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/basma_api.dart';
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
}
