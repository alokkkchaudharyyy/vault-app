import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'heatmap.dart';
import 'state.dart';
import 'theme.dart';
import 'usage_sync.dart';

/// Screen time across laptop and phone: how much, which apps, and when.
class ScreenPage extends StatefulWidget {
  const ScreenPage({super.key});

  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> with WidgetsBindingObserver {
  String _date = today();
  bool _week = false;
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final ok = !collectsUsage || await hasUsageAccess();
    if (mounted) setState(() => _access = ok);
  }

  String _later() {
    final next = addDays(_date, _week ? 7 : 1);
    return next.compareTo(today()) > 0 ? today() : next;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final to = _date;
    final from = _week ? addDays(to, -6) : to;
    final apps = app.store.usageByApp(from, to);
    final days = app.store.usageByDay(from, to);
    final total = days.values.fold(0, (a, b) => a + b);
    final devices = app.store.usageByDevice(from, to);
    final isToday = _date == today();

    final hours = _week ? const <int>[] : app.store.usageByHour(_date);
    final bars = _week
        ? [for (var i = 0; i < 7; i++) (prettyDate(addDays(from, i)).substring(0, 3), days[addDays(from, i)] ?? 0)]
        : [for (var h = 0; h < 24; h++) (h % 6 == 0 ? '$h' : '', hours[h])];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_access == false) ...[
          Card(
            color: AppColors.cream,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text('Allow usage access',
                      style: text.titleMedium?.copyWith(color: AppColors.onLight, fontWeight: FontWeight.w800)),
                  Text(
                    'Android only tells an app how long other apps were used once you allow it. '
                    'Turn on "G.ONE" in the list that opens; nothing leaves your own sync server.',
                    style: text.bodyMedium?.copyWith(color: AppColors.onLight),
                  ),
                  FilledButton(onPressed: openUsageSettings, child: const Text('Open settings')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            IconButton(
              tooltip: 'Earlier',
              onPressed: () => setState(() => _date = addDays(_date, _week ? -7 : -1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _week ? '${prettyDate(from)} – ${prettyDate(to)}' : isToday ? 'Today' : prettyDate(_date),
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Later',
              onPressed: isToday ? null : () => setState(() => _date = _later()),
              icon: const Icon(Icons.chevron_right),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Day')),
                ButtonSegment(value: true, label: Text('Week')),
              ],
              selected: {_week},
              onSelectionChanged: (v) => setState(() => _week = v.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Text(
                  total == 0 ? 'No screen time' : formatDuration(total),
                  style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1),
                ),
                if (_week && total > 0)
                  Text('${formatDuration(total ~/ 7)} a day on average',
                      style: text.bodySmall?.copyWith(color: AppColors.muted)),
                if (devices.isNotEmpty)
                  Row(
                    spacing: 8,
                    children: [
                      for (final e in devices.entries)
                        Expanded(child: StatTile(formatDuration(e.value), e.key)),
                    ],
                  ),
                _Bars(bars),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (apps.isEmpty && _access != false)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              collectsUsage
                  ? 'Nothing recorded yet. Use the phone for a bit and come back.'
                  : 'Nothing recorded yet. The top-bar extension records the laptop; '
                      'log out and back in once if it was just updated.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ),
        for (final a in apps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(formatDuration(a.seconds), style: text.labelLarge?.copyWith(color: AppColors.muted)),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: a.seconds / apps.first.seconds,
                    minHeight: 8,
                    color: AppColors.lavender,
                    backgroundColor: AppColors.raised,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Vertical bars with a short label under some of them.
class _Bars extends StatelessWidget {
  const _Bars(this.bars);

  final List<(String, int)> bars;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted);
    final peak = bars.fold(1, (m, b) => b.$2 > m ? b.$2 : m);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 3,
        children: [
          for (final (name, secs) in bars)
            Expanded(
              child: Tooltip(
                message: formatDuration(secs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: secs == 0 ? 3 : 80 * secs / peak + 3,
                      decoration: BoxDecoration(
                        color: secs == 0 ? AppColors.raised : AppColors.lavender,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(height: 12, child: OverflowBox(maxWidth: 40, child: Text(name, style: label))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
