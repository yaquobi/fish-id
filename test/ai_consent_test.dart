import 'package:fish_id/main.dart';
import 'package:fish_id/widgets/ai_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the first scan asks for AI consent and declining stops it', (tester) async {
    await tester.pumpWidget(const FishIdApp());
    await tester.tap(find.text('صوّر السمكة'));
    await tester.pumpAndSettle();
    expect(find.text('قبل أول فحص'), findsOneWidget);
    expect(find.textContaining('Anthropic'), findsWidgets);
    expect(find.text('اقرأ سياسة الخصوصية'), findsOneWidget);
    await tester.tap(find.text('لا أوافق'));
    await tester.pumpAndSettle();
    expect(find.text('قبل أول فحص'), findsNothing);
    expect(await AiConsent.granted(), isFalse);
  });

  testWidgets('agreeing is remembered and can be withdrawn from the menu', (tester) async {
    await tester.pumpWidget(const FishIdApp());
    await tester.tap(find.text('صوّر السمكة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أوافق وأكمل'));
    await tester.pumpAndSettle();
    expect(await AiConsent.granted(), isTrue);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحليل الصور بالذكاء الاصطناعي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لا أوافق'));
    await tester.pumpAndSettle();
    expect(await AiConsent.granted(), isFalse);
  });
}
