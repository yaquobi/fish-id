// لقطات متجر Google Play بمقاس 1080×1920، بدون شريط وضع التجربة.
// flutter test --dart-define=API_URL=DEMO --dart-define=STORE=true --update-goldens --plain-name home tool/shots/store_test.dart
// (شغّل كل اختبار لحاله: home و result و browse و species). الإطارات والعناوين في store/frame.html.
import 'dart:io';

import 'package:fish_id/data/ksafish.dart';
import 'package:fish_id/main.dart';
import 'package:fish_id/screens/browse_screen.dart';
import 'package:fish_id/screens/result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  setUpAll(loadFonts);
  final img = File('tool/shots/store-fish.jpg').readAsBytesSync();

  Future<void> shot(
    WidgetTester t,
    String name,
    Widget Function() build, {
    Future<void> Function(WidgetTester)? go,
    double h = 640,
  }) async {
    t.view.physicalSize = Size(1080, h * 3);
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 72, bottom: 48);
    t.view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
    await t.runAsync(Ksafish.load);
    await t.pumpWidget(build());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2600)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    }
    if (go != null) await go(t);
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('store/$name.png'));
  }

  Widget app(Widget home) => FishIdApp(home: home);
  testWidgets('home', (t) => shot(t, '1-home', () => const FishIdApp()));
  testWidgets('result', (t) => shot(t, '2-result', () => app(ResultScreen(image: img)), h: 3200));
  testWidgets(
    'browse',
    (t) => shot(
      t,
      '6-browse',
      () => app(const BrowseScreen()),
      go: (t) async {
        for (var i = 0; i < 5; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
          await t.pump(const Duration(seconds: 1));
        }
      },
    ),
  );
  testWidgets(
    'species',
    (t) => shot(
      t,
      '7-species',
      () => app(const BrowseScreen()),
      h: 2400,
      go: (t) async {
        for (var i = 0; i < 5; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
          await t.pump(const Duration(seconds: 1));
        }
        await t.tap(find.byType(ListTile).at(2));
        for (var i = 0; i < 5; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
          await t.pump(const Duration(seconds: 1));
        }
      },
    ),
  );
}
