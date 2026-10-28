import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/fish_id_api.dart';
import '../theme.dart';

/// «ساهم بالصورة»: المستخدم يؤكد النوع ويقول كم يوم صار لها وكيف انحفظت، ويرسل الصور بموافقته.
/// كل مساهمة تبني أول مجموعة بيانات لأسماك الخليج والبحر الأحمر وطزاجتها.
class ContributeCard extends StatefulWidget {
  const ContributeCard({super.key, required this.images, required this.candidates, required this.score});

  final List<Uint8List> images;

  /// (رقم حوات القصير، الاسم) للأنواع المرشحة، الأفضل أولًا.
  final List<(String, String)> candidates;
  final int score;

  @override
  State<ContributeCard> createState() => _ContributeCardState();
}

enum _Status { idle, sending, done }

class _ContributeCardState extends State<ContributeCard> {
  bool _open = false;
  late String _species = widget.candidates.firstOrNull?.$1 ?? '';
  bool _sure = false;
  int _days = -1;
  String _storage = 'unknown';
  bool _consent = false;
  _Status _status = _Status.idle;
  String? _error;

  static const _dayOptions = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 10];
  static const _storageOptions = {
    'unknown': 'ما أعرف',
    'ice': 'على الثلج',
    'fridge': 'في الثلاجة',
    'room': 'في غرفة مكيّفة',
    'hot': 'برّا أو في السيارة',
    'frozen': 'مجمّدة',
  };

  static String _dayLabel(int d) => switch (d) {
    -1 => 'ما أعرف',
    0 => 'نفس اليوم',
    1 => 'يوم',
    2 => 'يومين',
    10 => 'أكثر من أسبوع',
    _ => '$d أيام',
  };

  Future<void> _send() async {
    setState(() {
      _status = _Status.sending;
      _error = null;
    });
    try {
      await FishIdApi.contribute(
        widget.images,
        species: _species,
        speciesConfirmed: _sure,
        days: _days,
        storage: _storage,
        predicted: [for (final c in widget.candidates) c.$1],
        score: widget.score,
      );
      if (mounted) setState(() => _status = _Status.done);
    } on FishIdException catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.idle;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _Status.done) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.volunteer_activism, color: AppColors.good),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'شكرًا لك! وصلت صورك، وبتساعدنا نخلي FISH ID أدق لأسماكنا.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.volunteer_activism_outlined, color: AppColors.navy),
                SizedBox(width: 8),
                Expanded(
                  child: Text('ساهم بصورتك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'ساعدنا نبني أول قاعدة بيانات لأسماك الخليج والبحر الأحمر وطزاجتها. كل صورة تخلي التطبيق أدق.',
              style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 14),
            ),
            if (!_open) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _open = true),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('أبي أساهم'),
              ),
            ] else ...[
              const SizedBox(height: 14),
              const Text('وش نوعها؟', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, name) in widget.candidates)
                    ChoiceChip(
                      label: Text(name),
                      selected: _species == id,
                      selectedColor: AppColors.gold,
                      onSelected: (_) => setState(() => _species = id),
                    ),
                  ChoiceChip(
                    label: const Text('نوع ثاني أو ما أعرف'),
                    selected: _species.isEmpty,
                    selectedColor: AppColors.gold,
                    onSelected: (_) => setState(() {
                      _species = '';
                      _sure = false;
                    }),
                  ),
                ],
              ),
              if (_species.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _sure,
                  onChanged: (v) => setState(() => _sure = v ?? false),
                  title: const Text('متأكد من النوع (أعرفه أو قاله البائع)'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _days,
                      isExpanded: true,
                      decoration: _field('كم يوم من الصيد؟'),
                      items: [for (final d in _dayOptions) DropdownMenuItem(value: d, child: Text(_dayLabel(d)))],
                      onChanged: (v) => setState(() => _days = v ?? -1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _storage,
                      isExpanded: true,
                      decoration: _field('وين كانت محفوظة؟'),
                      items: [
                        for (final MapEntry(:key, :value) in _storageOptions.entries)
                          DropdownMenuItem(value: key, child: Text(value)),
                      ],
                      onChanged: (v) => setState(() => _storage = v ?? 'unknown'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'أوافق على حفظ صوري واستخدامها لتطوير FISH ID والبحث العلمي. ما نحفظ اسمي ولا موقعي، ونحذف بيانات الموقع من الصور.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.bad)),
                ),
              FilledButton.icon(
                onPressed: _consent && _status == _Status.idle ? _send : null,
                icon: _status == _Status.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: const Text('أرسل المساهمة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.line),
    ),
  );
}
