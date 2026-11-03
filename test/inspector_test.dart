import 'package:fish_id/data/box.dart';
import 'package:fish_id/data/ksafish.dart';
import 'package:fish_id/data/reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shop label matches the species local names, ignoring the article', () async {
    final db = await Ksafish.load();
    final hamour = db.byId('0373')!; // أبوخمام، هامور سمان
    expect(Ksafish.labelMatches('هامور', hamour), isTrue);
    expect(Ksafish.labelMatches('الهامور', hamour), isTrue);
    expect(Ksafish.labelMatches('شعري', hamour), isFalse);
    expect(Ksafish.labelMatches('', hamour), isNull);
  });

  test('box result reads counts, clamps bad values and totals', () {
    final r = BoxResult.fromJson({
      'is_fish_load': true,
      'items': [
        {'id': '0391', 'name': 'هامور', 'count': 12, 'count_min': 10, 'count_max': 15, 'size': 'medium', 'freshness': 82, 'confidence': 80, 'note': ''},
        {'id': '', 'name': 'غير معروف', 'count': '3', 'count_min': 3, 'count_max': 3, 'size': 'small', 'freshness': 500, 'confidence': 10, 'note': ''},
      ],
      'overall_freshness': -1,
      'summary': 'x',
      'photo_tip': '',
    });
    expect(r.total, 15);
    expect(r.items[1].freshness, 100);
    expect(r.items[0].rangeLabel, '10–15');
    expect(r.items[1].rangeLabel, '3');
    expect(r.items[0].sizeLabel, 'وسط');
  });

  test('inspection report and auction sheet render as PDF', () async {
    final pdf = await Reports.inspection({
      'ref': 'INS-2026-00001',
      'at': '2026-11-03T06:42:00Z',
      'inspectorName': 'عبدالله الحربي',
      'agency': 'وزارة البيئة والمياه والزراعة',
      'market': 'البنقلة',
      'city': 'جدة',
      'shop': 'محل البحر الأحمر 14',
      'labelName': 'هامور',
      'labelPrice': 95,
      'speciesName': 'ناجل',
      'sci': 'Plectropomus pessuliferus',
      'confidence': 82,
      'freshness': 71,
      'match': false,
      'decision': 'violation',
      'violations': ['name'],
      'note': 'تم التنبيه',
      'lat': 21.4858,
      'lng': 39.1925,
    });
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(Reports.when(DateTime.utc(2026, 11, 3, 6, 42)), '2026-11-03 09:42');

    final sheet = await Reports.haraj(BoxResult.demo, seller: 'قارب أبو فهد', market: 'البنقلة');
    expect(String.fromCharCodes(sheet.take(4)), '%PDF');
  });
}
