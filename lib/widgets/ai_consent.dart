import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/fish_id_api.dart';
import '../l10n.dart';
import '../theme.dart';

/// موافقة إرسال صورة الفحص لخدمة ذكاء اصطناعي خارجية (Claude من Anthropic).
/// أبل (5.1.1 و 5.1.2) تطلب إذنًا واضحًا داخل التطبيق قبل مشاركة بيانات المستخدم مع ذكاء اصطناعي طرف ثالث،
/// فما يكفي ذكرها في سياسة الخصوصية. تنطلب مرة وحدة قبل أول فحص، والمستخدم يقدر يسحبها من القائمة.
abstract final class AiConsent {
  static const _key = 'fishid_ai_consent_v1';
  static const privacyUrl = 'https://hawat.id/privacy.html';

  static Future<bool> granted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> _save(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value ? await prefs.setBool(_key, true) : await prefs.remove(_key);
    } on Object {
      return;
    }
  }

  /// قبل كل فحص: لو وافق قبل نكمل، وإلا نعرض الموافقة. وضع التجربة ما يرسل شي فما يحتاجها.
  static Future<bool> ensure(BuildContext context) async {
    if (isDemo || await granted()) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AiConsentDialog(),
    );
    if (ok == true) await _save(true);
    return ok == true;
  }

  /// من القائمة: يعرض الموافقة من جديد، والرفض يسحبها (يرجع يسأله قبل الفحص الجاي).
  static Future<void> review(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const AiConsentDialog());
    if (ok != null) await _save(ok);
    if (ok == false && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'سحبنا موافقتك. ما نقدر نفحص صورة إلا إذا وافقت من جديد.',
              'Consent withdrawn. We cannot analyze a photo until you agree again.',
            ),
          ),
        ),
      );
    }
  }
}

class AiConsentDialog extends StatelessWidget {
  const AiConsentDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.auto_awesome_outlined, color: AppColors.navy),
    title: Text(tr('قبل أول فحص', 'Before your first scan'), textAlign: TextAlign.center),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'عشان نعرف نوع السمكة وطزاجتها، نرسل الصورة اللي تصوّرها إلى:',
              'To identify the fish and its freshness, the photo you take is sent to:',
            ),
            style: const TextStyle(height: 1.6),
          ),
          const SizedBox(height: 10),
          _Point(
            icon: Icons.dns_outlined,
            text: tr('خادم FISH ID (hawat.id)', 'The FISH ID server (hawat.id)'),
          ),
          _Point(
            icon: Icons.auto_awesome_outlined,
            text: tr(
              'خدمة الذكاء الاصطناعي Claude من شركة Anthropic، وهي اللي تحلل الصورة.',
              'Claude, an AI service by Anthropic, which analyzes the photo.',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'شركة Anthropic تستلم الصورة فقط، بدون اسمك أو رقم جوالك. ما نحفظ صورة الفحص عندنا، و Anthropic ما تستخدمها لتدريب نماذجها.',
              'Anthropic receives only the photo, never your name or phone number. We do not keep scan photos, and Anthropic does not use them to train its models.',
            ),
            style: const TextStyle(height: 1.6, color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => launchUrl(
              Uri.parse(L10n.en ? '${AiConsent.privacyUrl}#en' : AiConsent.privacyUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(tr('اقرأ سياسة الخصوصية', 'Read the privacy policy')),
          ),
        ],
      ),
    ),
    actionsAlignment: MainAxisAlignment.spaceBetween,
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('لا أوافق', 'Don\'t allow'))),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(tr('أوافق وأكمل', 'Agree and continue')),
      ),
    ],
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.navyLight),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}
