import 'dart:convert';
import 'dart:typed_data';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _post(Object body, {String path = 'api/fishId/identify'}) =>
    Request('POST', Uri.parse('http://x/$path'), body: body is String ? body : jsonEncode(body));

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  test('returns the analysis as a JSON string, with or without /api', () async {
    late String gotType;
    final app = FishIdApp(identify: (img, type) async {
      gotType = type;
      return '{"is_fish":true,"n":${img.length}}';
    });
    for (final path in ['api/fishId/identify', 'fishId/identify']) {
      final res = await app.handler(_post({'image': "decode('$jpeg', 'base64')", 'mediaType': 'image/jpeg'}, path: path));
      expect(res.statusCode, 200);
      final inner = jsonDecode(jsonDecode(await res.readAsString()) as String);
      expect(inner['n'], 7);
    }
    expect(gotType, 'image/jpeg');
  });

  test('rejects unsupported types and empty images with Arabic messages', () async {
    final app = FishIdApp(identify: (_, _) async => '{}');
    var res = await app.handler(_post({'image': jpeg, 'mediaType': 'image/gif'}));
    expect(res.statusCode, 400);
    expect(jsonDecode(await res.readAsString())['code'], 'fishid_type');
    res = await app.handler(_post({'image': '', 'mediaType': 'image/png'}));
    expect(jsonDecode(await res.readAsString())['code'], 'fishid_empty');
    res = await app.handler(_post('not json'));
    expect(res.statusCode, 400);
  });

  test('without a key the service says it is off', () async {
    final app = FishIdApp(identify: null);
    final res = await app.handler(_post({'image': jpeg, 'mediaType': 'image/jpeg'}));
    expect(res.statusCode, 503);
    expect(jsonDecode(await res.readAsString())['code'], 'fishid_off');
    final health = await app.handler(Request('GET', Uri.parse('http://x/api/health')));
    expect(jsonDecode(await health.readAsString())['ready'], false);
  });

  test('applies the per-minute limit and resets the next minute', () async {
    var t = DateTime(2026, 10, 28, 1, 0, 0);
    final app = FishIdApp(identify: (_, _) async => '{}', perMinute: 2, clock: () => t);
    Future<int> call() async => (await app.handler(_post({'image': jpeg, 'mediaType': 'image/jpeg'}))).statusCode;
    expect([await call(), await call(), await call()], [200, 200, 429]);
    t = t.add(const Duration(minutes: 1));
    expect(await call(), 200);
  });

  test('builds the species list and request body', () {
    final list = FishIdAi.speciesListFrom({
      'species': [
        {'id': 'HWT-FISH-0408', 'sci': 'Sphyraena barracuda', 'en': 'Great barracuda', 'red': 'براكودا | عقام', 'gulf': 'جد'},
      ],
    });
    expect(list, '0408|Sphyraena barracuda|Great barracuda|براكودا | عقام | جد');
    final body = FishIdAi(key: 'k', speciesList: list).requestBody(Uint8List.fromList([1, 2]), 'image/png');
    expect(body['model'], 'claude-opus-5-5');
    final content = ((body['messages'] as List).single as Map)['content'] as List;
    expect((content.first as Map)['type'], 'image');
  });
}
