import 'package:fish_id/data/shelf_life.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ice keeps the full band', () {
    final r = ShelfLife.compute([const StorageStep(Storage.ice, 48)]);
    expect(r.usedDays, closeTo(2, 1e-9));
    expect(r.minDays, closeTo(10, 1e-9));
    expect(r.discard, isFalse);
  });

  test('six hours at room temperature uses about 5 ice days', () {
    final r = ShelfLife.compute([const StorageStep(Storage.room, 6)]);
    // exp(0.12 × 25) ≈ 20.1
    expect(r.usedDays, closeTo(6 * 20.0855 / 24, 0.01));
    expect(r.discard, isFalse);
  });

  test('two hours above 30 °C is a hard discard', () {
    final r = ShelfLife.compute([const StorageStep(Storage.ice, 24), const StorageStep(Storage.hot, 2)]);
    expect(r.discard, isTrue);
    expect(r.remainingLabel, 'انتهت مدتها الآمنة');
  });

  test('frozen time does not count', () {
    final r = ShelfLife.compute([const StorageStep(Storage.frozen, 240)]);
    expect(r.usedDays, 0);
  });

  test('histamine warning only for scombroid families left warm', () {
    const warm = [StorageStep(Storage.room, 3)];
    expect(ShelfLife.compute(warm, family: 'SCOMBRIDAE').histamineRisk, isTrue);
    expect(ShelfLife.compute(warm, family: 'SERRANIDAE').histamineRisk, isFalse);
    expect(ShelfLife.compute([const StorageStep(Storage.fridge, 48)], family: 'SCOMBRIDAE').histamineRisk, isFalse);
  });
}
