import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_core/vault_core.dart';

import 'collect.dart';
import 'screenshots.dart' show monthNames;
import 'state.dart';
import 'theme.dart';

/// Where the money went this month, read from bank and UPI messages.
class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

const categoryIcons = {
  Categories.food: Icons.restaurant_rounded,
  Categories.groceries: Icons.local_grocery_store_rounded,
  Categories.transport: Icons.directions_car_rounded,
  Categories.shopping: Icons.shopping_bag_rounded,
  Categories.bills: Icons.receipt_long_rounded,
  Categories.subscriptions: Icons.autorenew_rounded,
  Categories.health: Icons.favorite_rounded,
  Categories.fun: Icons.celebration_rounded,
  Categories.education: Icons.school_rounded,
  Categories.people: Icons.people_alt_rounded,
  Categories.transfers: Icons.swap_horiz_rounded,
  Categories.own: Icons.sync_alt_rounded,
  Categories.other: Icons.more_horiz_rounded,
};

class _MoneyPageState extends State<MoneyPage> {
  String _month = today().substring(0, 7);
  bool? _access;
  bool _reading = false;

  /// The list shows money spent, or with this, money received.
  bool _received = false;

  @override
  void initState() {
    super.initState();
    hasSmsAccess().then((a) {
      if (mounted) setState(() => _access = a);
      if (a) _read();
    });
  }

