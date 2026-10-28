import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/ksafish.dart';
import '../l10n.dart';
import '../theme.dart';

/// بطاقة النوع: لوحة النوع والأسماء والعائلة والمعلومات المنشورة في KSAFish ورابط صفحته.
/// اللوحة تُحمَّل من موقع KSAFish وقت العرض، وإذا ما فيه إنترنت تختفي بهدوء.
class SpeciesCard extends StatelessWidget {
  const SpeciesCard({super.key, required this.species, required this.facts, this.confidence, this.reason});

  final Species species;
  final List<Fact> facts;
  final int? confidence;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = species;
    final rows = <(String, String, bool)>[
      if (s.redSea.isNotEmpty) (tr('أسماء محلية: البحر الأحمر', 'Local names: Red Sea'), s.redSea.join('، '), false),
      if (s.gulf.isNotEmpty) (tr('أسماء محلية: الخليج العربي', 'Local names: Arabian Gulf'), s.gulf.join('، '), false),
      if (s.english.isNotEmpty && !L10n.en) ('الاسم الإنجليزي', s.english, true),
      if (s.familyAr.isNotEmpty || s.family.isNotEmpty)
        (
          tr('العائلة', 'Family'),
          (L10n.en ? [s.family, s.familyAr] : [s.familyAr, s.family]).where((x) => x.isNotEmpty).join(' · '),
          false,
        ),
      (tr('معرّف حوات', 'HUWAT ID'), s.id, true),
      if (s.code.isNotEmpty) (tr('الرمز الوطني', 'National code'), s.code, true),
      // المعلومات المكتوبة بالعربي ما لها ترجمة، فبالإنجليزي نعرض الأرقام والصيغ اللي نعرف عنوانها بس.
      for (final f in facts)
        if (!L10n.en || (_enLabels.containsKey(f.label) && !_arabic.hasMatch(f.value)))
          (_label(f), f.unit.isEmpty ? f.value : '${f.value} ${f.unit}', RegExp(r'^[\d.\s,]+$').hasMatch(f.value)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.plateUrl != null) _Plate(s.plateUrl!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          s.sci,
                          style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.muted, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                if (confidence != null) _Confidence(confidence!),
              ],
            ),
            if (reason != null && reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(reason!, style: const TextStyle(height: 1.6, color: AppColors.ink)),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppColors.line, height: 1),
            for (final (label, value, ltr) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      textDirection: ltr ? TextDirection.ltr : null,
                      style: const TextStyle(fontWeight: FontWeight.w500, height: 1.5, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            if (s.url.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: Text(tr('صفحة النوع في KSAFish', 'Species page on KSAFish')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final _arabic = RegExp('[\u0600-\u06FF]');

const _enLabels = {
  'الطول الكلي للعينة': 'Specimen total length',
  'الصيغة الزعنفية': 'Fin formula',
  'وزن الجسم': 'Body weight',
  'طول الدرقة (المدى المرصود)': 'Carapace length (observed range)',
  'عدد الأنواع كما يذكره المصدر': 'Number of species (per source)',
};

const _enScopes = {
  'المياه الإقليمية السعودية — البحر الأحمر': 'Saudi Red Sea waters',
  'المياه الإقليمية السعودية — الخليج العربي': 'Saudi Arabian Gulf waters',
  'عالمي': 'worldwide',
  'المملكة العربية السعودية': 'Saudi Arabia',
  'البحر الأحمر': 'Red Sea',
  'الخليج العربي': 'Arabian Gulf',
  'البحر الأحمر والخليج العربي': 'Red Sea and Arabian Gulf',
};

String _label(Fact f) {
  final label = L10n.en ? _enLabels[f.label] ?? f.label : f.label;
  final scope = L10n.en ? _enScopes[f.scope] ?? f.scope : f.scope;
  return scope.isEmpty ? label : '$label ($scope)';
}

class _Plate extends StatelessWidget {
  const _Plate(this.url);
  final String url;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.contain,
    // اللوحات رسومات على خلفية بيضاء، فنعرضها كاملة بإطار خفيف ومصدرها تحتها.
    frameBuilder: (context, child, frame, _) => frame == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: child,
                ),
                const SizedBox(height: 4),
                Text(
                  tr('المصدر: موسوعة KSAFish', 'Source: KSAFish encyclopedia'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

class _Confidence extends StatelessWidget {
  const _Confidence(this.value);
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12)),
    child: Column(
      children: [
        Text(
          '$value%',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AppColors.gold,
          ),
        ),
        Text(tr('الثقة', 'Confidence'), style: const TextStyle(color: AppColors.onNavyMuted, fontSize: 14)),
      ],
    ),
  );
}
