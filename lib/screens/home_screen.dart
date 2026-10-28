import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/fish_id_api.dart';
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ما قدرنا نفتح الكاميرا أو الصور. تأكد من الصلاحيات في إعدادات الجوال.')));
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
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.navyDeep, AppColors.navy],
              ),
            ),
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + (compact ? 20 : 36), 24, compact ? 22 : 32),
            child: Column(
              children: [
                FishIdMark(size: compact ? 80 : 104),
                SizedBox(height: compact ? 8 : 14),
                FishIdWordmark(size: compact ? 28 : 32),
                const SizedBox(height: 8),
                const Text(
                  'صوّر السمكة، ونقول لك نوعها ومدى طزاجتها وكل شيء عنها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.onNavyMuted, fontSize: 15, height: 1.6),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 16 : 24, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isDemo)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _Note(icon: Icons.science_outlined, text: 'وضع التجربة: النتيجة مثال ثابت ولا تُرسل الصورة لأي خادم.'),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('صوّر السمكة'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('اختر صورة من الجوال'),
                ),
                const SizedBox(height: 24),
                const _Tips(),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined, color: AppColors.navy),
                    title: const Text('تصفّح أنواع الموسوعة', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('447 نوعًا من البحر الأحمر والخليج العربي'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BrowseScreen())),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'إحدى مبادرات منظومة حوات',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
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
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('لصورة تعطي أدق نتيجة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          SizedBox(height: 10),
          _Tip(icon: Icons.straighten, text: 'صوّر السمكة كاملة من الجنب، من الرأس إلى الذيل.'),
          _Tip(icon: Icons.visibility_outlined, text: 'خلّ العين واضحة، ولو تقدر افتح الخياشيم للطزاجة.'),
          _Tip(icon: Icons.wb_sunny_outlined, text: 'إضاءة طبيعية وبدون فلاش قوي يعكس على الجلد.'),
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
