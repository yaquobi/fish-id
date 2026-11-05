import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/ksafish.dart';
import '../data/upload_queue.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/contribute_card.dart';

/// «ساهم بصور سمك»: للصيادين في البحر بدون إنترنت. يصوّر السمكة (جنب، عين، خياشيم)،
/// ويختار النوع من الموسوعة المحفوظة في الجوال، ويحفظ. الصور تنتظر في الجوال وتنرسل لحالها أول ما يرجع النت.
/// ما تحتاج فحص ولا تنحسب من الفحوصات.
class ContributeScreen extends StatefulWidget {
  const ContributeScreen({super.key});

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _picker = ImagePicker();
  final _db = Ksafish.load();
  final _shots = <Uint8List?>[null, null, null];
  Species? _species;
  bool _sure = false;
  int _days = 0;
  String _storage = 'ice';
  bool _consent = false;
  bool _saving = false;
  int _formKey = 0;

  static List<(IconData, String)> get _slots => [
    (Icons.straighten, tr('السمكة كاملة من الجنب', 'Whole fish, side view')),
    (Icons.visibility_outlined, tr('العين قريب', 'Eye, close up')),
    (Icons.air, tr('الخياشيم مفتوحة', 'Gills, opened')),
  ];

  Future<void> _shoot(int i) async {
    try {
      final f = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (f == null) return;
      final b = await f.readAsBytes();
      if (mounted) setState(() => _shots[i] = b);
    } on Exception {
      _snack(tr('ما قدرنا نفتح الكاميرا. تأكد من الصلاحيات.', 'Could not open the camera. Check the permissions.'));
    }
  }

