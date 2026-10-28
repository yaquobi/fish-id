import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/fish_id_api.dart';
import '../data/ksafish.dart';
import '../data/result.dart';
import '../theme.dart';
import '../widgets/freshness_card.dart';
import '../widgets/species_card.dart';

/// يرسل الصورة للتحليل ويعرض النوع (حتى 3 احتمالات) وتقدير الطزاجة.
/// يقدر المستخدم يضيف صورتين قريبتين (العين والخياشيم) لنفس السمكة، ويتعاد التحليل بكل الصور.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.image});
  final Uint8List image;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const _maxPhotos = 3;
  late final List<Uint8List> _images = [widget.image];
  late Future<(FishResult, Ksafish)> _future = _run();
  int _selected = 0;

  Future<(FishResult, Ksafish)> _run() async {
    final results = await Future.wait([FishIdApi.identify(List.of(_images)), Ksafish.load()]);
    return (results[0] as FishResult, results[1] as Ksafish);
  }

  void _retry() => setState(() {
    _selected = 0;
    _future = _run();
  });

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('صوّر العين قريبة، أو الخياشيم وهي مفتوحة', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('الكاميرا'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('من الصور'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _images.add(bytes);
      _selected = 0;
      _future = _run();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نتيجة التحليل')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * .3).clamp(160, 300),
            child: Image.memory(widget.image, fit: BoxFit.cover),
          ),
        ),
        if (_images.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length - 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_images[i + 1], width: 64, height: 64, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FutureBuilder(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const _Loading();
            if (snap.hasError) return _Error(message: '${snap.error}', onRetry: _retry);
            final (result, db) = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _body(result, db),
                if (result.isFish && _images.length < _maxPhotos) ...[
                  OutlinedButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(_images.length == 1 ? 'أضف صورة للعين أو الخياشيم لتقييم أدق' : 'أضف صورة ثالثة'),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _body(FishResult r, Ksafish db) {
    if (!r.isFish) {
      return _Message(
        icon: Icons.search_off,
        text: 'ما ظهرت سمكة واضحة في الصورة.${r.subject.isEmpty ? '' : ' ${r.subject}'}',
        tip: r.photoTip,
      );
    }
    final cands = [
      for (final c in r.candidates)
        if (db.byId(c.id) case final s?) (c, s),
    ];
    final sel = _selected < cands.length ? _selected : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDemo)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('وضع التجربة: هذه نتيجة مثال.', style: TextStyle(color: AppColors.muted)),
          ),
        if (cands.length > 1) ...[
          const Text(
            'الاحتمالات',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, (c, s)) in cands.indexed)
                ChoiceChip(
                  label: Text('${s.name} · ${c.confidence}%'),
                  selected: i == sel,
                  onSelected: (_) => setState(() => _selected = i),
                  selectedColor: AppColors.gold,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (cands.isNotEmpty)
          SpeciesCard(
            species: cands[sel].$2,
            facts: db.factsFor(cands[sel].$2),
            confidence: cands[sel].$1.confidence,
            reason: cands[sel].$1.reason,
          )
        else
          _Message(
            icon: Icons.help_outline,
            text: r.outsideListGuess.isNotEmpty
                ? 'يبدو أنها ليست ضمن أنواع الموسوعة. أقرب تخمين: ${r.outsideListGuess}'
                : 'ما قدرنا نحدد النوع من أنواع الموسوعة.',
          ),
        if (r.freshness case final f?) ...[const SizedBox(height: 12), FreshnessCard(freshness: f)],
        if (r.photoTip.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline, color: AppColors.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('نصيحة: ${r.photoTip}', style: const TextStyle(height: 1.5))),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        CircularProgressIndicator(color: AppColors.navy),
        SizedBox(height: 16),
        Text('نحلل الصورة…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        SizedBox(height: 4),
        Text('نقارنها بـ 447 نوعًا ونفحص العين والخياشيم والجلد', style: TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Message(icon: Icons.error_outline, text: message),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('حاول مرة ثانية')),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.tip = ''});
  final IconData icon;
  final String text;
  final String tip;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(height: 1.6, fontSize: 15))),
            ],
          ),
          if (tip.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('نصيحة: $tip', style: const TextStyle(color: AppColors.muted)),
            ),
        ],
      ),
    ),
  );
}
