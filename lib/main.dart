import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L10n.load();
  runApp(const FishIdApp());
}

class FishIdApp extends StatelessWidget {
  const FishIdApp({super.key, this.home = const HomeScreen()});

  /// أول شاشة. تتغير في الاختبارات واللقطات فقط.
  final Widget home;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder(valueListenable: L10n.lang, builder: (context, lang, _) => _app(lang));

  // تغيير اللغة يبني التطبيق كله من جديد، فتتبدل النصوص واتجاه الصفحة.
  Widget _app(String lang) => MaterialApp(
    key: ValueKey(lang),
    title: 'FISH ID',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: Locale(lang),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // خط الجوال المكبَّر يكسر التصميم فوق حد معيّن، فنقيّده. وعلى الأجهزة العريضة نحصر المحتوى في الوسط.
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.4)),
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