  Future<void> _read() async {
    setState(() => _reading = true);
    final app = AppScope.of(context);
    try {
      await collectSms(app.store);
      app.change((_) {});
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _shift(int months) {
    final d = DateTime.parse('$_month-01');
    final next = DateTime(d.year, d.month + months);
    setState(() => _month = '${next.year}-${next.month.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final s = app.store.moneySummary(_month);
    final recurring = _month == today().substring(0, 7) ? app.store.recurring() : const <Recurring>[];
    final d = DateTime.parse('$_month-01');
    final isNow = _month == today().substring(0, 7);

    final byDay = <String, List<Expense>>{};
    // Money moved between your own accounts is neither spent nor received.
    for (final e in s.counted.where((e) => e.spent != _received)) {
      byDay.putIfAbsent(e.date, () => []).add(e);
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _read,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            children: [
              if (_access == false)
                Card(
                  color: AppColors.raised,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text('Track spending without typing', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          'G.ONE reads bank and UPI messages on this phone and keeps only the amount, who was paid '
                          'and the account. The messages never leave the phone.',
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final ok = await requestSmsAccess();
                            setState(() => _access = ok);
                            if (ok) _read();
                          },
                          child: const Text('Allow messages'),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: Text(
                      '${monthNames[d.month - 1]} ${d.year}',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(onPressed: isNow ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                ],
              ),
              _Total(summary: s, onBudget: () => _setBudget(context)),
              if (_reading) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
              if (s.byCategory.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      spacing: 10,
                      children: [
                        for (final (c, v) in s.byCategory)
                          _Bar(
                            icon: categoryIcons[c] ?? Icons.more_horiz_rounded,
                            label: c,
                            value: rupees(v),
                            fraction: v / s.byCategory.first.$2,
                          ),
                      ],
                    ),
                  ),
                ),
              if (recurring.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Every month', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      for (final r in recurring.take(8))
                        ListTile(
                          dense: true,
                          leading: Icon(categoryIcons[r.category], color: AppColors.lavender),
                          title: Text(r.merchant),
                          trailing: Text(rupees(r.amount), style: t.labelLarge),
                        ),
                    ],
                  ),
                ),
              ],
              if (s.topMerchants.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Where it went', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      for (final (m, v) in s.topMerchants.take(5))
                        ListTile(
                          dense: true,
                          title: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(rupees(v), style: t.labelLarge),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (s.counted.isNotEmpty)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Spent')),
                    ButtonSegment(value: true, label: Text('Received')),
                  ],
                  selected: {_received},
                  onSelectionChanged: (v) => setState(() => _received = v.first),
                ),
              if (s.ownTransfers > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${s.ownTransfers} transfers between your own accounts left out',
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ),
              if (s.counted.isEmpty && _access == true)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No payments this month yet.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                ),
              for (final MapEntry(key: date, value: list) in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(prettyDate(date), style: t.labelLarge?.copyWith(color: AppColors.muted)),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final e in list)
                        ListTile(
                          key: ValueKey('expense-${e.id}'),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.raised,
                            child: Icon(categoryIcons[e.category] ?? Icons.more_horiz_rounded, color: AppColors.ink, size: 20),
                          ),
                          title: Text(
                            e.merchant ?? e.note ?? (e.spent ? 'Card payment' : 'Money in'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [e.category, ?e.account, '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}'].join(' · '),
                            style: t.bodySmall?.copyWith(color: AppColors.muted),
                          ),
                          trailing: Text(
                            '${e.spent ? '−' : '+'}${rupees(e.amount)}',
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: e.spent ? AppColors.ink : AppColors.green,
                            ),
                          ),
                          onTap: () => _edit(context, e),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-cash',
            onPressed: () => _addCash(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Cash'),
          ),
        ),
      ],
    );
  }

  Future<void> _setBudget(BuildContext context) async {
    final app = AppScope.of(context);
    final current = app.store.moneyBudget;
    final text = TextEditingController(text: current == null ? '' : '${current ~/ 100}');
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Leave empty for none'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, text.text), child: const Text('Save')),
        ],
      ),
    );
    if (value == null) return;
    final rupeesIn = int.tryParse(value);
    app.change((s) => s.moneyBudget = rupeesIn == null || rupeesIn <= 0 ? null : rupeesIn * 100);
  }

  Future<void> _addCash(BuildContext context) async {
    final app = AppScope.of(context);
    final amount = TextEditingController(), what = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Paid in cash'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'),
            ),
            TextField(controller: what, decoration: const InputDecoration(hintText: 'For what (chai, auto…)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Add')),
        ],
      ),
    );
    final value = double.tryParse(amount.text.replaceAll(',', ''));
    if (ok != true || value == null || value <= 0) return;
    app.change((s) => s.addExpense(amount: (value * 100).round(), merchant: what.text.trim().isEmpty ? null : what.text.trim()));
  }

  Future<void> _edit(BuildContext context, Expense e) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final t = Theme.of(sheet).textTheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text('${e.spent ? '' : '+'}${rupees(e.amount)}', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            Text(
              [?e.merchant, ?e.account, prettyDate(e.date)].join(' · '),
              style: t.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            Text('Category (later payments here follow)', style: t.labelLarge),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Categories.all)
                  ChoiceChip(
                    avatar: Icon(categoryIcons[c], size: 16),
                    label: Text(c),
                    selected: c == e.category,
                    onSelected: (_) {
                      AppScope.of(context).change((s) => s.setExpenseCategory(e.id, c));
                      Navigator.pop(sheet);
                    },
                  ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.block_rounded),
              label: const Text('Not an expense (own transfer, misread)'),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: () {
                AppScope.of(context).change((s) => s.deleteExpense(e.id));
                Navigator.pop(sheet);
              },
            ),
          ],
        ),
      );
    },
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.summary, required this.onBudget});

  final MoneySummary summary;
  final VoidCallback onBudget;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final budget = summary.budget;
    final used = budget == null || budget == 0 ? null : summary.spent / budget;
    return Card(
      color: AppColors.cream,
      child: InkWell(
        onTap: onBudget,
        borderRadius: BorderRadius.circular(cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text('Spent', style: t.labelLarge?.copyWith(color: AppColors.onLight)),
              Text(
                rupees(summary.spent),
                style: t.displaySmall?.copyWith(color: AppColors.onLight, fontWeight: FontWeight.w900),
              ),
              if (used != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: used.clamp(0, 1),
                    minHeight: 8,
                    color: used > 1 ? AppColors.red : (used > 0.8 ? AppColors.orange : AppColors.onLight),
                    backgroundColor: AppColors.onLight.withValues(alpha: 0.12),
                  ),
                ),
                Text(
                  used > 1
                      ? '${rupees(summary.spent - budget!)} over the ${rupees(budget)} budget'
                      : '${rupees(budget! - summary.spent)} left of ${rupees(budget)}',
                  style: t.bodySmall?.copyWith(color: AppColors.onLight),
                ),
              ] else
                Text('Tap to set a monthly budget', style: t.bodySmall?.copyWith(color: AppColors.onLight)),
              if (summary.received > 0)
                Text('Received ${rupees(summary.received)}', style: t.bodySmall?.copyWith(color: AppColors.onLight)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.icon, required this.label, required this.value, required this.fraction});

  final IconData icon;
  final String label, value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      spacing: 10,
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        SizedBox(width: 92, child: Text(label, style: t.bodySmall, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.02, 1),
              minHeight: 10,
              color: AppColors.orange,
              backgroundColor: AppColors.raised,
            ),
          ),
        ),
        SizedBox(width: 78, child: Text(value, textAlign: TextAlign.right, style: t.labelMedium)),
      ],
    );
  }
}