  Future<void> _fromGallery() async {
    try {
      final files = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: 3);
      final bytes = [for (final f in files.take(3)) await f.readAsBytes()];
      if (!mounted || bytes.isEmpty) return;
      setState(() {
        for (var i = 0; i < 3; i++) {
          _shots[i] = i < bytes.length ? bytes[i] : null;
        }
      });
    } on Exception {
      _snack(tr('ما قدرنا نفتح الصور. تأكد من الصلاحيات.', 'Could not open your photos. Check the permissions.'));
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final species = _species?.id.split('-').last ?? '';
    await UploadQueue.add(
      [for (final s in _shots) ?s],
      {
        'species': species,
        'speciesConfirmed': species.isNotEmpty && _sure,
        'days': _days,
        'storage': _storage,
        'predicted': const <String>[],
        'score': -1,
      },
    );
    final sent = await UploadQueue.flush();
    if (!mounted) return;
    setState(() {
      _saving = false;
      for (var i = 0; i < 3; i++) {
        _shots[i] = null;
      }
      _species = null;
      _sure = false;
      _formKey++;
    });
    _snack(
      sent > 0 && UploadQueue.pending.value == 0
          ? tr('وصلت! شكرًا لك. صوّر السمكة اللي بعدها.', 'Sent! Thank you. Now the next fish.')
          : tr(
              'انحفظت في الجوال ✓ بتنرسل لحالها أول ما يرجع النت. صوّر السمكة اللي بعدها.',
              'Saved on the phone ✓ It will be sent when you are back online. Now the next fish.',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _shots.whereType<Uint8List>().length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ساهم بصور سمك', 'Share fish photos'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _PendingBanner(),
          Text(
            tr(
              'يشتغل حتى بدون إنترنت، في البحر أو المينا. صوّر وحفظ، والصور تنرسل لحالها أول ما يشبك الجوال على النت.',
              'Works without internet, at sea or in port. Take the photos and save; they are sent automatically when the phone is back online.',
            ),
            style: const TextStyle(color: AppColors.muted, height: 1.6),
          ),
          const SizedBox(height: 16),
          _Title(tr('1. الصور', '1. Photos')),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, (icon, label)) in _slots.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _Shot(icon: icon, label: label, image: _shots[i], onTap: () => _shoot(i)),
                ),
              ],
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _fromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr('أو اختر من الاستوديو', 'Or choose from your photos')),
            ),
          ),
          const SizedBox(height: 8),
          _Title(tr('2. وش نوعها؟', '2. Which species?')),
          const SizedBox(height: 8),
          FutureBuilder(
            future: _db,
            builder: (context, snap) {
              final db = snap.data;
              if (db == null) return const LinearProgressIndicator(color: AppColors.navy);
              return Autocomplete<Species>(
                key: ValueKey(_formKey),
                displayStringForOption: (s) => s.name,
                optionsBuilder: (v) => v.text.trim().isEmpty ? const <Species>[] : db.search(v.text).take(20),
                onSelected: (s) => setState(() => _species = s),
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  onChanged: (_) {
                    if (_species != null) setState(() => _species = null);
                  },
                  decoration: _field(tr('اكتب الاسم: هامور، بياض، شعري…', 'Type the name: grouper, emperor…'))
                      .copyWith(prefixIcon: const Icon(Icons.search)),
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260, maxWidth: 520),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final s in options)
                            ListTile(
                              dense: true,
                              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(s.sci, style: const TextStyle(fontStyle: FontStyle.italic)),
                              onTap: () => onSelected(s),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _species == null
                  ? tr(
                      'اختياري. لو ما تعرفه خلّه فاضي، وفريقنا يحدده.',
                      "Optional. Leave it empty if you don't know; our team will name it.",
                    )
                  : tr('✓ من الموسوعة: ${_species!.sci}', '✓ From the encyclopedia: ${_species!.sci}'),
              style: TextStyle(color: _species == null ? AppColors.muted : AppColors.good, fontSize: 13),
            ),
          ),
          if (_species != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _sure,
              onChanged: (v) => setState(() => _sure = v ?? false),
              title: Text(tr('متأكد من النوع', "I'm sure of the species")),
            ),
          const SizedBox(height: 12),
          _Title(tr('3. طزاجتها', '3. Freshness')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _days,
                  isExpanded: true,
                  decoration: _field(tr('كم يوم من الصيد؟', 'Days since catch?')),
                  items: [
                    for (final d in ContributeCard.dayOptions)
                      DropdownMenuItem(value: d, child: Text(ContributeCard.dayLabel(d))),
                  ],
                  onChanged: (v) => setState(() => _days = v ?? -1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _storage,
                  isExpanded: true,
                  decoration: _field(tr('وين محفوظة؟', 'How is it kept?')),
                  items: [
                    for (final MapEntry(:key, :value) in ContributeCard.storageOptions.entries)
                      DropdownMenuItem(value: key, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => _storage = v ?? 'unknown'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _consent && count > 0 && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_alt),
            label: Text(tr('احفظ وأرسل', 'Save and send')),
          ),
          if (count == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('صوّر صورة وحدة على الأقل، والأفضل الثلاث.', 'Take at least one photo, ideally all three.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.line),
    ),
  );
}

/// كم سمكة تنتظر النت، مع زر «أرسل الحين».
class _PendingBanner extends StatelessWidget {
  const _PendingBanner();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: UploadQueue.pending,
    builder: (context, n, _) => n == 0
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: .18)),
            child: Row(
              children: [
                const Icon(Icons.cloud_upload_outlined, color: AppColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      switch (n) {
                        1 => 'سمكة وحدة تنتظر النت',
                        2 => 'سمكتين تنتظر النت',
                        < 11 => '$n سمكات تنتظر النت',
                        _ => '$n سمكة تنتظر النت',
                      },
                      n == 1 ? '1 fish waiting for internet' : '$n fish waiting for internet',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await UploadQueue.flush();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          UploadQueue.pending.value == 0
                              ? tr('انرسلت كلها ✓ شكرًا لك!', 'All sent ✓ Thank you!')
                              : tr('لسا ما فيه نت. بنحاول لحالنا.', 'Still no internet. We will keep trying.'),
                        ),
                      ),
                    );
                  },
                  child: Text(tr('أرسل الحين', 'Send now')),
                ),
              ],
            ),
          ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16));
}

class _Shot extends StatelessWidget {
  const _Shot({required this.icon, required this.label, required this.image, required this.onTap});
  final IconData icon;
  final String label;
  final Uint8List? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: AspectRatio(
      aspectRatio: .8,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: image == null ? AppColors.line : AppColors.good, width: image == null ? 1 : 2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null) Image.memory(image!, fit: BoxFit.cover),
            if (image == null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: AppColors.navy, size: 28),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 1.3)),
                    const SizedBox(height: 4),
                    const Icon(Icons.photo_camera_outlined, color: AppColors.muted, size: 18),
                  ],
                ),
              )
            else
              const PositionedDirectional(top: 4, end: 4, child: Icon(Icons.check_circle, color: AppColors.good)),
          ],
        ),
      ),
    ),
  );
}
