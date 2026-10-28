import 'package:flutter/material.dart';

import '../data/result.dart';
import '../theme.dart';

/// تقدير الطزاجة: مؤشر من 0 إلى 100 وملاحظات العين والخياشيم والجلد.
class FreshnessCard extends StatelessWidget {
  const FreshnessCard({super.key, required this.freshness});
  final Freshness freshness;

  @override
  Widget build(BuildContext context) {
    final f = freshness;
    final color = f.score >= 75 ? AppColors.good : (f.score >= 50 ? AppColors.warn : AppColors.bad);
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
