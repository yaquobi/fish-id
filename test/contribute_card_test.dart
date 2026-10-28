import 'dart:typed_data';

import 'package:fish_id/widgets/contribute_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('send stays disabled until the user consents', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ContributeCard(images: [Uint8List(4)], candidates: const [('0220', 'شعور رمك')], score: 80),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('أبي أساهم'));
    await tester.pump();
    expect(find.text('شعور رمك'), findsOneWidget);
    FilledButton send() => tester.widget<FilledButton>(
      find.ancestor(of: find.text('أرسل المساهمة'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
    );
    expect(send().onPressed, isNull);
    await tester.tap(find.textContaining('أوافق على حفظ صوري'));
    await tester.pump();
    expect(send().onPressed, isNotNull);
  });
}
