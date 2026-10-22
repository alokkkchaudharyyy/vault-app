import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'brain_icon.dart';
import 'diary_page.dart';
import 'markdown_view.dart';
import 'state.dart';
import 'theme.dart';

/// Your second brain, as far as the phone sees it: this morning's page, your
/// goals, this week and your projects. The notes themselves
/// live in the vault on the laptop; it publishes these on every sync.
class BrainPage extends StatelessWidget {
  const BrainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final store = app.store;
    final morning = store.page('morning');
    final weekly = store.page('weekly');
    final goals = store.page('goals')?.body.split('\n').where((g) => g.trim().isNotEmpty).toList() ?? const [];
    final projects = _projects(store.page('projects'));
    final nothing = morning == null && weekly == null && goals.isEmpty && projects.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        if (nothing) const _ConnectCard(),
        if (morning != null)
          _PageCard(
            key: const ValueKey('brain-morning'),
            label: morning.key == today() ? 'This morning' : 'Morning page, ${prettyDate(morning.key)}',
            page: morning,
            color: AppColors.cream,
          ),
        if (goals.isNotEmpty) ...[
          const _Heading('Goals'),
          Card(
            key: const ValueKey('brain-goals'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in goals)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.flag_rounded, size: 18, color: AppColors.orange),
                          ),
                          Expanded(child: Text(_withoutDate(g), style: Theme.of(context).textTheme.bodyLarge)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (weekly != null) ...[
          const _Heading('This week'),
          _PageCard(key: const ValueKey('brain-weekly'), label: weekly.title ?? weekly.key, page: weekly),
        ],
        if (projects.isNotEmpty) ...[
          _Heading('Projects', trailing: '${projects.length}'),
          for (final p in projects) ...[_ProjectTile(p), const SizedBox(height: 8)],
        ],
        if (store.pages('morning').length > 1) ...[
          const _Heading('Earlier mornings'),
          for (final m in store.pages('morning').skip(1))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(prettyDate(m.key)),
              subtitle: Text(m.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: () => openPage(context, m),
            ),
        ],
      ],
    );
  }
}

String _withoutDate(String goal) => goal.replaceFirst(RegExp(r'\s*\(\d{4}-\d{2}-\d{2}\)\.?$'), '');

List<Map<String, Object?>> _projects(VaultPage? page) {
  if (page == null) return const [];
  try {
    return (jsonDecode(page.body) as List).cast<Map<String, Object?>>();
  } on FormatException {
    return const [];
  }
}

/// Opens a page from the vault full screen.
Future<void> openPage(BuildContext context, VaultPage page) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(page.title ?? page.key)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: _Answerable(page.body),
                ),
              ),
            ),
          ),
        ),
      ),
    );

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) Text(trailing!, style: t.labelLarge?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// A morning or weekly page, shown in short; tap for all of it.
class _PageCard extends StatelessWidget {
  const _PageCard({super.key, required this.label, required this.page, this.color});

  final String label;
  final VaultPage page;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final light = color == AppColors.cream;
    final body = Theme(
      data: Theme.of(context).copyWith(
        textTheme: light ? t.apply(bodyColor: AppColors.onLight, displayColor: AppColors.onLight) : t,
      ),
      child: MarkdownView(firstSection(page.body), maxBlocks: 8),
    );
    return Material(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPage(context, page),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: t.labelLarge?.copyWith(
                        color: light ? AppColors.onLight.withValues(alpha: 0.65) : AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Read all',
                    style: t.labelLarge?.copyWith(color: light ? AppColors.onLight : AppColors.orange),
                  ),
                ],
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's first section after its title: for a morning page, the day.
String firstSection(String body) {
  final lines = body.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## '));
  if (start < 0) return lines.where((l) => !l.startsWith('# ')).join('\n');
  final end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile(this.project);

  final Map<String, Object?> project;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = project['name'] as String? ?? '';
    final status = project['status'] as String?;
    final what = project['what'] as String?;
    final color = switch (status) {
      'building' => AppColors.orange,
      'role' => AppColors.lavender,
      'paused' => AppColors.muted,
      _ => AppColors.green,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheet) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, scroll) => SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: MarkdownView(project['overview'] as String? ?? '# $name'),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            spacing: 12,
            children: [
              Container(width: 4, height: 40, decoration: ShapeDecoration(color: color, shape: const StadiumBorder())),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (what != null && what.isNotEmpty)
                      Text(
                        what,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: ShapeDecoration(color: color.withValues(alpha: 0.18), shape: const StadiumBorder()),
                  child: Text(status, style: t.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown until the laptop has published anything: how to connect the notes.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('brain-connect'),
      color: AppColors.lavender.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const BrainIcon(color: AppColors.lavender, size: 34),
            Text('Your second brain shows up here', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              'Your notes live in a vault on your laptop: you, your goals, projects, people, what you learned. '
              'Every night your agent files your diary into it and writes a morning page with the day\'s plan. '
              'This phone shows those pages, your goals and your projects after each sync.',
              style: t.bodyMedium?.copyWith(height: 1.4),
            ),
            Text('On your laptop:', style: t.labelLarge?.copyWith(color: AppColors.muted)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(12)),
              child: const Text('myvault init\nmyvault sync', style: TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sections of a morning or weekly page that ask you something.
final _asks = RegExp(r'^##\s+(open questions|waiting for (your|my) yes)', caseSensitive: false);

/// A page, with a + beside each section that asks you something: pick the
/// item and answer it, and the answer goes into the diary with the question.
class _Answerable extends StatelessWidget {
  const _Answerable(this.body);

  final String body;

  @override
  Widget build(BuildContext context) {
    // Split at the section headings, keeping each heading with its section.
    final sections = <List<String>>[[]];
    for (final line in body.split('\n')) {
      if (line.startsWith('## ')) sections.add([]);
      sections.last.add(line);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lines in sections)
          if (lines.isNotEmpty && _asks.hasMatch(lines.first))
            _AskSection(heading: lines.first.substring(3).trim(), lines: lines.skip(1).toList())
          else if (lines.any((l) => l.trim().isNotEmpty))
            MarkdownView(lines.join('\n')),
      ],
    );
  }
}

class _AskSection extends StatelessWidget {
  const _AskSection({required this.heading, required this.lines});

  final String heading;
  final List<String> lines;

  /// The section's items, as plain text.
  List<String> get items => [
    for (final l in lines)
      if (RegExp(r'^\s*([-*]|\d+\.)\s+').hasMatch(l))
        l.replaceFirst(RegExp(r'^\s*([-*]|\d+\.)\s+'), '').replaceAll('**', '').replaceAll('`', '').trim(),
  ];

  Future<void> _answer(BuildContext context) async {
    final options = items;
    var question = options.length == 1 ? options.first : null;
    if (options.isEmpty) question = heading;
    question ??= await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Which one are you answering?',
                  style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final (i, o) in options.indexed)
                Card(
                  child: ListTile(
                    key: ValueKey('answer-item-$i'),
                    title: Text(o),
                    trailing: const Icon(Icons.reply_rounded, color: AppColors.orange),
                    onTap: () => Navigator.pop(sheet, o),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (question == null || !context.mounted) return;
    await showQuickLog(context, replyTo: question);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Expanded(child: Text(heading, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              IconButton.filledTonal(
                key: ValueKey<String>('answer-${heading.toLowerCase()}'),
                tooltip: 'Answer',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _answer(context),
              ),
            ],
          ),
        ),
        MarkdownView(lines.join('\n')),
      ],
    );
  }
}
