import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late Store store;
  setUp(() => store = Store(openMemoryDb()));

  test('water adds up within a day; steps and weight replace', () {
    store.addWater(250);
    expect(store.addWater(500), 750);
    store.setHealth(today(), HealthKind.steps, 4000);
    store.setHealth(today(), HealthKind.steps, 6500);
    store.setHealth(today(), HealthKind.weight, 71.5);
    final day = store.healthDays(days: 1).single;
    expect((day.water, day.steps, day.weight), (750, 6500, 71.5));
  });

  test('workouts are listed for their day', () {
    store.addWorkout('Push: bench 3x8 60kg', minutes: 50);
    expect(store.healthDays(days: 1).single.workouts.single.detail, 'Push: bench 3x8 60kg');
  });

  test('a tracked night wins over the guess from phone use', () {
    store.setHealth(today(), HealthKind.sleep, 450, detail: '01:30-09:00');
    final day = store.healthDays(days: 1).single;
    expect((day.sleepMin, day.sleepGuessed), (450, false));
  });
}
