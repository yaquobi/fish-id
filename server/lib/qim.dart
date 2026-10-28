/// طريقة مؤشر الجودة (QIM) بالعلامات اللي تبان في الصورة فقط.
/// كل علامة لها نقاط عيب: 0 = طازجة تمامًا، وكل ما زادت النقاط قلّت الطزاجة.
/// النموذج يعطي النقاط (أو -1 إذا الجزء ما يبان)، والحساب هنا ثابت حتى تتطابق الدرجة مع النقاط دايمًا.
/// مبني على مخططات QIM المنشورة (FAO: Assessment of fish quality) مع حذف الرائحة والصلابة لأنها ما تنقاس من صورة.
library;

class QimAttribute {
  const QimAttribute(this.key, this.label, this.max, this.levels);
  final String key;
  final String label;
  final int max;

  /// وصف كل درجة من 0 إلى [max]، بالإنجليزي للنموذج.
  final List<String> levels;
}

const qimAttributes = [
  QimAttribute('skin_appearance', 'لمعة الجلد', 2, ['bright, shining, iridescent', 'slightly dull, losing shine', 'dull, faded, bleached']),
  QimAttribute('skin_mucus', 'مخاط الجلد', 2, ['clear, transparent, thin', 'milky, slightly cloudy', 'yellowish, thick, clotted']),
  QimAttribute('eye_clarity', 'صفاء العين', 2, ['clear, black pupil, bright', 'slightly cloudy or opaque', 'milky, grey, opaque']),
  QimAttribute('eye_shape', 'شكل العين', 2, ['convex, bulging', 'flat', 'sunken, concave']),
  QimAttribute('gill_colour', 'لون الخياشيم', 3, [
    'bright red / characteristic',
    'less bright, slightly faded',
    'brownish, discoloured',
    'brown or grey, bleached',
  ]),
  QimAttribute('gill_mucus', 'مخاط الخياشيم', 2, ['clear, transparent', 'milky, opaque', 'brown, thick, clotted']),
  QimAttribute('abdomen', 'البطن', 2, ['firm, intact', 'soft, slightly swollen', 'burst, very soft']),
  QimAttribute('blood_discolouration', 'الدم وتغيّر اللون', 2, [
    'none, bright blood if any',
    'some brownish spots or bruising',
    'extensive brown blood, discoloured patches',
  ]),
];

int get qimMax => qimAttributes.fold(0, (a, b) => a + b.max);

/// وصف المخطط للتعليمات اللي تنرسل للنموذج.
String qimPromptTable() => [
  for (final a in qimAttributes) '- ${a.key} (0-${a.max}): ${[for (var i = 0; i < a.levels.length; i++) '$i = ${a.levels[i]}'].join('; ')}',
].join('\n');

/// يكمّل كائن الطزاجة من النقاط: الدرجة من 100، والمستوى، والتصنيف الأوروبي.
/// الدرجة نسبة من العلامات اللي انشافت فعلًا، فإذا ما انشاف إلا القليل تنخفض الثقة ولا تتغير الدرجة.
void completeFreshness(Map<String, dynamic> f) {
  final points = (f['qim'] as Map?)?.cast<String, dynamic>() ?? {};
  var sum = 0, max = 0, seen = 0;
  final rows = <Map<String, Object>>[];
  for (final a in qimAttributes) {
    final raw = points[a.key];
    final v = raw is num ? raw.round() : -1;
    if (v < 0) {
      rows.add({'key': a.key, 'label': a.label, 'points': -1, 'max': a.max});
      continue;
    }
    final p = v.clamp(0, a.max);
    sum += p;
    max += a.max;
    seen++;
    rows.add({'key': a.key, 'label': a.label, 'points': p, 'max': a.max});
  }
  f['qim_rows'] = rows;
  f['qim_seen'] = seen;
  f['qim_total'] = sum;
  f['qim_max'] = max;

  // نحتاج على الأقل 3 علامات منها العين أو الخياشيم، وإلا التقييم ما يعتمد عليه.
  final hasKey = rows.any((r) => (r['key'] == 'eye_clarity' || r['key'] == 'gill_colour') && (r['points'] as int) >= 0);
  if (f['assessable'] != true || seen < 3 || !hasKey) {
    f['assessable'] = false;
    f['score'] = 0;
    f['level'] = 'غير معروف';
    f['grade'] = '';
    return;
  }
  final ratio = sum / max;
  final score = (100 * (1 - ratio)).round();
  f['score'] = score;
  f['level'] = score >= 85
      ? 'طازجة جدًا'
      : score >= 65
      ? 'طازجة'
      : score >= 40
      ? 'متوسطة'
      : 'غير طازجة';
  // تقريب لدرجات الاتحاد الأوروبي للطزاجة: Extra و A و B، وتحتها غير صالحة للبيع.
  f['grade'] = ratio <= .15
      ? 'E'
      : ratio <= .35
      ? 'A'
      : ratio <= .6
      ? 'B'
      : 'X';
}
