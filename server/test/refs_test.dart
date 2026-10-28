import 'dart:io';

import 'package:fish_id_server/refs.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  final data = {
    'species': [
      {'id': 'HWT-FISH-0363', 'sci': 'Epinephelus areolatus', 'en': 'Areolate grouper'},
      {'id': 'HWT-FISH-0365', 'sci': 'Epinephelus coioides', 'en': 'Orange-spotted grouper'},
      {'id': 'HWT-FISH-0368', 'sci': 'Epinephelus fuscoguttatus', 'en': ''},
      {'id': 'HWT-FISH-0379', 'sci': 'Plectropomus areolatus', 'en': ''},
      {'id': 'HWT-FISH-0220', 'sci': 'Lethrinus nebulosus', 'en': ''},
    ],
  };

  setUp(() {
    dir = Directory.systemTemp.createTempSync('refs');
    for (final id in ['0363', '0365', '0368', '0379']) {
      Directory('${dir.path}/$id').createSync();
      File('${dir.path}/$id/1.jpg').writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('missing or empty folder turns the stage off', () {
    expect(RefLibrary.load('${dir.path}/nope', data), isNull);
    expect(RefLibrary.load(Directory.systemTemp.createTempSync('empty').path, data), isNull);
  });

  test('pool puts candidates first, then their congeners that have photos', () {
    final lib = RefLibrary.load(dir.path, data)!;
    expect(lib.speciesCount, 4);
    // 0220 has no photos, so it is skipped; 0379 is another genus, so only the candidate itself comes in.
    expect(lib.poolFor(['0368', '0220']), ['0368', '0363', '0365']);
    expect(lib.poolFor(['0379', '0365'], max: 3), ['0379', '0365', '0363']);
    expect(lib.label('0365'), 'Epinephelus coioides (Orange-spotted grouper)');
  });

  test('message labels every reference id before its photos', () async {
    final lib = RefLibrary.load(dir.path, data)!;
    final content = await refsContent(lib, [], ['0363', '0365']);
    final texts = [
      for (final c in content)
        if (c['type'] == 'text') c['text'],
    ];
    expect(texts, contains('Reference id 0363: Epinephelus areolatus (Areolate grouper)'));
    expect(content.where((c) => c['type'] == 'image').length, 2);
  });
}
