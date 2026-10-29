import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/fish_id_api.dart';
import '../data/ksafish.dart';
import '../data/result.dart';
import '../data/billing.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/contribute_card.dart';
import '../widgets/freshness_card.dart';
import '../widgets/shelf_life_card.dart';
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr('صوّر العين قريبة، أو الخياشيم وهي مفتوحة', 'Take a close-up of the eye, or of the open gills'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('الكاميرا', 'Camera')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('من الصور', 'From photos')),
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
    appBar: AppBar(title: Text(tr('نتيجة التحليل', 'Result'))),
    // أندرويد الحديث يرسم التطبيق تحت شريط التنقل، فنضيف مسافته تحت حتى ما يغطي آخر بطاقة.
    body: ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.paddingOf(context).bottom + 8),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * .25).clamp(140, 240),
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
            if (snap.error is FishIdQuotaException) return _Subscribe(message: '${snap.error}');
            if (snap.hasError) return _Error(message: '${snap.error}', onRetry: _retry);
            final (result, db) = snap.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_body(result, db)]);
          },
        ),
      ],
    ),
  );

  Widget _body(FishResult r, Ksafish db) {
    if (!r.isFish) {
      return _Message(
        icon: Icons.search_off,
        text:
            '${tr('ما ظهرت سمكة واضحة في الصورة.', 'No clear fish in the photo.')}${r.subject.isEmpty ? '' : ' ${r.subject}'}',
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
        if (isDemo && !const bool.fromEnvironment("STORE"))
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('وضع التجربة: هذه نتيجة مثال.', style: TextStyle(color: AppColors.muted)),
          ),
        if (cands.length > 1) ...[
          Text(
            tr('الاحتمالات', 'Possible species'),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, (c, s)) in cands.indexed)
                ChoiceChip(
                  label: Text('${s.name} · \u2066${c.confidence}%\u2069'),
                  selected: i == sel,
                  onSelected: (_) => setState(() => _selected = i),
                  selectedColor: AppColors.gold,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // الطزاجة أول شيء بعد الاحتمالات: هي اللي يقرر عليها المشتري.
        if (r.freshness case final f?) ...[FreshnessCard(freshness: f), const SizedBox(height: 12)],
        if (r.photoTip.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline, color: AppColors.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${tr('نصيحة', 'Tip')}: ${r.photoTip}', style: const TextStyle(height: 1.5))),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_images.length < _maxPhotos) ...[
          OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              _images.length == 1
                  ? tr('أضف صورة العين أو الخياشيم', 'Add a photo of the eye or gills')
                  : tr('أضف صورة ثالثة', 'Add a third photo'),
            ),
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
                ? tr(
                    'يبدو أنها ليست ضمن أنواع الموسوعة. أقرب تخمين: ${r.outsideListGuess}',
                    'It seems not to be in the encyclopedia. Closest guess: ${r.outsideListGuess}',
                  )
                : tr(
                    'ما قدرنا نحدد النوع من أنواع الموسوعة.',
                    'We could not match it to a species in the encyclopedia.',
                  ),
          ),
        const SizedBox(height: 12),
        ShelfLifeCard(
          key: ValueKey(cands.isNotEmpty ? cands[sel].$2.id : ''),
          family: cands.isNotEmpty ? cands[sel].$2.family : '',
          photoDays: switch (r.freshness) {
            final f? when f.assessable && f.daysMin >= 0 && f.daysMax >= 0 => (f.daysMin + f.daysMax) / 2,
            _ => null,
          },
        ),
        const SizedBox(height: 12),
        ContributeCard(
          key: ValueKey(_images.length),
          images: List.of(_images),
          candidates: [for (final (_, s) in cands) (s.id.split('-').last, s.name)],
          score: r.freshness?.assessable == true ? r.freshness!.score : -1,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const CircularProgressIndicator(color: AppColors.navy),
        const SizedBox(height: 16),
        Text(
          tr('نحلل الصورة…', 'Analyzing the photo…'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            'نقارنها بـ 447 نوعًا ونفحص العين والخياشيم والجلد',
            'Comparing with 447 species and checking the eyes, gills and skin',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
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
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: Text(tr('حاول مرة ثانية', 'Try again')),
      ),
    ],
  );
}

/// تظهر لما تخلص الفحوصات: الباقات بأسعارها من المتجر، أو الأسعار الثابتة لو المتجر مو جاهز.
class _Subscribe extends StatefulWidget {
  const _Subscribe({required this.message});
  final String message;

  @override
  State<_Subscribe> createState() => _SubscribeState();
}

class _SubscribeState extends State<_Subscribe> {
  late final Future<List<Package>> _packages = Billing.packages();
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      if (!await action()) return;
      final active = (FishIdApi.remaining.value ?? 0) > 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            active
                ? tr('اشتراكك فعّال، صوّر السمكة من جديد', 'You are subscribed. Take the photo again')
                : tr(
                    'وصلنا الدفع، والاشتراك يتفعّل خلال دقيقة',
                    'Payment received. Your subscription will be active within a minute',
                  ),
          ),
        ),
      );
      navigator.pop();
    } on FishIdException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.navy,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: FutureBuilder(
        future: _packages,
        builder: (context, snap) {
          final packages = snap.data ?? const <Package>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.workspace_premium_outlined, color: AppColors.gold, size: 36),
              const SizedBox(height: 8),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.5),
              ),
              const SizedBox(height: 14),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator(color: AppColors.gold))
              else if (packages.isNotEmpty) ...[
                for (final p in packages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Plan(
                      title: Billing.title(p),
                      price: p.storeProduct.priceString,
                      note: p.packageType == PackageType.annual ? tr('بالسنة', 'per year') : tr('بالشهر', 'per month'),
                      onTap: _busy ? null : () => _run(() => Billing.buy(p)),
                    ),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await Billing.restore();
                          return (FishIdApi.remaining.value ?? 0) > 0;
                        }),
                  child: Text(
                    tr('اشتركت قبل؟ استرجع اشتراكك', 'Subscribed before? Restore'),
                    style: const TextStyle(color: AppColors.gold),
                  ),
                ),
                if (Billing.isIOS) const _Terms(),
              ] else ...[
                _Plan(title: tr('شهري', 'Monthly'), price: tr('25 ريال', 'SAR 25'), note: tr('بالشهر', 'per month')),
                const SizedBox(height: 8),
                _Plan(
                  title: tr('سنوي', 'Yearly'),
                  price: tr('199 ريال', 'SAR 199'),
                  note: tr('بالسنة، توفّر 33%', 'per year, save 33%'),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: null,
                  child: Text(tr('الاشتراك من المتجر قريبًا', 'Store subscriptions coming soon')),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                tr('الموسوعة وحاسبة الصلاحية تبقى مجانية.', 'The encyclopedia and shelf-life calculator stay free.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onNavyMuted, fontSize: 14),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// شروط الاشتراك المتجدد وروابطها، تطلبها أبل في صفحة الاشتراك (القاعدة 3.1.2).
class _Terms extends StatelessWidget {
  const _Terms();

  static const _eula = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const _privacy = 'https://hawat.id/privacy.html';

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: AppColors.onNavyMuted, fontSize: 12, height: 1.5);
    Widget link(String label, String url) => TextButton(
      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(label, style: const TextStyle(color: AppColors.gold, fontSize: 13)),
    );
    return Column(
      children: [
        Text(
          tr(
            'الاشتراك يتجدد تلقائيًا بنفس السعر والمدة، إلا لو ألغيته قبل نهاية المدة بـ 24 ساعة على الأقل من إعدادات حسابك في App Store.',
            'The subscription renews automatically at the same price and length unless you cancel it at least 24 hours before the period ends, in your App Store account settings.',
          ),
          textAlign: TextAlign.center,
          style: muted,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            link(tr('شروط الاستخدام', 'Terms of Use'), _eula),
            link(tr('سياسة الخصوصية', 'Privacy Policy'), L10n.en ? '$_privacy#en' : _privacy),
          ],
        ),
      ],
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.title, required this.price, required this.note, this.onTap});
  final String title;
  final String price;
  final String note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.navyLight,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(note, style: const TextStyle(color: AppColors.onNavyMuted, fontSize: 13)),
            const SizedBox(width: 10),
            Text(
              price,
              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(L10n.en ? Icons.chevron_right : Icons.chevron_left, color: AppColors.gold),
            ],
          ],
        ),
      ),
    ),
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
              child: Text('${tr('نصيحة', 'Tip')}: $tip', style: const TextStyle(color: AppColors.muted)),
            ),
        ],
      ),
    ),
  );
}
