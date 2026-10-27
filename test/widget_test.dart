import 'package:fish_id/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows capture actions and tagline', (tester) async {
    await tester.pumpWidget(const FishIdApp());
    expect(find.text('صوّر السمكة'), findsOneWidget);
    expect(find.text('اختر صورة من الجوال'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('إحدى مبادرات منظومة حوات'), 200);
    expect(find.text('إحدى مبادرات منظومة حوات'), findsOneWidget);
  });
}
