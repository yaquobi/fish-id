import 'dart:convert';
import 'dart:typed_data';

import 'package:fish_id/data/fish_id_api.dart';
import 'package:fish_id/data/ksafish.dart';
import 'package:fish_id/data/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ksafish', () {
    test('loads all 447 species and finds by short or full id', () async {
      final db = await Ksafish.load();
      expect(db.species, hasLength(447));
      expect(db.byId('1')?.sci, 'Alopias pelagicus');
      expect(db.byId('0001'), same(db.byId('HWT-FISH-0001')));
      expect(db.byId('9999'), isNull);
    });

    test('search ignores hamza and taa marbuta differences', () async {
      final db = await Ksafish.load();
      expect(db.search('هامور'), isNotEmpty);
      expect(db.search('EPINEPHELUS'), isNotEmpty);
      expect(db.search(''), hasLength(447));
    });

    test('links species plates on KSAFish', () async {
      final db = await Ksafish.load();
      expect(db.species.where((s) => s.plateUrl != null), hasLength(442));
      expect(db.byId('2')?.plateUrl, startsWith('https://ksafish.com/ar/plate/e665cab4-'));
    });
  });

  group('FishResult', () {
    test('parses the server JSON and clamps numbers', () {
      final r = FishResult.fromJson(
        jsonDecode('''{
        "is_fish": true, "subject": "سمكة", "outside_list_guess": "", "photo_tip": "",
        "candidates": [{"id": "0408", "confidence": 140, "reason": "سبب"}],
        "freshness": {"assessable": true, "score": 72.6, "level": "طازجة", "eyes": "", "gills": "", "skin": "", "other": "", "summary": "تمام"}
      }''') as Map<String, dynamic>,
      );
      expect(r.candidates.single.confidence, 100);
      expect(r.freshness!.score, 73);
    });

    test('reads QIM rows, grade and days', () {
      final r = FishResult.fromJson({
        'is_fish': true,
        'freshness': {
          'assessable': true, 'score': 76, 'level': 'طازجة', 'grade': 'A', 'estimated_days_min': 2, 'estimated_days_max': 3,
          'qim_rows': [
            {'key': 'eye_clarity', 'label': 'صفاء العين', 'points': 1, 'max': 2},
            {'key': 'gill_colour', 'label': 'لون الخياشيم', 'points': -1, 'max': 3},
          ],
        },
      });
      final f = r.freshness!;
      expect(f.gradeLabel, 'جيدة (A)');
      expect(f.daysLabel, 'من 2 إلى 3 أيام من الصيد');
      expect(f.rows.map((x) => x.seen), [true, false]);
    });

    test('tolerates missing fields', () {
      final r = FishResult.fromJson({'is_fish': false});
      expect(r.isFish, isFalse);
      expect(r.candidates, isEmpty);
      expect(r.freshness, isNull);
    });
  });

  test('detects media type from bytes', () {
    expect(FishIdApi.mediaTypeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])), 'image/png');
    expect(FishIdApi.mediaTypeOf(Uint8List.fromList(utf8.encode('RIFF\x00\x00\x00\x00WEBPVP8 '))), 'image/webp');
    expect(FishIdApi.mediaTypeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
  });
}
