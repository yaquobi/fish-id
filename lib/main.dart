import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() => runApp(const FishIdApp());

class FishIdApp extends StatelessWidget {
  const FishIdApp({super.key, this.home = const HomeScreen()});

  /// أول شاشة. تتغير في الاختبارات واللقطات فقط.
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FISH ID',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // خط الجوال المكبَّر يكسر التصميم فوق حد معيّن، فنقيّده. وعلى الأجهزة العريضة نحصر المحتوى في الوسط.
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: .9, maxScaleFactor: 1.2)),
        child: ColoredBox(
          color: AppColors.navyDeep,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
          ),
        ),
      );
    },
    home: home,
  );
}
