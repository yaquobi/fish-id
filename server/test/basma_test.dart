import 'dart:io';
import 'dart:typed_data';

import 'package:fish_id_server/basma.dart';
import 'package:fish_id_server/claude.dart';
import 'package:test/test.dart';

void main() {
  final photo = Photo(Uint8List.fromList([1, 2, 3]), 'image/jpeg');
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('basma'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('logs Opus and Basma answers and sums agreement', () async {
    var calls = 0;
    final b = BasmaShadow(File('${dir.path}/s.jsonl'), (_) async {
      calls++;
      return {
        'top': [
          {'id': calls == 1 ? '0365' : '0100', 'score': 0.4},
          {'id': '0377', 'score': 0.2},
          {'id': '0001', 'score': 0.1},
        ],
        'ms': 600,
      };
    });
    final now = DateTime.utc(2026, 11, 4);
    b.compare(photo, '{"is_fish":true,"candidates":[{"id":"0365"},{"id":"0377"}]}', now);
    b.compare(photo, '{"is_fish":true,"candidates":[{"id":"0377"}]}', now);
    // ما نرسل اللي مو سمكة أو بدون مرشحين.
    b.compare(photo, '{"is_fish":false,"candidates":[]}', now);
    b.compare(photo, 'not json', now);
    await settle();
    expect(calls, 2);
    final s = b.summary();
    expect(s['scans'], 2);
    expect(s['same_top1'], 50.0);
    expect(s['basma_top1_in_opus'], 50.0);
    expect(s['opus_top1_in_basma_top3'], 100.0);
    expect(s['avg_ms'], 600);
    expect((s['last'] as List).first['basma'], ['0100', '0377', '0001']);
  });

  test('a failing Basma service never throws', () async {
    final b = BasmaShadow(File('${dir.path}/s.jsonl'), (_) async => throw const SocketException('down'));
    b.compare(photo, '{"candidates":[{"id":"1"}]}', DateTime.now());
    await settle();
    expect(b.summary()['scans'], 0);
  });

  test('http client sends the photo with a content-length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int? length;
    server.listen((req) async {
      length = req.headers.contentLength;
      await req.drain<void>();
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"top":[{"id":"0058","score":0.9}],"ms":5}');
      await req.response.close();
    });
    final b = BasmaShadow.http(dir.path, Uri.parse('http://127.0.0.1:${server.port}/basma'));
    final r = await b.rank(photo);
    await server.close(force: true);
    expect(length, 3);
    expect((r['top'] as List).first['id'], '0058');
  });
}
