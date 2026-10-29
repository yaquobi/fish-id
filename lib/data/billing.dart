import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../l10n.dart';
import 'fish_id_api.dart';

/// اشتراكات المتجر عن طريق RevenueCat. الشراء يصير في Google Play أو App Store برقم الحساب نفسه، وبعده يسأل الخادم
/// RevenueCat (POST fishId/sync، وكل حدث على /api/revenuecat) ويفتح الفحوصات.
abstract final class Billing {
  /// مفاتيح RevenueCat العامة لتطبيقي Google Play و App Store. مفاتيح عامة تنحط في التطبيق، وما تسمح إلا بالشراء.
  static const _androidKey = 'goog_hbGYTrOvVqpREIzVQGfbduJsozZ';
  static const _iosKey = 'appl_GFbVefXxLpnsgtEoUEtZohBxEav';

  static Future<bool>? _ready;

  /// المتجر متاح في أندرويد والآيفون، وما يشتغل في الويب أو وضع التجربة.
  static bool get supported =>
      !kIsWeb &&
      !isDemo &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// صفحة الآيفون لازم تعرض روابط الشروط والخصوصية مع الاشتراك المتجدد.
  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> _configure() => _ready ??= () async {
    try {
      await Purchases.configure(PurchasesConfiguration(isIOS ? _iosKey : _androidKey)..appUserID = await FishIdApi.userId());
      return true;
    } on Object {
      _ready = null;
      return false;
    }
  }();

  /// باقات العرض الحالي (شهري وسنوي) بأسعارها من المتجر، أو قائمة فاضية لو المتجر مو جاهز.
  static Future<List<Package>> packages() async {
    if (!supported || !await _configure()) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  /// يشتري الباقة، ويرجّع false لو المستخدم ألغى. الخادم يوصله الحدث خلال ثواني، فننتظر شوي ونحدّث العدّاد.
  static Future<bool> buy(Package package) async {
    try {
      await Purchases.purchase(PurchaseParams.package(package));
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      throw FishIdException(
        tr('تعذّر إتمام الاشتراك، حاول مرة ثانية.', 'Could not complete the purchase. Please try again.'),
      );
    }
    await _refreshAfterPurchase();
    return true;
  }

  /// يسترجع اشتراك سابق على نفس حساب Google أو Apple، مثلًا بعد إعادة تثبيت التطبيق.
  static Future<void> restore() async {
    if (!supported || !await _configure()) return;
    try {
      await Purchases.restorePurchases();
    } on PlatformException {
      throw FishIdException(
        tr('تعذّر استرجاع الاشتراك، حاول مرة ثانية.', 'Could not restore your subscription. Please try again.'),
      );
    }
    await _refreshAfterPurchase();
  }

  static Future<void> _refreshAfterPurchase() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await FishIdApi.sync();
      if ((FishIdApi.remaining.value ?? 0) > 0) return;
    }
  }

  /// نوع الباقة بلغة التطبيق.
  static String title(Package p) => switch (p.packageType) {
    PackageType.annual => tr('سنوي', 'Yearly'),
    PackageType.monthly => tr('شهري', 'Monthly'),
    _ => p.storeProduct.title,
  };
}
