import 'dart:math' as math;

/// المدة المتبقية للسمكة من سجل التخزين، بنموذج معدّل التلف النسبي للأسماك الاستوائية
/// (FAO، Huss 1995، الفصل 6؛ ونموذج FSSP-RRS-tropical من DTU):
/// ln(RRS) = 0.12 × T، يعني كل ساعة على حرارة T تعادل exp(0.12·T) ساعة على الثلج.
/// النموذج مختبر من 0 إلى 30 °م فقط، وفوقها نعطي تحذيرًا بدل رقم.
enum Storage {
  ice('على الثلج', 0),
  fridge('في الثلاجة', 4),
  room('في غرفة مكيّفة', 25),
  hot('برّا أو في السيارة', 35),
  frozen('مجمّدة', -18);

  const Storage(this.label, this.temp);
  final String label;
  final double temp;

  /// كم ساعة على الثلج تعادل ساعة واحدة هنا. التجميد يوقف التلف تقريبًا.
  double get rate => temp < 0 ? 0 : math.exp(0.12 * temp);

  /// خارج المدى اللي اختُبر فيه النموذج.
  bool get beyondModel => temp > 30;
}

class StorageStep {
  const StorageStep(this.storage, this.hours);
  final Storage storage;
  final double hours;
}

/// عائلات تتكوّن فيها مادة الهيستامين إذا ما بُرّدت السمكة (التونة والكنعد والسردين والحمام وغيرها).
/// الهيستامين ما يبان بالعين ولا الريحة، وما يزول بالطبخ.
const histamineFamilies = {
  'SCOMBRIDAE',
  'CLUPEIDAE',
  'ENGRAULIDAE',
  'CORYPHAENIDAE',
  'CARANGIDAE',
  'POMATOMIDAE',
  'ISTIOPHORIDAE',
  'XIPHIIDAE',
};

class ShelfLife {
  const ShelfLife._({
    required this.usedDays,
    required this.minDays,
    required this.maxDays,
    required this.discard,
    required this.histamineRisk,
    required this.hotHours,
  });

  /// أيام الثلج اللي انصرفت من عمر السمكة.
  final double usedDays;

  /// المتبقي بالأيام على الثلج: تقدير متحفظ ومتفائل.
  final double minDays;
  final double maxDays;

  /// تحذير قاطع: انتهت المدة، أو بقيت ساعتين وأكثر فوق 30 °م.
  final bool discard;

  /// نوع يتكوّن فيه الهيستامين وبقي ساعتين وأكثر بدون تبريد.
  final bool histamineRisk;
  final double hotHours;

  /// عمر الأسماك البحرية الاستوائية على الثلج متفاوت جدًا في مراجع FAO (من 12 إلى 35 يومًا)،
  /// فناخذ الطرف الأدنى للحذر، ونعرض نطاقًا بدل يوم محدد.
  static const iceDaysLow = 12.0;
  static const iceDaysHigh = 18.0;

  static ShelfLife compute(List<StorageStep> steps, {String family = ''}) {
    var used = 0.0, hot = 0.0, warm = 0.0;
    for (final s in steps) {
      final h = s.hours.clamp(0, 24 * 60).toDouble();
      used += h * s.storage.rate / 24;
      if (s.storage.beyondModel) hot += h;
      if (s.storage.temp > 4.4) warm += h;
    }
    final minDays = math.max(0.0, iceDaysLow - used);
    final maxDays = math.max(0.0, iceDaysHigh - used);
    return ShelfLife._(
      usedDays: used,
      minDays: minDays,
      maxDays: maxDays,
      discard: hot >= 2 || minDays <= 0,
      histamineRisk: histamineFamilies.contains(family.toUpperCase()) && warm >= 2,
      hotHours: hot,
    );
  }

  /// نص المتبقي مثل «من 3 إلى 9 أيام على الثلج».
  String get remainingLabel {
    if (discard) return 'انتهت مدتها الآمنة';
    final lo = minDays.floor(), hi = maxDays.floor();
    if (hi < 1) return 'أقل من يوم';
    if (hi <= 2) return 'يوم أو يومين على الثلج كحد أقصى';
    if (lo < 1) return 'أقل من $hi ${_days(hi)} على الثلج';
    return 'من $lo إلى $hi ${_days(hi)} على الثلج';
  }

  static String _days(int n) => n <= 10 ? 'أيام' : 'يومًا';
}
