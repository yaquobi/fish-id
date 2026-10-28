import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/fish_id_api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import 'browse_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FishIdApi.refreshRemaining();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // تصغير الصورة يسرّع الرفع ويبقيها تحت حد الخادم (5MB).
      final file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ResultScreen(image: bytes)));
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'ما قدرنا نفتح الكاميرا أو الصور. تأكد من الصلاحيات في إعدادات الجوال.',
                'Could not open the camera or photos. Check the permissions in your phone settings.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // الجوالات القصيرة: شعار أصغر ومسافات أقل عشان أزرار التصوير تبان بدون تمرير.
    final compact = MediaQuery.sizeOf(context).height < 720;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.navyDeep, AppColors.navy],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top + (compact ? 20 : 36),
                  24,
                  compact ? 22 : 32,
                ),
                child: Column(
                  children: [
                    FishIdMark(size: compact ? 80 : 104),
                    SizedBox(height: compact ? 8 : 14),
                    FishIdWordmark(size: compact ? 28 : 32),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'صوّر السمكة، ونقول لك نوعها ومدى طزاجتها وكل شيء عنها.',
                        'Snap a fish, and we tell you its species, how fresh it is, and all about it.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.onNavyMuted, fontSize: 15, height: 1.6),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + 4,
                end: 4,
                child: IconButton(
                  tooltip: tr('القائمة', 'Menu'),
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () =>
                      showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _Menu()),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 16 : 24, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isDemo && !const bool.fromEnvironment("STORE"))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _Note(
                      icon: Icons.science_outlined,
                      text:
                          'وضع التجربة: النتيجة مثال ثابت ولا تُرسل الصورة لأي خادم. Demo mode: a fixed sample result.',
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(tr('صوّر السمكة', 'Take a photo')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(tr('اختر صورة من الجوال', 'Choose from your photos')),
                ),
                ValueListenableBuilder(
                  valueListenable: FishIdApi.remaining,
                  builder: (context, n, _) => n == null
                      ? const SizedBox(height: 24)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 16),
                          child: Text(
                            n > 0
                                ? tr('باقي لك $n ${n == 1 ? 'فحص' : 'فحوصات'}', '$n ${n == 1 ? 'scan' : 'scans'} left')
                                : tr('خلصت فحوصاتك، اشترك عشان تكمل', 'No scans left. Subscribe to keep scanning'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted, fontSize: 14),
                          ),
                        ),
                ),
                const _Tips(),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined, color: AppColors.navy),
                    title: Text(
                      tr('تصفّح أنواع الموسوعة', 'Browse the encyclopedia'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      tr('447 نوعًا من البحر الأحمر والخليج العربي', '447 species of the Red Sea and Arabian Gulf'),
                    ),
                    trailing: Icon(L10n.en ? Icons.chevron_right : Icons.chevron_left),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BrowseScreen())),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  tr('إحدى مبادرات منظومة حوات', 'Part of the HUWAT initiative'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('لصورة تعطي أدق نتيجة', 'For the most accurate result'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          _Tip(
            icon: Icons.straighten,
            text: tr(
              'صوّر السمكة كاملة من الجنب، من الرأس إلى الذيل.',
              'Shoot the whole fish from the side, head to tail.',
            ),
          ),
          _Tip(
            icon: Icons.visibility_outlined,
            text: tr(
              'خلّ العين واضحة، ولو تقدر افتح الخياشيم للطزاجة.',
              'Keep the eye clear, and open the gills if you can for freshness.',
            ),
          ),
          _Tip(
            icon: Icons.wb_sunny_outlined,
            text: tr(
              'إضاءة طبيعية وبدون فلاش قوي يعكس على الجلد.',
              'Use natural light, without a strong flash that reflects off the skin.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.navyLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(height: 1.5, color: AppColors.ink)),
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Icon(icon, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}

/// القائمة: اللغة، ورمز الهدية، ورقم الحساب (لطلب حذف البيانات)، والخصوصية والتواصل.
class _Menu extends StatelessWidget {
  const _Menu();

  static const _privacy = 'https://hawat.id/privacy.html';
  static const _email = 'yaquobi@hawat.sa';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {L10n.lang.value},
            onSelectionChanged: (v) {
              Navigator.of(context).pop();
              L10n.set(v.first);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.redeem_outlined),
            title: Text(tr('عندك رمز؟', 'Have a code?')),
            onTap: () {
              Navigator.of(context).pop();
              showDialog<void>(context: context, builder: (_) => const _CodeDialog());
            },
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(tr('رقم حسابك', 'Your account ID')),
            subtitle: Text(tr('انسخه وأرسله لنا لو تبي نحذف بياناتك', 'Copy it and email us to delete your data')),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final id = await FishIdApi.userId();
              await Clipboard.setData(ClipboardData(text: id));
              messenger.showSnackBar(SnackBar(content: Text(tr('نسخنا رقم حسابك: $id', 'Account ID copied: $id'))));
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('سياسة الخصوصية', 'Privacy policy')),
            onTap: () =>
                launchUrl(Uri.parse(L10n.en ? '$_privacy#en' : _privacy), mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(tr('تواصل معنا', 'Contact us')),
            subtitle: const Text(_email, textDirection: TextDirection.ltr),
            onTap: () => launchUrl(Uri.parse('mailto:$_email?subject=FISH%20ID')),
          ),
        ],
      ),
    ),
  );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FishIdApi.redeem(_code.text);
      if (!mounted) return;
      final n = FishIdApi.remaining.value;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == null ? tr('تمت إضافة الفحوصات', 'Scans added') : tr('صار عندك $n فحص', 'You now have $n scans'),
          ),
        ),
      );
    } on FishIdException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('رمز الهدية', 'Gift code')),
    content: TextField(
      controller: _code,
      autofocus: true,
      textDirection: TextDirection.ltr,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(hintText: 'FISH-XXXXXXXX', errorText: _error),
      onSubmitted: (_) => _redeem(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('إلغاء', 'Cancel'))),
      FilledButton(onPressed: _busy ? null : _redeem, child: Text(tr('استخدم الرمز', 'Redeem'))),
    ],
  );
}
