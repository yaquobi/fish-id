import 'dart:convert';
import 'dart:typed_data';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/qim.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _post(Object body, {String path = 'api/fishId/identify'}) =>
    Request('POST', Uri.parse('http://x/$path'), body: body is String ? body : jsonEncode(body));

void main() {
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  test('returns the analysis as a JSON string, with or without /api', () async {
    late String gotType;
    final app = FishIdApp(
      identify: (photos) async {
        gotType = photos.single.mediaType;
        return '{"is_fish":true,"n":${photos.single.bytes.length}}';
      },
    );
    for (final path in ['api/fishId/identify', 'fishId/identify']) {
      final res = await app.handler(_post({'image': "decode('$jpeg', 'base64')", 'mediaType': 'image/jpeg'}, path: path));
      expect(res.statusCode, 200);
      final inner = jsonDecode(jsonDecode(await res.readAsString()) as String);
      expect(inner['n'], 7);
    }
    expect(gotType, 'image/jpeg');
  });

  test('rejects unsupported types and empty images with Arabic messages', () async {
    final app = FishIdApp(identify: (_) async => '{}');
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
    final app = FishIdApp(identify: (_) async => '{}', perMinute: 2, clock: () => t);
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
    final body = FishIdAi(key: 'k', speciesList: list).requestBody([
      Photo(Uint8List.fromList([1, 2]), 'image/png'),
    ]);
    expect(body['model'], 'claude-opus-5-5');
    final content = ((body['messages'] as List).single as Map)['content'] as List;
    expect((content.first as Map)['type'], 'image');
  });

  test('accepts up to 3 photos of the same fish', () async {
    var n = 0;
    final app = FishIdApp(
      identify: (photos) async {
        n = photos.length;
        return '{}';
      },
    );
    final one = {'image': jpeg, 'mediaType': 'image/jpeg'};
    var res = await app.handler(
      _post({
        'images': [one, one, one],
      }),
    );
    expect(res.statusCode, 200);
    expect(n, 3);
    res = await app.handler(
      _post({
        'images': [one, one, one, one],
      }),
    );
    expect(jsonDecode(await res.readAsString())['code'], 'fishid_count');
  });

  group('QIM', () {
    Map<String, dynamic> f(Map<String, int> qim, {bool assessable = true}) => {
      'assessable': assessable,
      'qim': {for (final a in qimAttributes) a.key: qim[a.key] ?? -1},
    };

    test('perfectly fresh fish scores 100 and grade E', () {
      final x = f({for (final a in qimAttributes) a.key: 0});
      completeFreshness(x);
      expect([x['score'], x['grade'], x['level'], x['qim_seen']], [100, 'E', 'طازجة جدًا', qimAttributes.length]);
    });

    test('score uses only the parts that were seen', () {
      final x = f({'eye_clarity': 2, 'eye_shape': 2, 'skin_appearance': 0, 'gill_colour': -1});
      completeFreshness(x);
      expect(x['qim_max'], 6);
      expect(x['score'], 33);
      expect(x['grade'], 'X');
      expect((x['qim_rows'] as List).where((r) => r['points'] == -1), hasLength(qimAttributes.length - 3));
    });

    test('too few visible parts is not assessable', () {
      final x = f({'skin_appearance': 0, 'abdomen': 0, 'skin_mucus': 0});
      completeFreshness(x);
      expect(x['assessable'], false);
      expect(x['level'], 'غير معروف');
    });

    test('points above the max are clamped', () {
      final x = f({'eye_clarity': 9, 'eye_shape': 0, 'gill_colour': 0});
      completeFreshness(x);
      expect(x['qim_total'], 2);
    });
  });
}
