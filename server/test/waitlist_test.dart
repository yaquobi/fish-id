import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/waitlist.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  final t = DateTime.utc(2026, 10, 30, 12);
  setUp(() => dir = Directory.systemTemp.createTempSync('waitlist'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Response> join(FishIdApp app, Map body, {String ip = '1.2.3.4'}) async => app.handler(Request('POST', Uri.parse('http://x/api/waitlist'), body: jsonEncode(body), headers: {'x-forwarded-for': ip}));

  test('emails and Saudi mobiles are normalized, anything else is refused', () {
    expect(Waitlist.normalize(' Ali@Example.COM '), (kind: 'email', value: 'ali@example.com'));
    expect(Waitlist.normalize('0551234567'), (kind: 'phone', value: '+966551234567'));
    expect(Waitlist.normalize('+966 55 123 4567'), (kind: 'phone', value: '+966551234567'));
    expect(Waitlist.normalize('00966551234567'), (kind: 'phone', value: '+966551234567'));
    expect(Waitlist.normalize('٠٥٥١٢٣٤٥٦٧'), (kind: 'phone', value: '+966551234567'));
    expect(Waitlist.normalize('0112345678'), isNull);
    expect(Waitlist.normalize('ali@'), isNull);
    expect(Waitlist.normalize(''), isNull);
  });

  test('signups need consent, are kept once, survive a restart and show in the admin panel', () async {
    final told = <String>[];
    final app = FishIdApp(identify: null, waitlist: Waitlist.open(dir.path), adminToken: 'secret-token', notify: told.add, clock: () => t);
    expect((await join(app, {'contact': 'ali@example.com'})).statusCode, 400);
    final ok = await join(app, {'contact': 'ali@example.com', 'consent': true, 'name': 'علي', 'src': 'fb_ad'});
    expect(jsonDecode(await ok.readAsString()), {'ok': true, 'new': true});
    expect(jsonDecode(await (await join(app, {'contact': 'ALI@example.com', 'consent': true})).readAsString())['new'], false);
    expect((await join(app, {'contact': '0551234567', 'consent': true}, ip: '5.6.7.8')).statusCode, 200);
    expect((await join(app, {'contact': 'not a contact', 'consent': true})).statusCode, 400);
    expect(told.single, contains('المجموع: 1'));

    final again = Waitlist.open(dir.path);
    expect(again.count, 2);
    final res = await app.handler(Request('GET', Uri.parse('http://x/api/admin/waitlist'), headers: {'authorization': 'Bearer secret-token'}));
    final r = jsonDecode(await res.readAsString()) as Map;
    expect([r['count'], r['today'], r['emails'], r['phones']], [2, 2, 1, 1]);
    expect((r['items'] as List).first['contact'], '+966551234567');

    final id = (r['items'] as List).first['id'];
    final del = await app.handler(Request('POST', Uri.parse('http://x/api/admin/waitlist'), body: jsonEncode({'delete': id}), headers: {'authorization': 'Bearer secret-token'}));
    expect(jsonDecode(await del.readAsString())['count'], 1);
  });

  test('one address cannot flood the list', () async {
    final app = FishIdApp(identify: null, waitlist: Waitlist.open(dir.path), clock: () => t);
    for (var i = 0; i < 5; i++) {
      expect((await join(app, {'contact': 'u$i@example.com', 'consent': true})).statusCode, 200);
    }
    expect((await join(app, {'contact': 'u9@example.com', 'consent': true})).statusCode, 429);
  });
}
