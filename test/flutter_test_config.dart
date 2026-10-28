import 'dart:async';

import 'package:fish_id/l10n.dart';

/// جهاز الاختبار لغته إنجليزي، والاختبارات مكتوبة على الواجهة العربية الافتراضية.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  L10n.lang.value = 'ar';
  await testMain();
}
