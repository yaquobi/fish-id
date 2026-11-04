import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../data/fish_id_api.dart';
import '../data/ksafish.dart';
import '../data/reports.dart';
import '../data/result.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/ai_consent.dart';

/// زيارة تفتيشية واحدة: صورة السمكة وصورة لوحة المحل، والمكتوب عليها، والفحص، ثم قرار المفتش وحفظ الزيارة وتقريرها.
class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key, required this.market, this.city = ''});
  final String market;
  final String city;

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final _picker = ImagePicker();
  final _shop = TextEditingController();
  final _label = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  final _fish = <Uint8List>[];
  Uint8List? _labelPhoto;
  FishResult? _result;
  Species? _species;
  Ksafish? _db;
  String? _error;
  bool _checking = false;
  bool _saving = false;
  String _decision = '';
  final _violations = <String>{};

  @override
  void dispose() {
    _shop.dispose();
    _label.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<Uint8List?> _take(ImageSource source) async {
    if (!await AiConsent.ensure(context)) return null;
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      return f == null ? null : await f.readAsBytes();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('ما قدرنا نفتح الكاميرا. تأكد من الصلاحيات.', 'Could not open the camera. Check permissions.'),
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<ImageSource?> _source() => showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('الكاميرا', 'Camera')),
            onTap: () => Navigator.of(c).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('من الصور', 'From photos')),
            onTap: () => Navigator.of(c).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );

  Future<void> _addFish() async {
    final s = await _source();
    if (s == null || !mounted) return;
    final b = await _take(s);
    if (b != null && mounted) {
      setState(() {
        _fish.add(b);
        _result = null;
      });
    }
  }

  Future<void> _addLabel() async {
    final s = await _source();
    if (s == null || !mounted) return;
    final b = await _take(s);
    if (b != null && mounted) setState(() => _labelPhoto = b);
  }

  Future<void> _check() async {
    if (_fish.isEmpty) {
      setState(() => _error = tr('صوّر السمكة أول', 'Take a photo of the fish first'));
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final out = await Future.wait([FishIdApi.identify(List.of(_fish)), Ksafish.load()]);
      final r = out[0] as FishResult, db = out[1] as Ksafish;
      final top = r.candidates.isEmpty ? null : db.byId(r.candidates.first.id);
      setState(() {
        _result = r;
        _db = db;
        _species = top;
        final match = _match;
        // اقتراح أولي للقرار، والمفتش يغيّره.
        if (_decision.isEmpty && match == false) {
          _decision = 'violation';
          _violations.add('name');
        }
        if ((r.freshness?.assessable ?? false) && (r.freshness?.score ?? 100) < 40) _violations.add('fresh');
      });
    } on FishIdException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  bool? get _match {
    final s = _species;
    if (s == null || _label.text.trim().isEmpty) return null;
    return Ksafish.labelMatches(_label.text, s);
  }

  Future<Position?> _where() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _save() async {
    if (_shop.text.trim().isEmpty) {
      setState(() => _error = tr('اكتب اسم المحل', 'Enter the shop name'));
      return;
    }
    if (_decision.isEmpty) {
      setState(() => _error = tr('اختر نتيجة الزيارة', 'Choose the visit result'));
      return;
    }
    if (_decision == 'violation' && _violations.isEmpty) {
      setState(() => _error = tr('اختر نوع المخالفة', 'Choose the violation type'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pos = await _where();
      final r = _result, s = _species, f = r?.freshness;
      final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
      final visit = <String, dynamic>{
        'market': widget.market,
        'city': widget.city,
        'shop': _shop.text.trim(),
        'labelName': _label.text.trim(),
        'labelPrice': ?price,
        if (s != null)
          'result': {
            'species': s.id.split('-').last,
            'name': s.name,
            'sci': s.sci,
            'confidence': r!.candidates.first.confidence,
            if (f != null && f.assessable) 'freshness': f.score,
            if (f != null && f.assessable) 'grade': f.grade,
          },
        'match': ?_match,
        'decision': _decision,
        'violations': _decision == 'ok' ? <String>[] : _violations.toList(),
        'note': _note.text.trim(),
        'lat': ?pos?.latitude,
        'lng': ?pos?.longitude,
      };
      final photos = [..._fish.take(2), ?_labelPhoto];
      final saved = await FishIdApi.govVisit(visit, photos);
      final full = {...visit, ...saved, 'agency': FishIdApi.gov.value?['agency'] ?? ''};
      final pdf = await Reports.inspection(full, photos: photos);
      if (!mounted) return;
      await Printing.sharePdf(bytes: pdf, filename: '${saved['ref']}.pdf');
      if (mounted) Navigator.of(context).pop(true);
    } on FishIdException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(tr('زيارة تفتيشية', 'Inspection visit'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.market}${widget.city.isEmpty ? '' : ' · ${widget.city}'}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          _Section(
            title: tr('1. المحل وما هو مكتوب على اللوحة', '1. Shop and its label'),
            children: [
              TextField(
                controller: _shop,
                decoration: InputDecoration(
                  labelText: tr('اسم المحل أو رقمه', 'Shop name or number'),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _label,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: tr('الاسم المكتوب', 'Name on label'),
                        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('السعر / كجم', 'Price / kg'),
                        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Photos(
                label: tr('صورة اللوحة (اختياري)', 'Label photo (optional)'),
                photos: [?_labelPhoto],
                onAdd: _labelPhoto == null ? _addLabel : null,
                onRemove: (_) => setState(() => _labelPhoto = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: tr('2. صورة السمكة', '2. Fish photo'),
            children: [
              _Photos(
                label: tr(
                  'السمكة كاملة من الجنب، وإذا تقدر العين والخياشيم',
                  'Whole fish from the side, plus eye and gills if you can',
                ),
                photos: _fish,
                onAdd: _fish.length < 3 ? _addFish : null,
                onRemove: (i) => setState(() {
                  _fish.removeAt(i);
                  _result = null;
                }),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
                label: Text(_checking ? tr('جاري الفحص…', 'Checking…') : tr('افحص السمكة', 'Check the fish')),
              ),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 12),
            _Section(
              title: tr('3. النتيجة (استرشادية)', '3. Result (advisory)'),
              children: [_ResultBox(result: r, species: _species, db: _db, label: _label.text.trim(), match: _match)],
            ),
          ],
          const SizedBox(height: 12),
          _Section(
            title: tr('4. قرار المفتش', '4. Inspector decision'),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in const ['ok', 'violation', 'followup'])
                    ChoiceChip(
                      label: Text(Reports.decisionName(d)),
                      selected: _decision == d,
                      onSelected: (_) => setState(() => _decision = d),
                    ),
                ],
              ),
              if (_decision == 'violation' || _decision == 'followup') ...[
                const SizedBox(height: 8),
                for (final k in Reports.violationNames.keys)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(Reports.violationName(k)),
                    value: _violations.contains(k),
                    onChanged: (v) => setState(() => v == true ? _violations.add(k) : _violations.remove(k)),
                  ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: tr('ملاحظة المفتش', 'Inspector note'),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.bad)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_saving ? tr('جاري الحفظ…', 'Saving…') : tr('حفظ وإصدار التقرير', 'Save and issue report')),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'الموقع ينحفظ مع الزيارة إذا سمحت للتطبيق. نتيجة الذكاء الاصطناعي استرشادية، والقرار لك.',
              'The location is saved with the visit if you allow it. The AI result is advisory; the decision is yours.',
            ),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _Photos extends StatelessWidget {
  const _Photos({required this.label, required this.photos, required this.onAdd, required this.onRemove});
  final String label;
  final List<Uint8List> photos;
  final VoidCallback? onAdd;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, p) in photos.indexed)
            Stack(
              children: [
                Image.memory(p, width: 84, height: 84, fit: BoxFit.cover),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: InkWell(
                    onTap: () => onRemove(i),
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          if (onAdd != null)
            Semantics(
              button: true,
              label: tr('أضف صورة', 'Add photo'),
              excludeSemantics: true,
              child: InkWell(
                onTap: onAdd,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.navy),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({
    required this.result,
    required this.species,
    required this.db,
    required this.label,
    required this.match,
  });
  final FishResult result;
  final Species? species;
  final Ksafish? db;
  final String label;
  final bool? match;

  @override
  Widget build(BuildContext context) {
    final s = species, f = result.freshness;
    if (!result.isFish || s == null) {
      return Text(
        result.outsideListGuess.isNotEmpty
            ? tr(
                'ما قدرنا نحدد صنف من الموسوعة. أقرب تخمين: ${result.outsideListGuess}',
                'No species from the list. Best guess: ${result.outsideListGuess}',
              )
            : tr(
                'ما قدرنا نحدد الصنف، جرّب صورة أوضح للسمكة كاملة.',
                'Could not identify the species. Try a clearer photo of the whole fish.',
              ),
      );
    }
    final others = [
      for (final c in result.candidates.skip(1))
        if (db?.byId(c.id) case final o?) '${o.name} ${c.confidence}%',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('المكتوب', 'Label'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text(
                      label.isEmpty ? '—' : label,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('التطبيق يقول', 'App says'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text(
                      '${s.name} ${result.candidates.first.confidence}%',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (match != null)
          Container(
            padding: const EdgeInsets.all(10),
            color: (match! ? AppColors.good : AppColors.bad).withValues(alpha: .1),
            child: Text(
              match!
                  ? tr('الاسم يطابق الصنف المرجّح', 'The label matches the likely species')
                  : tr('الاسم ما يطابق الصنف المرجّح', 'The label does not match the likely species'),
              style: TextStyle(color: match! ? AppColors.good : AppColors.bad, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          s.sci,
          style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.muted),
          textDirection: TextDirection.ltr,
        ),
        if (others.isNotEmpty)
          Text(
            '${tr('احتمالات ثانية', 'Other options')}: ${others.join('، ')}',
            style: const TextStyle(color: AppColors.muted),
          ),
        if (f != null && f.assessable) Text('${tr('الطزاجة', 'Freshness')}: ${f.score}/100 · ${f.levelLabel}'),
        if (f != null && f.assessable && f.summary.isNotEmpty)
          Text(f.summary, style: const TextStyle(color: AppColors.muted)),
      ],
    );
  }
}
