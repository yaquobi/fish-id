import 'package:fish_id/widgets/shelf_life_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shelf life card renders and warns for kingfish family', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(child: ShelfLifeCard(family: 'SCOMBRIDAE', photoDays: 1.5)),
          ),
        ),
      ),
    );
    expect(find.text('كم باقي لها؟'), findsOneWidget);
    expect(find.textContaining('على الثلج'), findsWidgets);
    expect(find.textContaining('الهيستامين'), findsOneWidget);
  });
}
