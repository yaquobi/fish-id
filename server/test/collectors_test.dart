import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/collectors.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]);
  const admin = 'Bearer secret';

  late Directory dir;
  late FishIdApp app;
  final sent = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('collect');
    Directory('${dir.path}/contrib').createSync();
    sent.clear();
    app = FishIdApp(
      identify: null,
      contrib: ContribStore('${dir.path}/contrib'),
      collectors: CollectorStore.open(dir.path),
      adminToken: 'secret',
      speciesNames: const {'0220': 'شعور'},
      notify: sent.add,
      clock: () => DateTime.utc(2026, 11, 1, 9),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, dynamic)> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    final res = await app.handler(Request(method, Uri.parse('http://x/api/$path'), body: body == null ? null : jsonEncode(body), headers: headers));
    final text = await res.readAsString();
    return (res.statusCode, res.headers['content-type']!.contains('json') ? jsonDecode(text) : text);
  }

  test('admin creates a link, the collector joins and uploads 5 photos', () async {
    final (s, added) = await call('POST', 'admin/collectors', body: {'add': {'name': 'سعد', 'city': 'القنفذة'}}, headers: {'authorization': admin});
    expect(s, 200);
    final key = added['key'] as String;
    expect(CollectorStore.keyPattern.hasMatch(key), isTrue);
    final h = {'x-collector': key};

    var (status, page) = await call('GET', 'collect');
    expect(status, 200);
    expect(page, contains('collect/upload'));
    final (_, manifest) = await call('GET', 'collect/manifest.webmanifest?k=$key');
    expect(manifest['start_url'], '/api/collect?k=$key');
    expect(manifest['display'], 'standalone');

    var (st, me) = await call('GET', 'collect/me', headers: h);
    expect(st, 200);
    expect(me['joined'], false);
    expect(me['species']['0220'], 'شعور');

    final images = [for (final p in CollectorStore.parts) {'part': p, 'image': jpeg, 'mediaType': 'image/jpeg'}];
    (st, me) = await call('POST', 'collect/upload', body: {'name': 'شعور', 'images': images}, headers: h);
    expect((st, me['code']), (400, 'collector_join'));

    (st, me) = await call('POST', 'collect/join', body: {'contact': '055 123 4567', 'consent': true}, headers: h);
    expect(st, 200);

    (st, me) = await call('POST', 'collect/upload', body: {'name': 'شعور (0220)', 'species': '0220', 'images': images, 'note': 'صيد اليوم'}, headers: h);
    expect(st, 200);
    expect(me['fish'], 1);
    expect(me['today'], 1);
    expect(sent.single, contains('سعد'));

    final list = ContribStore('${dir.path}/contrib').latest();
    expect(list.single['files'], hasLength(5));
    expect(list.single['source'], 'collector');
    expect(list.single['parts'], CollectorStore.parts);
    expect(list.single['species'], '0220');
    expect(list.single['collector'], 'سعد');
    expect(list.single.containsKey('contact'), isFalse);

    final (_, all) = await call('GET', 'admin/collectors', headers: {'authorization': admin});
    expect(all.single['contact'], '0551234567');
    expect(all.single['photos'], 5);

    // بعد الإيقاف الرابط ما يشتغل.
    await call('POST', 'admin/collectors', body: {'key': key, 'active': false}, headers: {'authorization': admin});
    (st, me) = await call('GET', 'collect/me', headers: h);
    expect(st, 401);
  });

  test('rejects unknown links, missing consent and a missing fish name', () async {
    var (st, body) = await call('GET', 'collect/me', headers: {'x-collector': 'c_${'0' * 24}'});
    expect((st, body['code']), (401, 'collector'));
    final (_, added) = await call('POST', 'admin/collectors', body: {'add': {'name': 'علي', 'city': 'الدمام'}}, headers: {'authorization': admin});
    final h = {'x-collector': added['key'] as String};
    (st, body) = await call('POST', 'collect/join', body: {'contact': '0551234567'}, headers: h);
    expect(body['code'], 'contrib_consent');
    (st, body) = await call('POST', 'collect/join', body: {'contact': 'abc', 'consent': true}, headers: h);
    expect(st, 400);
    await call('POST', 'collect/join', body: {'contact': 'ali@example.com', 'consent': true}, headers: h);
    (st, body) = await call('POST', 'collect/upload', body: {'name': ' ', 'images': [{'image': jpeg, 'mediaType': 'image/jpeg'}]}, headers: h);
    expect(st, 400);
    final six = [for (var i = 0; i < 6; i++) {'image': jpeg, 'mediaType': 'image/jpeg'}];
    (st, body) = await call('POST', 'collect/upload', body: {'name': 'هامور', 'images': six}, headers: h);
    expect(body['code'], 'fishid_count');
  });
}
