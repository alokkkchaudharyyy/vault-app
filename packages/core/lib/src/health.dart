import 'dates.dart';
import 'planning.dart';
import 'store.dart';

/// Health by day: steps and sleep (from Health Connect on the phone, or sleep
/// worked out from when the phone was last and first used), water, weight
/// and workouts (typed in).
abstract final class HealthKind {
  static const steps = 'steps';

  /// Minutes asleep; `detail` is "bed-wake" in local time.
  static const sleep = 'sleep';

  /// Millilitres.
  static const water = 'water';

  /// Kilograms.
  static const weight = 'weight';

  /// Minutes, if known; `detail` says what was done.
  static const workout = 'workout';
}

class HealthDay {
  HealthDay(this.date);

  final String date;
  int? steps;
  int? sleepMin;
  String? sleepDetail;

  /// True when sleep came from phone use rather than a tracker.
  bool sleepGuessed = false;
  int water = 0;
  double? weight;
  final workouts = <({String id, String detail, int? minutes})>[];

  Map<String, Object?> toJson() => {
        'date': date,
        if (steps != null) 'steps': steps,
        if (sleepMin != null) 'sleep': '${sleepMin! ~/ 60}h ${sleepMin! % 60}m${sleepDetail == null ? '' : ' ($sleepDetail)'}',
        if (sleepMin != null && sleepGuessed) 'sleep_from': 'phone use',
        if (water > 0) 'water_ml': water,
        if (weight != null) 'weight_kg': weight,
        if (workouts.isNotEmpty) 'workouts': [for (final w in workouts) {'what': w.detail, 'minutes': ?w.minutes}],
      };
}

extension HealthLog on Store {
  /// One value per day for steps, sleep, water and weight: writing again
  /// replaces it.
  void setHealth(String date, String kind, double value, {String? detail}) {
    final id = '$kind-$date';
    final now = Store.nowUtc();
    final exists = db.select('SELECT value, detail, deleted_at FROM health WHERE id = ?', [id]);
    if (exists.isEmpty) {
      db.execute(
        'INSERT INTO health (id, date, kind, value, detail, created_at, updated_at, dirty) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
        [id, date, kind, value, detail, now, now],
      );
    } else {
      final r = exists.first;
      if (r['value'] == value && r['detail'] == detail && r['deleted_at'] == null) return;
      db.execute(
        'UPDATE health SET value = ?, detail = ?, deleted_at = NULL, updated_at = ?, dirty = 1 WHERE id = ?',
        [value, detail, now, id],
      );
    }
  }

  /// Adds [ml] of water to [date] (today by default); negative takes away.
  int addWater(int ml, {String? date}) {
    final d = date ?? today();
    final current = (db.select('SELECT value FROM health WHERE id = ? AND deleted_at IS NULL', ['water-$d']).firstOrNull?['value'] as num?) ?? 0;
    final total = (current + ml).clamp(0, 20000).toInt();
    setHealth(d, HealthKind.water, total.toDouble());
    return total;
  }

  String addWorkout(String what, {int? minutes, String? date}) {
    if (what.trim().isEmpty) throw TodoException('Say what the workout was');
    final id = Store.newId();
    final now = Store.nowUtc();
    db.execute(
      'INSERT INTO health (id, date, kind, value, detail, created_at, updated_at, dirty) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
      [id, date ?? today(), HealthKind.workout, minutes?.toDouble(), what.trim(), now, now],
    );
    return id;
  }

  void deleteHealth(String id) =>
      db.execute('UPDATE health SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?', [Store.nowUtc(), Store.nowUtc(), id]);

  /// The [days] days up to [until] (today), oldest first. Sleep on a day is
  /// the night before it.
  List<HealthDay> healthDays({int days = 7, String? until}) {
    final last = until ?? today();
    final first = addDays(last, -(days - 1));
    final byDate = {for (var d = first; d.compareTo(last) <= 0; d = addDays(d, 1)) d: HealthDay(d)};
    for (final r in db.select(
      'SELECT * FROM health WHERE deleted_at IS NULL AND date BETWEEN ? AND ? ORDER BY created_at',
      [first, last],
    )) {
      final day = byDate[r['date']];
      if (day == null) continue;
      final value = r['value'] as num?;
      switch (r['kind']) {
        case HealthKind.steps:
          day.steps = value?.round();
        case HealthKind.sleep:
          day.sleepMin = value?.round();
          day.sleepDetail = r['detail'] as String?;
        case HealthKind.water:
          day.water = value?.round() ?? 0;
        case HealthKind.weight:
          day.weight = value?.toDouble();
        case HealthKind.workout:
          day.workouts.add((id: r['id'] as String, detail: r['detail'] as String? ?? '', minutes: value?.round()));
      }
    }
    // No tracker: the night between the last and the first sign of being awake.
    final records = {for (final d in stats(days: days + 1, until: last).days) d.date: d};
    for (final day in byDate.values.where((d) => d.sleepMin == null)) {
      final wake = records[day.date]?.wake, bed = records[addDays(day.date, -1)]?.bed;
      if (wake == null || bed == null) continue;
      final minutes = wake + 24 * 60 - bed;
      if (minutes < 120 || minutes > 16 * 60) continue;
      day
        ..sleepMin = minutes
        ..sleepDetail = '${clockText(bed % (24 * 60))}-${clockText(wake)}'
        ..sleepGuessed = true;
    }
    return byDate.values.toList();
  }

  /// The latest weight, from any day.
  double? latestWeight() => (db
          .select("SELECT value FROM health WHERE deleted_at IS NULL AND kind = 'weight' ORDER BY date DESC LIMIT 1")
          .firstOrNull?['value'] as num?)
      ?.toDouble();
}
