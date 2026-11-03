import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/gov.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]);
  const admin = 'Bearer secret';
  const dev1 = 'inspector-phone-000001', dev2 = 'inspector-phone-000002', dev3 = 'inspector-phone-000003', citizen = 'citizen-phone-00000001';

  late Directory dir;
  late FishIdApp app;
  late AccountStore accounts;
  late GovStore gov;
  var now = DateTime.utc(2026, 11, 3, 9);
  final sent = <String>[];

  FishIdApp build() => FishIdApp(
    identify: (_) async => '{"candidates":[{"id":"0220","confidence":90}]}',
    box: (_) async => jsonEncode(
      FishIdAi.tidyBox({
        'is_fish_load': true,
        'items': [
          {'id': '220', 'name': 'ناجل', 'count': 4, 'count_min': 3, 'count_max': 6, 'size': 'large', 'freshness': 80, 'confidence': 70, 'note': ''},
          {'id': '', 'name': 'غير معروف', 'count': 0, 'count_min': 0, 'count_max': 1, 'size': 'small', 'freshness': -1, 'confidence': 10, 'note': ''},
          {'id': '0391', 'name': 'هامور', 'count': 12, 'count_min': 10, 'count_max': 15, 'size': 'medium', 'freshness': 75, 'confidence': 80, 'note': ''},
        ],
        'overall_freshness': 77,
        'summary': 'صندوق طازج',
        'photo_tip': '',
      }),
    ),
    accounts: accounts,
    gov: gov,
    adminToken: 'secret',
    notify: sent.add,
    clock: () => now,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gov');
    accounts = AccountStore.open(dir.path)!;
    gov = GovStore.open(dir.path);
    now = DateTime.utc(2026, 11, 3, 9);
    sent.clear();
    app = build();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, dynamic)> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    final res = await app.handler(
      Request(method, Uri.parse('http://x/api/$path'), body: body == null ? null : jsonEncode(body), headers: {'content-type': 'application/json', ...headers}),
    );
    final text = await res.readAsString();
    return (res.statusCode, res.headers['content-type']!.contains('json') ? jsonDecode(text) : text);
  }

  Future<(int, dynamic)> as(String user, String method, String path, {Object? body}) => call(method, path, body: body, headers: {'x-fishid-user': user});

  Future<Map<String, dynamic>> agency({int seats = 2}) async {
    final (s, a) = await call('POST', 'admin/gov', body: {'add': {'name': 'وزارة البيئة والمياه والزراعة', 'seats': seats, 'until': '2027-11-03', 'pilot': true}}, headers: {'authorization': admin});
    expect(s, 200);
    return a as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> inspector(String agencyId, String name) async {
    final (s, i) = await call('POST', 'admin/gov', body: {'agency': agencyId, 'inspector': {'name': name, 'phone': '0555555555', 'branch': 'مكة'}}, headers: {'authorization': admin});
    expect(s, 200, reason: '$i');
    return i as Map<String, dynamic>;
  }

  Map<String, dynamic> visit({String decision = 'violation', List<String> violations = const ['name'], bool photo = true}) => {
    'market': 'البنقلة',
    'city': 'جدة',
    'shop': 'محل البحر الأحمر 14',
    'labelName': 'هامور',
    'labelPrice': 95,
    'result': {'species': '0220', 'name': 'ناجل', 'sci': 'Plectropomus pessuliferus', 'confidence': 82, 'freshness': 71, 'grade': 'A'},
    'match': false,
    'decision': decision,
    'violations': violations,
    'note': 'تم التنبيه',
    'lat': 21.4858,
    'lng': 39.1925,
    if (photo)
      'images': [
        {'image': jpeg, 'mediaType': 'image/jpeg'},
      ],
  };

  test('inspector joins with a GOV code and scans without limit', () async {
    final a = await agency();
    final i = await inspector(a['id'] as String, 'عبدالله الحربي');
    expect(i['code'], matches(GovStore.codePattern));

    // قبل الدخول: حساب عادي بثلاث فحوصات مجانية.
    var (s, me) = await as(dev1, 'GET', 'fishId/me');
    expect(me['plan'], 'free');

    final (sj, p) = await as(dev1, 'POST', 'fishId/gov/join', body: {'code': (i['code'] as String).toLowerCase()});
    expect(sj, 200);
    expect(p['name'], 'عبدالله الحربي');
    expect(p['active'], isTrue);
    expect(sent.single, contains('مفتش'));

    (s, me) = await as(dev1, 'GET', 'fishId/me');
    expect(me['plan'], 'gov');
    expect(me['gov']['agency'], contains('وزارة'));

    for (var k = 0; k < 6; k++) {
      final (si, _) = await as(dev1, 'POST', 'fishId/identify', body: {'image': jpeg, 'mediaType': 'image/jpeg'});
      expect(si, 200);
    }
    expect(accounts.find(dev1)!['freeUsed'] ?? 0, 0);
    expect(accounts.remaining(dev1, now), AccountStore.ownerRemaining);

    // العقد انتهى: يرجع حساب عادي.
    now = DateTime.utc(2027, 11, 5);
    expect(accounts.remaining(dev1, now), 3);
    (s, me) = await as(dev1, 'GET', 'fishId/me');
    expect(me['plan'], 'free');
  });

  test('a code works on two devices at most, and a new code frees them', () async {
    final a = await agency();
    final i = await inspector(a['id'] as String, 'فهد الدوسري');
    expect((await as(dev1, 'POST', 'fishId/gov/join', body: {'code': i['code']})).$1, 200);
    expect((await as(dev2, 'POST', 'fishId/gov/join', body: {'code': i['code']})).$1, 200);
    final (s3, e3) = await as(dev3, 'POST', 'fishId/gov/join', body: {'code': i['code']});
    expect(s3, 409);
    expect(e3['code'], 'gov_devices');

    final (_, fresh) = await call('POST', 'admin/gov', body: {'inspectorId': i['id'], 'update': {'newCode': true}}, headers: {'authorization': admin});
    expect(fresh['code'], isNot(i['code']));
    expect((await as(dev3, 'POST', 'fishId/gov/join', body: {'code': i['code']})).$1, 400);
    expect((await as(dev3, 'POST', 'fishId/gov/join', body: {'code': fresh['code']})).$1, 200);
    expect(gov.unlimited(dev1, now), isFalse);
  });

  test('stopped inspector or agency cannot join', () async {
    final a = await agency();
    final i = await inspector(a['id'] as String, 'ناصر عسيري');
    await call('POST', 'admin/gov', body: {'inspectorId': i['id'], 'update': {'stopped': true}}, headers: {'authorization': admin});
    expect((await as(dev1, 'POST', 'fishId/gov/join', body: {'code': i['code']})).$2['code'], 'gov_stopped');
    await call('POST', 'admin/gov', body: {'inspectorId': i['id'], 'update': {'stopped': false}}, headers: {'authorization': admin});
    await call('POST', 'admin/gov', body: {'agency': a['id'], 'update': {'stopped': true}}, headers: {'authorization': admin});
    expect((await as(dev1, 'POST', 'fishId/gov/join', body: {'code': i['code']})).$2['code'], 'gov_expired');
  });

  test('seats limit the number of active inspectors', () async {
    final a = await agency(seats: 1);
    await inspector(a['id'] as String, 'الأول');
    final (s, e) = await call('POST', 'admin/gov', body: {'agency': a['id'], 'inspector': {'name': 'الثاني'}}, headers: {'authorization': admin});
    expect(s, 409);
    expect(e['code'], 'seats');
  });

  test('inspection visit is saved with a reference, photos and shows on the agency dashboard', () async {
    final a = await agency();
    final i = await inspector(a['id'] as String, 'عبدالله الحربي');
    // بدون دخول: ممنوع.
    expect((await as(citizen, 'POST', 'fishId/gov/visit', body: visit())).$1, 403);
    await as(dev1, 'POST', 'fishId/gov/join', body: {'code': i['code']});

    // مخالفة بدون نوع: مرفوضة.
    expect((await as(dev1, 'POST', 'fishId/gov/visit', body: visit(violations: []))).$1, 400);

    final (s, v) = await as(dev1, 'POST', 'fishId/gov/visit', body: visit());
    expect(s, 200, reason: '$v');
    expect(v['ref'], 'INS-2026-00001');
    expect(v['photos'], 1);
    expect(v['labelName'], 'هامور');
    expect(v['speciesName'], 'ناجل');
    expect(sent.last, contains('INS-2026-00001'));
    final (_, v2) = await as(dev1, 'POST', 'fishId/gov/visit', body: visit(decision: 'ok', photo: false));
    expect(v2['ref'], 'INS-2026-00002');
    expect(v2['violations'], isEmpty);

    final (_, mine) = await as(dev1, 'GET', 'fishId/gov/visits');
    expect((mine['visits'] as List).map((x) => x['ref']), ['INS-2026-00002', 'INS-2026-00001']);
    expect(mine['profile']['today'], 2);

    // لوحة الجهة بمفتاحها.
    expect((await call('GET', 'gov/data')).$1, 401);
    final key = a['key'] as String;
    final (sd, d) = await call('GET', 'gov/data', headers: {'x-gov': key});
    expect(sd, 200);
    expect(d['visits'], 2);
    expect(d['violations'], 1);
    expect(d['mismatch'], 2);
    expect(d['byType']['name'], 1);
    expect(d['topMismatch'].first['label'], 'هامور ← ناجل');
    expect(d['markets'].single['market'], 'البنقلة');
    expect(d['inspectors'].single['visits'], 2);
    expect((d['days'] as List).length, 30);

    // الصورة تنفتح بمفتاح الجهة بس.
    final res = await app.handler(Request('GET', Uri.parse('http://x/api/gov/photo/INS-2026-00001/0?k=$key')));
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'image/jpeg');
    final other = await agency();
    final res2 = await app.handler(Request('GET', Uri.parse('http://x/api/gov/photo/INS-2026-00001/0?k=${other['key']}')));
    expect(res2.statusCode, 404);

    // الجهة تضيف مفتشها من لوحتها، وتقدر توقفه.
    final (sa, added) = await call('POST', 'gov/inspectors', body: {'add': {'name': 'مفتش جديد', 'branch': 'جدة'}}, headers: {'x-gov': key});
    expect(sa, 200);
    expect(added['code'], matches(GovStore.codePattern));
    final (ss, _) = await call('POST', 'gov/inspectors', body: {'id': i['id'], 'update': {'stopped': true}}, headers: {'x-gov': other['key'] as String});
    expect(ss, 404);

    // يبقى محفوظ بعد إعادة التشغيل.
    final reopened = GovStore.open(dir.path);
    expect(reopened.visit('INS-2026-00002')?['decision'], 'ok');
    expect(reopened.byCode(i['code'] as String)?.$2['name'], 'عبدالله الحربي');
  });

  test('page is served and the admin lists agencies', () async {
    final (s, html) = await call('GET', 'gov');
    expect(s, 200);
    expect(html, contains('لوحة الجهة الرسمية'));
    final a = await agency();
    await inspector(a['id'] as String, 'عبدالله الحربي');
    final (_, list) = await call('GET', 'admin/gov', headers: {'authorization': admin});
    expect((list as List).single['inspectors'], hasLength(1));
    expect(list.single['active'], isTrue);
  });

  test('leaving returns the phone to a normal account', () async {
    final a = await agency();
    final i = await inspector(a['id'] as String, 'عبدالله');
    await as(dev1, 'POST', 'fishId/gov/join', body: {'code': i['code']});
    await as(dev1, 'POST', 'fishId/gov/leave');
    final (_, me) = await as(dev1, 'GET', 'fishId/me');
    expect(me['plan'], 'free');
    expect(me['gov'], isNull);
  });

  test('box photo lists species by count and counts as one scan', () async {
    final (s, r) = await as(citizen, 'POST', 'fishId/box', body: {'image': jpeg, 'mediaType': 'image/jpeg'});
    expect(s, 200);
    final box = jsonDecode(r as String) as Map<String, dynamic>;
    expect((box['items'] as List).map((i) => i['id']), ['0391', '0220']);
    expect(box['total_count'], 16);
    expect(accounts.remaining(citizen, now), 2);
  });
}
