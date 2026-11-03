import '../l10n.dart';

/// نوع واحد في صورة الصندوق: الاسم والعدد التقريبي والحجم والطزاجة.
class BoxItem {
  const BoxItem({
    required this.id,
    required this.name,
    required this.count,
    required this.countMin,
    required this.countMax,
    required this.size,
    required this.freshness,
    required this.confidence,
    required this.note,
  });

  /// رقم حوات (4 أرقام)، وفاضي إذا النوع مو في الموسوعة.
  final String id;
  final String name;
  final int count;
  final int countMin;
  final int countMax;

  /// small أو medium أو large.
  final String size;

  /// 0 إلى 100، و -1 إذا ما قدر يحكم.
  final int freshness;
  final int confidence;
  final String note;

  String get sizeLabel => switch (size) {
    'small' => tr('صغير', 'Small'),
    'large' => tr('كبير', 'Large'),
    _ => tr('وسط', 'Medium'),
  };

  String get rangeLabel => countMin == countMax || countMax <= 0 ? '$count' : '$countMin–$countMax';

  BoxItem copyWith({int? count, String? name}) => BoxItem(
    id: id,
    name: name ?? this.name,
    count: count ?? this.count,
    countMin: countMin,
    countMax: countMax,
    size: size,
    freshness: freshness,
    confidence: confidence,
    note: note,
  );
}

/// نتيجة صورة الصندوق للدلّال (POST fishId/box).
class BoxResult {
  const BoxResult({
    required this.isFish,
    required this.items,
    required this.overallFreshness,
    required this.summary,
    required this.photoTip,
  });

  final bool isFish;
  final List<BoxItem> items;
  final int overallFreshness;
  final String summary;
  final String photoTip;

  int get total => items.fold(0, (t, i) => t + i.count);

  factory BoxResult.fromJson(Map<String, dynamic> j) {
    int n(Object? v, [int def = 0]) => v is num ? v.round() : int.tryParse('$v') ?? def;
    return BoxResult(
      isFish: j['is_fish_load'] != false,
      items: [
        for (final i in (j['items'] as List? ?? const []).whereType<Map>())
          BoxItem(
            id: '${i['id'] ?? ''}',
            name: '${i['name'] ?? ''}',
            count: n(i['count']).clamp(0, 100000),
            countMin: n(i['count_min']),
            countMax: n(i['count_max']),
            size: '${i['size'] ?? 'medium'}',
            freshness: n(i['freshness'], -1).clamp(-1, 100),
            confidence: n(i['confidence']).clamp(0, 100),
            note: '${i['note'] ?? ''}',
          ),
      ],
      overallFreshness: n(j['overall_freshness'], -1).clamp(-1, 100),
      summary: '${j['summary'] ?? ''}',
      photoTip: '${j['photo_tip'] ?? ''}',
    );
  }

  static const demo = BoxResult(
    isFish: true,
    items: [
      BoxItem(
        id: '0391',
        name: 'هامور',
        count: 12,
        countMin: 10,
        countMax: 15,
        size: 'medium',
        freshness: 82,
        confidence: 80,
        note: 'بعضها تحت الثلج',
      ),
      BoxItem(
        id: '0220',
        name: 'ناجل',
        count: 4,
        countMin: 3,
        countMax: 5,
        size: 'large',
        freshness: 78,
        confidence: 70,
        note: '',
      ),
      BoxItem(
        id: '0129',
        name: 'شعري',
        count: 9,
        countMin: 7,
        countMax: 11,
        size: 'small',
        freshness: 74,
        confidence: 75,
        note: '',
      ),
    ],
    overallFreshness: 79,
    summary: 'وضع التجربة: صندوق طازج بشكل عام، والعدد تقريبي.',
    photoTip: '',
  );
}
