import 'package:flutter/material.dart';

import '../data/shelf_life.dart';
import '../theme.dart';

/// حاسبة المدة المتبقية: المستخدم يختار وين انحفظت السمكة وكم مدة، ونحسب الباقي بنموذج الحرارة.
/// أدق من الصورة في تقدير الأيام، لأن التلف يعتمد على الحرارة أكثر من أي شيء ثاني.
class ShelfLifeCard extends StatefulWidget {
  const ShelfLifeCard({super.key, this.family = '', this.photoDays});

  /// عائلة النوع بالإنجليزي من الموسوعة، لتحذير الهيستامين.
  final String family;

  /// متوسط الأيام المقدّرة من الصورة، نبدأ فيه كقيمة أولى إذا موجود.
  final double? photoDays;

  @override
  State<ShelfLifeCard> createState() => _ShelfLifeCardState();
}

class _ShelfLifeCardState extends State<ShelfLifeCard> {
  static const _maxSteps = 4;
  static const _durations = <double>[1, 2, 3, 6, 12, 24, 48, 72, 96, 120, 168, 240, 336];

  late final List<StorageStep> _steps = [StorageStep(Storage.ice, _nearest((widget.photoDays ?? 1) * 24))];

  static double _nearest(double h) => _durations.reduce((a, b) => (a - h).abs() <= (b - h).abs() ? a : b);

  static String _durationLabel(double h) {
    if (h < 24) {
      final n = h.round();
      return n == 1 ? 'ساعة' : (n == 2 ? 'ساعتين' : '$n ساعات');
    }
    final d = (h / 24).round();
    return d == 1 ? 'يوم' : (d == 2 ? 'يومين' : (d <= 10 ? '$d أيام' : '$d يومًا'));
  }

  @override
  Widget build(BuildContext context) {
    final r = ShelfLife.compute(_steps, family: widget.family);
    final color = r.discard ? AppColors.bad : (r.minDays < 3 ? AppColors.warn : AppColors.good);
    final prone = histamineFamilies.contains(widget.family.toUpperCase());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.thermostat_outlined, color: AppColors.navy),
                SizedBox(width: 8),
                Expanded(
                  child: Text('كم باقي لها؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'اختر وين انحفظت السمكة من وقت الصيد وكم مدة. الحرارة تحدد سرعة التلف أكثر من أي شيء ثاني.',
              style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 12),
            for (final (i, s) in _steps.indexed)
              Padding(
                key: ObjectKey(s),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<Storage>(
                        initialValue: s.storage,
                        isExpanded: true,
                        decoration: _field(),
                        items: [for (final st in Storage.values) DropdownMenuItem(value: st, child: Text(st.label))],
                        onChanged: (v) => setState(() => _steps[i] = StorageStep(v!, s.hours)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<double>(
                        initialValue: s.hours,
                        isExpanded: true,
                        decoration: _field(),
                        items: [for (final h in _durations) DropdownMenuItem(value: h, child: Text(_durationLabel(h)))],
                        onChanged: (v) => setState(() => _steps[i] = StorageStep(s.storage, v!)),
                      ),
                    ),
                    if (_steps.length > 1)
                      IconButton(
                        tooltip: 'احذف',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() => _steps.removeAt(i)),
                      ),
                  ],
                ),
              ),
            if (_steps.length < _maxSteps)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _steps.add(StorageStep(Storage.room, 1))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('أضف مرحلة (مثل الطريق للبيت)'),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.remainingLabel,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.discard
                        ? (r.hotHours >= 2
                              ? 'بقيت ساعتين أو أكثر فوق 30 °م. في هالحرارة التلف سريع جدًا، والأسلم لا تشتريها ولا تاكلها.'
                              : 'حسب سجل التخزين، صرفت السمكة مدتها كلها. لا تشتريها.')
                        : 'صرفت ما يعادل ${_usedLabel(r.usedDays)} على الثلج. حطها على الثلج أو في الثلاجة على طول.',
                    style: const TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
            if (prone) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: r.histamineRisk ? AppColors.bad : AppColors.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.histamineRisk
                          ? 'خطر الهيستامين: هذا النوع بقي ساعتين أو أكثر بدون تبريد. الهيستامين ما يبان بالشكل ولا الريحة وما يزول بالطبخ، ويسبب تسممًا.'
                          : 'هذا النوع من الأسماك اللي يتكوّن فيها الهيستامين إذا ما بُرّدت. اشترها على الثلج وبرّدها على طول.',
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'محسوبة بنموذج FAO وجامعة DTU لتلف الأسماك الاستوائية، المختبر من 0 إلى 30 °م. تقدير تقريبي، وليس بديلًا عن الفحص.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  static String _usedLabel(double d) {
    if (d < 1) return 'أقل من يوم';
    final n = (d * 2).round() / 2;
    final t = n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    return n == 1 ? 'يوم واحد' : (n == 2 ? 'يومين' : '$t أيام');
  }

  InputDecoration _field() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.line),
    ),
  );
}
