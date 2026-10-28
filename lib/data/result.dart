import '../l10n.dart';

/// نتيجة تحليل الصورة كما يرجعها خادم FISH ID (fishId/identify).
class Candidate {
  const Candidate(this.id, this.confidence, this.reason);
  final String id;
  final int confidence;
  final String reason;
}

/// علامة واحدة من علامات QIM: نقاط العيب من [max]، و-1 إذا الجزء ما بان في الصورة.
class QimRow {
  const QimRow(this.key, this.label, this.points, this.max);
  final String key;
  final String label;
  final int points;
  final int max;

  bool get seen => points >= 0;

  /// اسم العلامة بلغة التطبيق. الخادم يرسله بالعربي.
  String get title => L10n.en ? _en[key] ?? key : label;

  static const _en = {
    'skin_appearance': 'Skin shine',
    'skin_mucus': 'Skin slime',
    'eye_clarity': 'Eye clarity',
    'eye_shape': 'Eye shape',
    'gill_colour': 'Gill colour',
    'gill_mucus': 'Gill slime',
    'abdomen': 'Belly',
    'blood_discolouration': 'Blood and discolouration',
  };
}

class Freshness {
  const Freshness({
    required this.assessable,
    required this.score,
    required this.level,
    required this.grade,
    required this.rows,
    required this.daysMin,
    required this.daysMax,
    required this.eyes,
    required this.gills,
    required this.skin,
    required this.other,
    required this.manualChecks,
    required this.summary,
  });

  final bool assessable;
  final int score;
  final String level;

  /// تقريب لدرجات الاتحاد الأوروبي: E (ممتازة) أو A أو B، و X غير صالحة للبيع.
  final String grade;
  final List<QimRow> rows;

  /// أيام تقريبية من الصيد على الثلج، و-1 إذا ما تقدّر.
  final int daysMin;
  final int daysMax;
  final String eyes;
  final String gills;
  final String skin;
  final String other;
  final String manualChecks;
  final String summary;

  /// مستوى الطزاجة بلغة التطبيق، بنفس حدود الخادم (server/lib/qim.dart).
  String get levelLabel {
    if (!L10n.en) return level;
    if (!assessable) return 'Unknown';
    return score >= 85
        ? 'Very fresh'
        : score >= 65
        ? 'Fresh'
        : score >= 40
        ? 'Fair'
        : 'Not fresh';
  }

  String get gradeLabel => switch (grade) {
    'E' => tr('ممتازة (Extra)', 'Excellent (Extra)'),
    'A' => tr('جيدة (A)', 'Good (A)'),
    'B' => tr('مقبولة (B)', 'Acceptable (B)'),
    'X' => tr('غير صالحة للبيع', 'Not fit for sale'),
    _ => '',
  };

  String get daysLabel {
    if (daysMin < 0 || daysMax < 0) return '';
    if (daysMax == 0) return tr('نفس يوم الصيد', 'Caught today');
    if (daysMin == daysMax) {
      return daysMin == 1
          ? tr('يوم تقريبًا من الصيد', 'About 1 day since catch')
          : tr('$daysMin أيام تقريبًا من الصيد', 'About $daysMin days since catch');
    }
    return tr('من $daysMin إلى $daysMax أيام من الصيد', '$daysMin to $daysMax days since catch');
  }
}

class FishResult {
  const FishResult({
    required this.isFish,
    required this.subject,
    required this.candidates,
    required this.outsideListGuess,
    required this.freshness,
    required this.photoTip,
  });

  final bool isFish;
  final String subject;
  final List<Candidate> candidates;
  final String outsideListGuess;
  final Freshness? freshness;
  final String photoTip;

  factory FishResult.fromJson(Map<String, dynamic> j) {
    final f = j['freshness'] as Map<String, dynamic>?;
    String s(Map<String, dynamic> m, String k) => m[k]?.toString() ?? '';
    int n(Object? v) => (v is num ? v.round() : int.tryParse('$v') ?? 0).clamp(0, 100);
    int i(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? -1;
    return FishResult(
      isFish: j['is_fish'] != false,
      subject: s(j, 'subject'),
      candidates: [
        for (final c in (j['candidates'] as List? ?? const []))
          Candidate('${(c as Map)['id']}', n(c['confidence']), c['reason']?.toString() ?? ''),
      ],
      outsideListGuess: s(j, 'outside_list_guess'),
      freshness: f == null
          ? null
          : Freshness(
              assessable: f['assessable'] == true,
              score: n(f['score']),
              level: s(f, 'level'),
              grade: s(f, 'grade'),
              rows: [
                for (final r in (f['qim_rows'] as List? ?? const []))
                  QimRow('${(r as Map)['key']}', '${r['label']}', i(r['points']), i(r['max'])),
              ],
              daysMin: i(f['estimated_days_min']),
              daysMax: i(f['estimated_days_max']),
              eyes: s(f, 'eyes'),
              gills: s(f, 'gills'),
              skin: s(f, 'skin'),
              other: s(f, 'other'),
              manualChecks: s(f, 'manual_checks'),
              summary: s(f, 'summary'),
            ),
      photoTip: s(j, 'photo_tip'),
    );
  }

  /// مثال ثابت لوضع التجربة، لما يكون التطبيق مبني بدون خادم.
  static const demo = FishResult(
    isFish: true,
    subject: 'سمكة كاملة على ثلج في سوق السمك',
    candidates: [
      Candidate('0408', 86, 'جسم طويل أسطواني، فك سفلي بارز وأسنان كبيرة، بقع داكنة متفرقة على الجانب.'),
      Candidate('0412', 9, 'نفس الجنس لكن البقع أوضح عند هذا النوع.'),
    ],
    outsideListGuess: '',
    freshness: Freshness(
      assessable: true,
      score: 82,
      level: 'طازجة',
      grade: 'A',
      rows: [
        QimRow('skin_appearance', 'لمعة الجلد', 0, 2),
        QimRow('skin_mucus', 'مخاط الجلد', 1, 2),
        QimRow('eye_clarity', 'صفاء العين', 0, 2),
        QimRow('eye_shape', 'شكل العين', 1, 2),
        QimRow('gill_colour', 'لون الخياشيم', -1, 3),
        QimRow('gill_mucus', 'مخاط الخياشيم', -1, 2),
        QimRow('abdomen', 'البطن', 0, 2),
        QimRow('blood_discolouration', 'الدم وتغيّر اللون', 0, 2),
      ],
      daysMin: 1,
      daysMax: 2,
      eyes: 'العين صافية لكنها مسطّحة قليلًا.',
      gills: 'الخياشيم غير ظاهرة في الصورة.',
      skin: 'الجلد لامع، والمخاط صار حليبيًا خفيفًا.',
      other: '',
      manualChecks: 'شمّ الخياشيم واضغط على اللحم: لازم يرجع بسرعة.',
      summary: 'تبدو طازجة، صوّر الخياشيم مفتوحة للتأكد.',
    ),
    photoTip: 'أضف صورة للخياشيم مفتوحة لتقييم أدق.',
  );
}
