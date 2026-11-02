import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/billing.dart';
import '../data/fish_id_api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'result_screen.dart' show SubscriptionTerms;

/// باقة المحلات والمطاعم: صاحب المحل يشترك من المتجر، ويطلع له رمز محله يعطيه موظفينه
/// (يكتبونه في «عندك رمز؟» أو يضيفهم من لوحة المحل في الموقع)، وكلهم يفحصون من رصيد واحد.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final Future<Package?> _package = Billing.shopPackage();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FishIdApi.refreshRemaining();
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      await FishIdApi.refreshRemaining();
      if (FishIdApi.shop.value != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'اشتراك محلك فعّال ✅ أعط موظفينك رمز المحل',
                'Your shop plan is active. Give your staff the shop code',
              ),
            ),
          ),
        );
      }
    } on FishIdException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('باقة المحلات والمطاعم', 'Shops and restaurants'))),
    body: ValueListenableBuilder(
      valueListenable: FishIdApi.shop,
      builder: (context, shop, _) =>
          ListView(padding: const EdgeInsets.all(16), children: shop == null ? _offer(context) : _owner(context, shop)),
    ),
  );

  static Widget _point(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.gold, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white, height: 1.5)),
        ),
      ],
    ),
  );

  List<Widget> _offer(BuildContext context) => [
    Container(
      color: AppColors.navy,
      padding: const EdgeInsets.all(18),
      child: FutureBuilder(
        future: _package,
        builder: (context, snap) {
          final p = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('افحص شحنة السمك وقت الاستلام من جوالات موظفينك', 'Check fish deliveries from your staff phones'),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 12),
              _point(
                Icons.photo_camera_outlined,
                tr('300 فحص بالشهر، مشتركة بين جوالات المحل', '300 scans a month, shared by your shop phones'),
              ),
              _point(
                Icons.phone_android_outlined,
                tr('لحد 5 جوالات: موظفينك يكتبون رمز محلك', 'Up to 5 phones: your staff enter your shop code'),
              ),
              _point(
                Icons.verified_outlined,
                tr('النوع والاسم المحلي والطزاجة من 100', 'Species, local name and freshness out of 100'),
              ),
              const SizedBox(height: 14),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator(color: AppColors.gold))
              else if (p != null) ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: _busy ? null : () => _run(() async => Billing.buy(p)),
                  child: Text(
                    '${tr('اشترك', 'Subscribe')} · ${p.storeProduct.priceString} ${tr('بالشهر', 'per month')}',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(Billing.restore),
                  child: Text(
                    tr('اشتركت قبل؟ استرجع اشتراكك', 'Subscribed before? Restore'),
                    style: const TextStyle(color: AppColors.gold),
                  ),
                ),
                if (Billing.isIOS) const SubscriptionTerms(),
              ] else
                Text(
                  tr('الاشتراك من المتجر يتفعّل قريب.', 'Store subscription is coming soon.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.onNavyMuted),
                ),
            ],
          );
        },
      ),
    ),
    const SizedBox(height: 16),
    Text(
      tr(
        'موظف في محل مشترك؟ خذ رمز المحل من صاحب المحل واكتبه في القائمة «عندك رمز؟»، أو أرسل له «رقم حسابك» من القائمة.',
        'Work at a subscribed shop? Get the shop code from the owner and enter it under "Have a code?" in the menu, or send them "Your account ID".',
      ),
      style: const TextStyle(color: AppColors.muted, height: 1.6),
    ),
    // الدفع بالتحويل أو بمدى من الموقع: رابط على أندرويد بس (أبل تمنع روابط الشراء خارج المتجر).
    if (!Billing.isIOS) ...[
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => launchUrl(Uri.parse('https://hawat.id/shop/'), mode: LaunchMode.externalApplication),
        child: Text(
          tr('تبغى تدفع تحويل أو بفاتورة لمحلك؟ من الموقع', 'Prefer bank transfer or an invoice? Use the website'),
        ),
      ),
    ],
  ];

  List<Widget> _owner(BuildContext context, Map<String, dynamic> shop) {
    final code = '${shop['code']}';
    return [
      Container(
        color: AppColors.navy,
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(tr('رمز محلك', 'Your shop code'), style: const TextStyle(color: AppColors.onNavyMuted)),
            const SizedBox(height: 8),
            SelectableText(
              code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 30,
                letterSpacing: 3,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.onNavyMuted),
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: code));
                messenger.showSnackBar(SnackBar(content: Text(tr('نسخنا رمز المحل', 'Shop code copied'))));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: Text(tr('نسخ الرمز', 'Copy code')),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: _stat(tr('فحوصات هذا الشهر', 'Scans this month'), '${shop['used']} / ${shop['cap']}')),
          const SizedBox(width: 10),
          Expanded(child: _stat(tr('الجوالات', 'Phones'), '${shop['devices']} / ${shop['maxDevices']}')),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        tr(
          'موظفك ينزّل التطبيق، يفتح القائمة ويضغط «عندك رمز؟» ويكتب الرمز. على آيفون: يرسل لك «رقم حسابك» من القائمة وتكلّمنا واتساب نضيفه.',
          'Your staff install the app, open the menu, tap "Have a code?" and enter the code. On iPhone: they send you "Your account ID" from the menu and you message us on WhatsApp to add it.',
        ),
        style: const TextStyle(color: AppColors.muted, height: 1.6),
      ),
    ];
  }

  static Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      ],
    ),
  );
}
