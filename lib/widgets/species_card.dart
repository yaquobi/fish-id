import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/ksafish.dart';
import '../theme.dart';

/// بطاقة النوع: الأسماء والعائلة والمعلومات المنشورة في KSAFish ورابط صفحته.
/// صور الموسوعة لا تُضمَّن في التطبيق، والرابط يفتحها في الموقع.
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
      if (s.redSea.isNotEmpty) ('أسماء محلية: البحر الأحمر', s.redSea.join('، '), false),
      if (s.gulf.isNotEmpty) ('أسماء محلية: الخليج العربي', s.gulf.join('، '), false),
      if (s.english.isNotEmpty) ('الاسم الإنجليزي', s.english, true),
      if (s.familyAr.isNotEmpty || s.family.isNotEmpty) ('العائلة', [s.familyAr, s.family].where((x) => x.isNotEmpty).join(' · '), false),
      ('معرّف حوات', s.id, true),
      if (s.code.isNotEmpty) ('الرمز الوطني', s.code, true),
      for (final f in facts)
        (
          f.scope.isEmpty ? f.label : '${f.label} (${f.scope})',
          f.unit.isEmpty ? f.value : '${f.value} ${f.unit}',
          RegExp(r'^[\d.\s,]+$').hasMatch(f.value),
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3, color: AppColors.ink),
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
                    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
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
                label: const Text('صفحة النوع وصوره في KSAFish'),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
          style: const TextStyle(fontFamily: 'ChakraPetch', fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.gold),
        ),
        const Text('الثقة', style: TextStyle(color: AppColors.onNavyMuted, fontSize: 12)),
      ],
    ),
  );
}
