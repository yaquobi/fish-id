import 'package:flutter/material.dart';

import '../data/result.dart';
import '../theme.dart';

/// تقدير الطزاجة بطريقة مؤشر الجودة (QIM): الدرجة من 100، والتصنيف، والأيام التقريبية، ونقاط كل علامة.
class FreshnessCard extends StatelessWidget {
  const FreshnessCard({super.key, required this.freshness});
  final Freshness freshness;

  @override
  Widget build(BuildContext context) {
    final f = freshness;
    final color = f.score >= 65 ? AppColors.good : (f.score >= 40 ? AppColors.warn : AppColors.bad);
    final notes = [('العين', f.eyes), ('الخياشيم', f.gills), ('الجلد', f.skin), ('ملاحظات', f.other)].where((n) => n.$2.isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop_outlined, color: AppColors.navy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('تقدير الطزاجة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (f.assessable)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${f.level}  '),
                        TextSpan(
                          text: '${f.score}/100',
                          style: const TextStyle(fontFamily: 'ChakraPetch'),
                        ),
                      ],
                    ),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (!f.assessable)
              Text(f.summary.isNotEmpty ? f.summary : 'ما نقدر نقدّر الطزاجة من هذه الصورة.', style: const TextStyle(height: 1.6))
            else ...[
              Semantics(
                label: 'مؤشر الطزاجة ${f.score} من 100',
                child: _Meter(score: f.score),
              ),
              const SizedBox(height: 6),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('غير طازجة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Text('طازجة جدًا', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              if (f.gradeLabel.isNotEmpty || f.daysLabel.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (f.gradeLabel.isNotEmpty) _Badge(icon: Icons.verified_outlined, text: 'التصنيف: ${f.gradeLabel}', color: color),
                    if (f.daysLabel.isNotEmpty) _Badge(icon: Icons.schedule, text: f.daysLabel, color: AppColors.navy),
                  ],
                ),
              ],
              if (f.summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(f.summary, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6)),
              ],
              for (final (label, text) in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(label, style: const TextStyle(color: AppColors.muted)),
                      ),
                      Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
                    ],
                  ),
                ),
              if (f.rows.isNotEmpty) _QimDetails(rows: f.rows),
              if (f.manualChecks.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.back_hand_outlined, size: 18, color: AppColors.warn),
                    const SizedBox(width: 8),
                    Expanded(child: Text('افحص بيدك: ${f.manualChecks}', style: const TextStyle(height: 1.5))),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 14),
            const Text(
              'تقدير بصري بالذكاء الاصطناعي، وليس بديلًا عن الفحص بالشم واللمس.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط متدرج من الأحمر (يمين في العربي = غير طازجة) إلى الأخضر، مع مؤشر عند الدرجة.
class _Meter extends StatelessWidget {
  const _Meter({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final pos = c.maxWidth * score / 100;
      return SizedBox(
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: const [AppColors.bad, AppColors.warn, AppColors.good],
                ),
              ),
            ),
            Positioned(
              left: (rtl ? c.maxWidth - pos : pos) - 11,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navy, width: 4),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// نقاط كل علامة من علامات QIM. كل نقطة عيب تنرسم دائرة ممتلئة، والعلامة اللي ما بانت تنكتب «ما بانت».
class _QimDetails extends StatelessWidget {
  const _QimDetails({required this.rows});
  final List<QimRow> rows;

  @override
  Widget build(BuildContext context) {
    final seen = rows.where((r) => r.seen).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text('تفاصيل التقييم (QIM)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          'انفحصت $seen علامات من ${rows.length}. كل نقطة تعني عيبًا، والصفر أفضل.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.label, style: TextStyle(color: r.seen ? AppColors.ink : AppColors.muted)),
                  ),
                  if (!r.seen)
                    const Text('ما بانت', style: TextStyle(color: AppColors.muted, fontSize: 13))
                  else
                    Semantics(
                      label: '${r.points} من ${r.max}',
                      child: Row(
                        children: [
                          for (var i = 0; i < r.max; i++)
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsetsDirectional.only(start: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < r.points ? (r.points * 2 > r.max ? AppColors.bad : AppColors.warn) : AppColors.line,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
