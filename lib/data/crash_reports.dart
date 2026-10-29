import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// تقارير الأعطال عن طريق Firebase Crashlytics (مشروع FISH ID تحت ksafish.com).
/// يرسل نوع الخطأ ومكانه في الكود ونوع الجوال فقط، بدون رقم الحساب أو الصور.
abstract final class CrashReports {
  /// مفاتيح Firebase عامة بطبيعتها وتنحط في التطبيق، وتعرّف المشروع فقط.
  static const _android = FirebaseOptions(
    apiKey: 'AIzaSyC8e27bmvHQ_8pAgHH8bVAcLQltm1gdCrQ',
    appId: '1:776524521205:android:e3682fa884af938ac5afbc',
    messagingSenderId: '776524521205',
    projectId: 'fish-id-76104',
    storageBucket: 'fish-id-76104.firebasestorage.app',
  );
  static const _ios = FirebaseOptions(
    apiKey: 'AIzaSyCuEAZC_ez5UcuqoifyhRTyvUprE0OwzME',
    appId: '1:776524521205:ios:400a8d973c99269bc5afbc',
    messagingSenderId: '776524521205',
    projectId: 'fish-id-76104',
    storageBucket: 'fish-id-76104.firebasestorage.app',
    iosBundleId: 'sa.hawat.fishId',
  );

  /// يشتغل في نسخ الجوال فقط. لو تعطل Firebase نفسه نكمل بدون تقارير، وما نوقف التطبيق.
  static Future<void> start() async {
    if (kIsWeb) return;
    final options = switch (defaultTargetPlatform) {
      TargetPlatform.android => _android,
      TargetPlatform.iOS => _ios,
      _ => null,
    };
    if (options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      final crashlytics = FirebaseCrashlytics.instance;
      // نسخ التطوير ما ترسل شي، عشان ما تختلط أعطالها بأعطال المستخدمين.
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = crashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } on Object catch (e) {
      debugPrint('Crashlytics off: $e');
    }
  }
}
