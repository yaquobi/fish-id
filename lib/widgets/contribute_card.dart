import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/fish_id_api.dart';
import '../l10n.dart';
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
  static Map<String, String> get _storageOptions => {
    'unknown': tr('ما أعرف', "I don't know"),
    'ice': tr('على الثلج', 'On ice'),
    'fridge': tr('في الثلاجة', 'In the fridge'),
    'room': tr('في غرفة مكيّفة', 'In an air-conditioned room'),
    'hot': tr('برّا أو في السيارة', 'Outside or in the car'),
    'frozen': tr('مجمّدة', 'Frozen'),
  };

  static String _dayLabel(int d) => switch (d) {
    -1 => tr('ما أعرف', "I don't know"),
    0 => tr('نفس اليوم', 'Same day'),
    1 => tr('يوم', '1 day'),
    2 => tr('يومين', '2 days'),
    10 => tr('أكثر من أسبوع', 'More than a week'),
    _ => tr('$d أيام', '$d days'),
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.volunteer_activism, color: AppColors.good),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(
                    'شكرًا لك! وصلت صورك، وبتساعدنا نخلي FISH ID أدق لأسماكنا.',
                    'Thank you! Your photos arrived and will help make FISH ID more accurate for our fish.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
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
            Row(
              children: [
                const Icon(Icons.volunteer_activism_outlined, color: AppColors.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('ساهم بصورتك', 'Share your photo'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                'ساعدنا نبني أول قاعدة بيانات لأسماك الخليج والبحر الأحمر وطزاجتها. كل صورة تخلي التطبيق أدق.',
                'Help us build the first dataset of Gulf and Red Sea fish and their freshness. Every photo makes the app more accurate.',
              ),
              style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 14),
            ),
            if (!_open) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _open = true),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(tr('أبي أساهم', 'I want to help')),
              ),
            ] else ...[
              const SizedBox(height: 14),
              Text(tr('وش نوعها؟', 'Which species is it?'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    label: Text(tr('نوع ثاني أو ما أعرف', "Another species or I don't know")),
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
                  title: Text(
                    tr(
                      'متأكد من النوع (أعرفه أو قاله البائع)',
                      "I'm sure of the species (I know it or the seller said so)",
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _days,
                      isExpanded: true,
                      decoration: _field(tr('كم يوم من الصيد؟', 'Days since catch?')),
                      items: [for (final d in _dayOptions) DropdownMenuItem(value: d, child: Text(_dayLabel(d)))],
                      onChanged: (v) => setState(() => _days = v ?? -1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _storage,
                      isExpanded: true,
                      decoration: _field(tr('وين كانت محفوظة؟', 'How was it kept?')),
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
                title: Text(
                  tr(
                    'أوافق على حفظ صوري واستخدامها لتطوير FISH ID والبحث العلمي. ما نحفظ اسمي ولا موقعي، ونحذف بيانات الموقع من الصور.',
                    'I agree that my photos are saved and used to improve FISH ID and for scientific research. My name and location are not kept, and location data is removed from the photos.',
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5),
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
                label: Text(tr('أرسل المساهمة', 'Send')),
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
