/// نتيجة تحليل الصورة كما يرجعها خادم حوات (نقطة fishId.identify).
class Candidate {
  const Candidate(this.id, this.confidence, this.reason);
  final String id;
  final int confidence;
  final String reason;
}

class Freshness {
  const Freshness({
    required this.assessable,
    required this.score,
    required this.level,
    required this.eyes,
    required this.gills,
    required this.skin,
    required this.other,
    required this.summary,
  });

  final bool assessable;
  final int score;
  final String level;
  final String eyes;
  final String gills;
  final String skin;
  final String other;
  final String summary;
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
              eyes: s(f, 'eyes'),
              gills: s(f, 'gills'),
              skin: s(f, 'skin'),
              other: s(f, 'other'),
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
      eyes: 'العين صافية ومحدّبة قليلًا.',
      gills: 'الخياشيم غير ظاهرة في الصورة.',
      skin: 'الجلد لامع والقشور متماسكة.',
      other: '',
      summary: 'تبدو طازجة، يُفضّل فحص الخياشيم للتأكد.',
    ),
    photoTip: '',
  );
}
