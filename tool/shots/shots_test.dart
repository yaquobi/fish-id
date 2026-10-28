// لقطات لكل الشاشات على مقاسات جوالات مختلفة، مع رصد أي تجاوز في المقاسات.
// flutter test --dart-define=API_URL=DEMO --update-goldens tool/shots/shots_test.dart
import 'dart:io';

import 'package:fish_id/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fish_id/screens/result_screen.dart';
import 'package:fish_id/screens/browse_screen.dart';

Future<void> loadFonts() async {
  Future<void> fam(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await fam('Tajawal', ['Regular', 'Medium', 'Bold', 'ExtraBold'].map((w) => 'assets/fonts/Tajawal-$w.ttf').toList());
  await fam('ChakraPetch', ['SemiBold', 'Bold'].map((w) => 'assets/fonts/ChakraPetch-$w.ttf').toList());
  await fam('MaterialIcons', ['/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

const sizes = {'s320x568': Size(320, 568), 'm360x780': Size(360, 780), 'l412x915': Size(412, 915)};
const scales = [1.0, 1.2];

void main() {
  final issues = <String>[];
  setUpAll(loadFonts);
  tearDownAll(() => File('tool/shots/issues.txt').writeAsStringSync(issues.join('\n\n')));

  Future<void> shot(
    WidgetTester t,
    String name,
    Widget Function() build, {
    Future<void> Function(WidgetTester)? go,
    bool full = false,
  }) async {
    for (final MapEntry(key: sn, value: size) in sizes.entries) {
      for (final sc in scales) {
        final h = full ? 5000.0 : size.height;
        t.view.physicalSize = Size(size.width, h) * 2;
        t.view.devicePixelRatio = 2;
        t.view.padding = const FakeViewPadding(top: 48, bottom: 96);
        t.view.viewPadding = const FakeViewPadding(top: 48, bottom: 96);
        t.platformDispatcher.textScaleFactorTestValue = sc;
        final old = FlutterError.onError;
        FlutterError.onError = (d) =>
            issues.add('[$name $sn x$sc] ${d.exceptionAsString().split('\n').take(3).join(' ')}');
        await t.pumpWidget(build());
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2600)));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(seconds: 1));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        }
        if (go != null) await go(t);
        await t.pump(const Duration(milliseconds: 500));
        FlutterError.onError = old;
        await expectLater(
          find.byType(MaterialApp).first,
          matchesGoldenFile('out/$name-$sn-x$sc${full ? '-full' : ''}.png'),
        );
        await t.pumpWidget(const SizedBox());
      }
    }
  }

  Widget app(Widget home) => FishIdApp(home: home);
  final img = File('tool/shots/fish.jpg').existsSync()
      ? File('tool/shots/fish.jpg').readAsBytesSync()
      : File('assets/icon/icon.png').readAsBytesSync();

  testWidgets('home', (t) => shot(t, 'home', () => const FishIdApp()));
  testWidgets('browse', (t) => shot(t, 'browse', () => app(const BrowseScreen())));
  testWidgets(
    'species',
    (t) => shot(
      t,
      'species',
      () => app(const BrowseScreen()),
      full: true,
      go: (t) async {
        await t.tap(find.byType(ListTile).first);
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await t.pumpAndSettle();
      },
    ),
  );
  testWidgets('result', (t) => shot(t, 'result', () => app(ResultScreen(image: img))));
  testWidgets('result-full', (t) => shot(t, 'result', () => app(ResultScreen(image: img)), full: true));
}
