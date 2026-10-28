import 'package:fish_id/l10n.dart';
import 'package:fish_id/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => L10n.lang.value = 'ar');

  testWidgets('home shows capture actions and tagline', (tester) async {
    await tester.pumpWidget(const FishIdApp());
    expect(find.text('صوّر السمكة'), findsOneWidget);
    expect(find.text('اختر صورة من الجوال'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('إحدى مبادرات منظومة'), 200);
    expect(find.text('إحدى مبادرات منظومة'), findsOneWidget);
  });

  testWidgets('the menu switches the app to English and left-to-right', (tester) async {
    await tester.pumpWidget(const FishIdApp());
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('عندك رمز؟'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Take a photo'))), TextDirection.ltr);
  });
}
