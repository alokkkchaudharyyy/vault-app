import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'collect.dart';
import 'state.dart';
import 'theme.dart';

const _stepGoal = 8000;
const _waterGoal = 2500;
const _glass = 250;

/// Sleep, steps, water, weight and workouts: today, and the last week.
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  bool _available = false, _access = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final available = await healthAvailable();
    final access = available && await hasHealthAccess();
    if (!mounted) return;
    setState(() {
      _available = available;
      _access = access;
    });
    if (access) await _read();
  }

  Future<void> _read() async {
    final app = AppScope.of(context);
    await collectHealth(app.store);
    app.change((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final week = app.store.healthDays(days: 7);
    final day = week.last;
    final weight = day.weight ?? app.store.latestWeight();

    return RefreshIndicator(
      onRefresh: _read,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          if (_available && !_access)
            Card(
              color: AppColors.raised,
              child: ListTile(
                leading: const Icon(Icons.favorite_rounded, color: AppColors.red),
                title: const Text('Connect Health Connect'),
                subtitle: const Text('Steps and sleep from Samsung Health, Google Fit or your watch'),
                onTap: () async {
                  final ok = await requestHealthAccess();
                  setState(() => _access = ok);
                  if (ok) _read();
                },
              ),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [
              _Tile(
                icon: Icons.bedtime_rounded,
                color: AppColors.lavender,
                label: 'Last night',
                value: day.sleepMin == null ? '—' : '${day.sleepMin! ~/ 60}h ${day.sleepMin! % 60}m',
                detail: day.sleepMin == null
                    ? 'Use the phone tonight and tomorrow'
                    : '${day.sleepDetail ?? ''}${day.sleepGuessed ? ' · from phone use' : ''}',
              ),
              _Tile(
                icon: Icons.directions_walk_rounded,
                color: AppColors.green,
                label: 'Steps',
                value: day.steps == null ? '—' : '${day.steps}',
                detail: day.steps == null ? 'Needs Health Connect' : '${(day.steps! * 100 ~/ _stepGoal)}% of $_stepGoal',
                progress: day.steps == null ? null : day.steps! / _stepGoal,
              ),
              _Tile(
                icon: Icons.water_drop_rounded,
                color: const Color(0xFF5AB8F0),
                label: 'Water',
                value: '${day.water} ml',
                detail: '${day.water ~/ _glass} of ${_waterGoal ~/ _glass} glasses',
                progress: day.water / _waterGoal,
                actions: [
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Less',
                    onPressed: day.water == 0 ? null : () => app.change((s) => s.addWater(-_glass)),
                    icon: const Icon(Icons.remove_rounded, size: 18),
                  ),
                  IconButton.filled(
                    key: const ValueKey('water-add'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'A glass',
                    onPressed: () => app.change((s) => s.addWater(_glass)),
                    icon: const Icon(Icons.add_rounded, size: 18),
                  ),
                ],
              ),
              _Tile(
                icon: Icons.monitor_weight_rounded,
                color: AppColors.cream,
                label: 'Weight',
                value: weight == null ? '—' : '$weight kg',
                detail: day.weight == null ? 'Tap to log today' : 'Logged today',
                onTap: () => _logWeight(context, weight),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Workouts', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _logWorkout(context),
                icon: const Icon(Icons.fitness_center_rounded, size: 18),
                label: const Text('Log'),
              ),
            ],
          ),
          Card(
            child: Column(
              children: [
                if (week.every((d) => d.workouts.isEmpty))
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('None this week.', style: t.bodySmall?.copyWith(color: AppColors.muted)),
                  ),
                for (final d in week.reversed)
                  for (final w in d.workouts)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.fitness_center_rounded, color: AppColors.orange),
                      title: Text(w.detail),
                      subtitle: Text([prettyDate(d.date), if (w.minutes != null) '${w.minutes} min'].join(' · ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => app.change((s) => s.deleteHealth(w.id)),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('This week', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  _WeekBars(
                    label: 'Sleep',
                    color: AppColors.lavender,
                    days: week,
                    value: (d) => (d.sleepMin ?? 0) / 60,
                    max: 10,
                    text: (v) => '${v.toStringAsFixed(1)}h',
                  ),
                  _WeekBars(
                    label: 'Steps',
                    color: AppColors.green,
                    days: week,
                    value: (d) => (d.steps ?? 0).toDouble(),
                    max: _stepGoal * 1.5,
                    text: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.round().toString(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logWeight(BuildContext context, double? current) async {
    final app = AppScope.of(context);
    final text = TextEditingController(text: current?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Weight today'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, text.text), child: const Text('Save')),
        ],
      ),
    );
    final kg = double.tryParse(value ?? '');
    if (kg == null || kg <= 0) return;
    app.change((s) => s.setHealth(today(), HealthKind.weight, kg));
  }

  Future<void> _logWorkout(BuildContext context) async {
    final app = AppScope.of(context);
    final what = TextEditingController(), minutes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Workout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            TextField(
              controller: what,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Push day: bench 3×8 60kg, run 5k…'),
            ),
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Minutes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Log')),
        ],
      ),
    );
    if (ok != true || what.text.trim().isEmpty) return;
    app.change((s) => s.addWorkout(what.text, minutes: int.tryParse(minutes.text)));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
    this.progress,
    this.actions = const [],
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label, value, detail;
  final double? progress;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: 6,
                children: [
                  Icon(icon, size: 18, color: color),
                  Expanded(child: Text(label, style: t.labelLarge?.copyWith(color: AppColors.muted))),
                  ...actions,
                ],
              ),
              const Spacer(),
              Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1),
                      minHeight: 5,
                      color: color,
                      backgroundColor: AppColors.raised,
                    ),
                  ),
                ),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.label,
    required this.color,
    required this.days,
    required this.value,
    required this.max,
    required this.text,
  });

  final String label;
  final Color color;
  final List<HealthDay> days;
  final double Function(HealthDay) value;
  final double max;
  final String Function(double) text;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: t.labelLarge?.copyWith(color: AppColors.muted)),
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              for (final d in days)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 3,
                    children: [
                      if (value(d) > 0) Text(text(value(d)), style: t.labelSmall?.copyWith(fontSize: 9)),
                      Container(
                        height: 56 * (value(d) / max).clamp(0.03, 1),
                        decoration: BoxDecoration(
                          color: value(d) > 0 ? color : AppColors.raised,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Text(_weekdays[parseYmd(d.date).weekday - 1], style: t.labelSmall?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
