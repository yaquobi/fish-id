import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/box.dart';
import '../data/fish_id_api.dart';
import '../data/reports.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/ai_consent.dart';

/// صورة الصندوق للدلّال: يصوّر صندوق أو حمولة وصلت الحراج، ويطلع له الأنواع بأسمائها المحلية
/// وعدد تقريبي لكل نوع والطزاجة، ويقدر يعدّل العدد ويطلع «كشف حراج» PDF يرسله أو يطبعه.
class BoxScreen extends StatefulWidget {
  const BoxScreen({super.key});

  @override
  State<BoxScreen> createState() => _BoxScreenState();
}

class _BoxScreenState extends State<BoxScreen> {
  final _picker = ImagePicker();
  final _seller = TextEditingController();
  final _market = TextEditingController();
  final _photos = <Uint8List>[];
  BoxResult? _result;
  List<BoxItem> _items = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) _market.text = p.getString('box_market') ?? '';
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _seller.dispose();
    _market.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource source) async {
    if (!await AiConsent.ensure(context) || !mounted) return;
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      if (f == null) return;
      final b = await f.readAsBytes();
      if (mounted) {
        setState(() {
          _photos.add(b);
          _result = null;
        });
      }
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
    }
  }

  Future<void> _run() async {
    if (_photos.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await FishIdApi.box(List.of(_photos));
      setState(() {
        _result = r;
        _items = List.of(r.items);
      });
    } on FishIdException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString('box_market', _market.text.trim());
    } on Object {
      // حفظ اسم السوق للمرة الجاية مو ضروري.
    }
    final sheet = BoxResult(
      isFish: r.isFish,
      items: _items,
      overallFreshness: r.overallFreshness,
      summary: r.summary,
      photoTip: r.photoTip,
    );
    final pdf = await Reports.haraj(
      sheet,
      seller: _seller.text.trim(),
      market: _market.text.trim(),
      photo: _photos.first,
    );
    final stamp = Reports.when(DateTime.now()).replaceAll(RegExp(r'[^0-9]'), '');
    await Printing.sharePdf(bytes: pdf, filename: 'haraj-$stamp.pdf');
  }

  Future<void> _edit(int i) async {
    final c = TextEditingController(text: '${_items[i].count}');
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(_items[i].name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('العدد', 'Count'),
            helperText: '${tr('تقدير التطبيق', 'App estimate')}: ${_items[i].rangeLabel}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(int.tryParse(c.text.trim())),
            child: Text(tr('حفظ', 'Save')),
          ),
        ],
      ),
    );
    c.dispose();
    if (n != null && n >= 0 && mounted) setState(() => _items[i] = _items[i].copyWith(count: n));
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final total = _items.fold(0, (t, i) => t + i.count);
    return Scaffold(
      appBar: AppBar(title: Text(tr('صورة الصندوق', 'Box photo'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(
              'للدلّالين: صوّر الصندوق أو الحمولة من فوق، ونطلع لك الأنواع وعدد تقريبي لكل نوع والطزاجة، وكشف حراج ترسله.',
              'For auctioneers: photograph the box or load from above, and get the species, an approximate count for each and freshness, plus an auction sheet to send.',
            ),
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, p) in _photos.indexed)
                Stack(
                  children: [
                    Image.memory(p, width: 100, height: 100, fit: BoxFit.cover),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: InkWell(
                        onTap: () => setState(() {
                          _photos.removeAt(i);
                          _result = null;
                        }),
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_photos.isNotEmpty) const SizedBox(height: 12),
          if (_photos.length < 3) ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _add(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                _photos.isEmpty
                    ? tr('صوّر الصندوق', 'Photograph the box')
                    : tr('صورة ثانية لنفس الصندوق', 'Another photo of the same box'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr('اختر من الصور', 'Choose from photos')),
            ),
          ],
          if (_photos.isNotEmpty && r == null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.navy),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.inventory_2_outlined),
              label: Text(
                _busy
                    ? tr('جاري العدّ… (قد يأخذ دقيقة)', 'Counting… (may take a minute)')
                    : tr('وش في الصندوق؟', "What's in the box?"),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.bad)),
            ),
          if (r != null) ...[
            const SizedBox(height: 16),
            if (!r.isFish || _items.isEmpty)
              Text(
                r.photoTip.isNotEmpty
                    ? r.photoTip
                    : tr(
                        'ما لقينا أسماك في الصورة. صوّر الصندوق من فوق بإضاءة واضحة.',
                        'No fish found. Photograph the box from above in good light.',
                      ),
              )
            else
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('الأنواع', 'Species'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          Text(
                            '${tr('المجموع', 'Total')} ≈ $total',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    for (final (i, it) in _items.indexed)
                      ListTile(
                        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            it.sizeLabel,
                            if (it.freshness >= 0) '${tr('الطزاجة', 'Freshness')} ${it.freshness}/100',
                            if (it.note.isNotEmpty) it.note,
                          ].join(' · '),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${it.count}',
                              style: const TextStyle(
                                fontFamily: 'ChakraPetch',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              it.rangeLabel,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                        onTap: () => _edit(i),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        tr(
                          'اضغط على أي نوع تعدّل عدده. الأعداد تقديرية من الصورة.',
                          'Tap a species to correct its count. Counts are estimates from the photo.',
                        ),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (r.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(r.summary)),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _seller,
                decoration: InputDecoration(
                  labelText: tr('البائع أو القارب (اختياري)', 'Seller or boat (optional)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _market,
                decoration: InputDecoration(
                  labelText: tr('السوق (اختياري)', 'Market (optional)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(tr('كشف حراج PDF', 'Auction sheet PDF')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _photos.clear();
                  _result = null;
                  _items = [];
                  _seller.clear();
                }),
                icon: const Icon(Icons.add),
                label: Text(tr('صندوق جديد', 'New box')),
              ),
            ],
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ],
      ),
    );
  }
}
