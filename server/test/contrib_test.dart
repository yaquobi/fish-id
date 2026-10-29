import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/contrib.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _post(Object body) => Request('POST', Uri.parse('http://x/api/fishId/contribute'), body: jsonEncode(body));

void main() {
  // JPEG صغير: SOI، ثم APP0 (يبقى)، ثم APP1 فيه "GPS" (ينحذف)، ثم تعليق (ينحذف)، ثم SOS والبيانات.
  final jpeg = Uint8List.fromList([
    0xFF, 0xD8, //
    0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46,
    0xFF, 0xE1, 0x00, 0x05, 0x47, 0x50, 0x53,
    0xFF, 0xFE, 0x00, 0x03, 0x41,
    0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9,
  ]);
  Map<String, Object> image() => {'image': "decode('${base64Encode(jpeg)}', 'base64')", 'mediaType': 'image/jpeg'};

  test('strips EXIF and comments from JPEG but keeps the image data', () {
    final out = stripMetadata(jpeg, 'image/jpeg');
    expect(out, [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46, 0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]);
    expect(String.fromCharCodes(out).contains('GPS'), isFalse);
  });

  test('saves a consented contribution with clean metadata', () async {
    final dir = Directory.systemTemp.createTempSync('contrib');
    final sent = <String>[];
    final app = FishIdApp(
      identify: null,
      contrib: ContribStore(dir.path),
      speciesNames: const {'0220': 'شعور'},
      notify: sent.add,
      clock: () => DateTime.utc(2026, 10, 28, 9),
    );
    final res = await app.handler(
      _post({
        'images': [image()],
        'species': '0220',
        'speciesConfirmed': true,
        'days': 2,
        'storage': 'ice',
        'predicted': ['0220', '0219'],
        'score': 81,
        'consent': true,
      }),
    );
    expect(res.statusCode, 200);
    final id = (jsonDecode(await res.readAsString()) as Map)['id'] as String;
    final folder = Directory('${dir.path}/2026-10-28/$id');
    final meta = jsonDecode(File('${folder.path}/meta.json').readAsStringSync()) as Map;
    expect(meta['species'], '0220');
    expect(meta['species_confirmed'], true);
    expect(meta['days_since_catch'], 2);
    expect(meta['storage'], 'ice');
    expect(String.fromCharCodes(File('${folder.path}/1.jpg').readAsBytesSync()).contains('GPS'), isFalse);
    expect(sent.single, contains('شعور (0220) · 1 صور · 2 يوم من الصيد'));
    dir.deleteSync(recursive: true);
  });

  test('refuses without consent, bad species ids, or when switched off', () async {
    final dir = Directory.systemTemp.createTempSync('contrib');
    final app = FishIdApp(identify: null, contrib: ContribStore(dir.path));
    expect(
      (await app.handler(
        _post({
          'images': [image()],
          'consent': false,
        }),
      )).statusCode,
      400,
    );
    expect(
      (await app.handler(
        _post({
          'images': [image()],
          'consent': true,
          'species': '../x',
        }),
      )).statusCode,
      400,
    );
    expect(
      (await FishIdApp(identify: null).handler(
        _post({
          'images': [image()],
          'consent': true,
        }),
      )).statusCode,
      503,
    );
    expect(dir.listSync(), isEmpty);
    dir.deleteSync(recursive: true);
  });
}
