import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:vault_cli/brain.dart';
import 'package:vault_cli/embedded.g.dart';
import 'package:vault_cli/mcp.dart';
import 'package:vault_cli/setup.dart';
import 'package:vault_cli/vault.dart';
import 'package:vault_cli/vault_lint.dart';
import 'package:vault_core/vault_core.dart';

final Store store = Store(openDb());

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'myvault',
          'Vault: a private second brain that your agents share. Plan your goals and days; keep your memory.',
        )
        ..argParser.addFlag('json', negatable: false, help: 'Print JSON instead of text.')
        ..addCommand(InitCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(CaptureCommand())
        ..addCommand(SearchCommand())
        ..addCommand(
          PageCommand(
            'morning',
            'morning',
            'Today\'s morning page, written overnight: myvault morning [DATE]',
          ),
        )
        ..addCommand(PageCommand('week', 'weekly', 'The latest weekly look back: myvault week'))
        ..addCommand(GoalsCommand())
        ..addCommand(ProjectCommand())
        ..addCommand(NoteCommand())
        ..addCommand(RoutineCommand())
        ..addCommand(AddCommand())
        ..addCommand(ListCommand())
        ..addCommand(TodayCommand())
        ..addCommand(DoneCommand('done', 'Tick tasks.', true))
        ..addCommand(DoneCommand('undo', 'Untick tasks.', false))
        ..addCommand(EditCommand())
        ..addCommand(RmCommand())
        ..addCommand(ListsCommand())
        ..addCommand(HabitCommand())
        ..addCommand(FocusCommand())
        ..addCommand(UsageCommand())
        ..addCommand(MoneyCommand())
        ..addCommand(HealthCommand())
        ..addCommand(VaultCommand())
        ..addCommand(ShowCommand())
        ..addCommand(StatsCommand())
        ..addCommand(CheckPlanCommand())
        ..addCommand(DiaryCommand())
        ..addCommand(DiaryCommand('brief'))
        ..addCommand(_DiaryRm())
        ..addCommand(_DiaryFiled())
        ..addCommand(_DiaryOutcome())
        ..addCommand(_UsageAdd())
        ..addCommand(SchemaCommand())
        ..addCommand(ServerCommand())
        ..addCommand(LoginCommand())
        ..addCommand(LogoutCommand())
        ..addCommand(SyncCommand())
        ..addCommand(McpCommand());
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
  } on TodoException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on SyncException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on SocketException {
    stderr.writeln('Offline: could not reach the sync server. Local changes are kept.');
    exitCode = 1;
  } on http.ClientException {
    stderr.writeln('Offline: could not reach the sync server. Local changes are kept.');
    exitCode = 1;
  }
}

abstract class Cmd extends Command<void> {
  Cmd(this.name, this.description);

  @override
  final String name;
  @override
  final String description;

  List<String> get rest => argResults!.rest;
  String? opt(String name) => argResults!.option(name);

  /// Prints [data] as JSON under `--json`, otherwise the lines from [text].
  void out(Object? data, String Function() text) =>
      print(globalResults!.flag('json') ? jsonEncode(data) : text());

  void needArgs(String what) {
    if (rest.isEmpty) usageException('Give $what.');
  }
}

String short(String id) => id.substring(0, 6);

String taskLine(Task t, {bool showDate = true}) {
  final time = t.startTime == null
      ? ''
      : t.endTime == null
      ? '${t.startTime} '
      : '${t.startTime}–${t.endTime} ';
  final date = showDate && t.date != null ? '${prettyDate(t.date!)} ' : '';
  final tag = t.tag == null ? '' : '  #${t.tag}';
  final list = t.list == null ? '' : '  (${t.list})';
  final due = t.dueDate == null ? '' : '  due ${prettyDate(t.dueDate!)}';
  final protect = switch (t.protect) {
    Task.protectDay => '  [protected]',
    Task.protectTime => '  [fixed time]',
    _ => '',
  };
  return '${t.done ? '[x]' : '[ ]'} ${short(t.id)}  $date$time${t.title}$tag$list$due$protect';
}

String taskLines(List<Task> tasks, {bool showDate = true}) =>
    tasks.isEmpty ? 'No tasks.' : tasks.map((t) => taskLine(t, showDate: showDate)).join('\n');

String focusLine(FocusSession? s) {
  if (s == null) return 'No focus session running.';
  final left = s.plannedEnd.difference(DateTime.now());
  final on = s.taskTitle == null ? '' : ' on "${s.taskTitle}"';
  return '${s.kind == 'break' ? 'Break' : 'Focus'}$on: '
      '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')} left of ${s.plannedMin} min';
}

void addTaskOptions(Cmd c) {
  c.argParser
    ..addOption('date', abbr: 'd', help: 'today, tomorrow, fri, +3 or 2026-10-12.')
    ..addOption('time', abbr: 't', help: '17:30 or 17:30-18:15.')
    ..addOption('list', abbr: 'l', help: 'List name (created if new).')
    ..addOption('tag', help: 'Short label.')
    ..addOption('notes', abbr: 'n')
    ..addOption('due', help: 'Deadline: when it must be done by. Not the day it is planned for (-d).')
    ..addOption('estimate', help: 'Minutes it should take, for a task without a time slot.')
    ..addOption(
      'protect',
      allowed: ['day', 'time', 'none'],
      help: 'day: must stay on its day, may move within it. time: fixed in time. none: free to move.',
    )
    ..addOption('from', help: 'The diary entry this commitment was captured from (id or prefix).');
}

/// The commitment fields of [c]'s options, as store columns. "none" clears.
Map<String, Object?> commitmentOptions(Cmd c) {
  String? opt(String name) => c.argResults!.option(name);
  bool clear(String v) => v.toLowerCase() == 'none';
  return {
    if (opt('due') != null) 'due_date': clear(opt('due')!) ? null : parseDate(opt('due')!),
    if (opt('estimate') != null)
      'estimate_min': clear(opt('estimate')!)
          ? null
          : int.tryParse(opt('estimate')!) ?? (throw TodoException('The estimate is a number of minutes')),
    if (opt('protect') != null) 'protect': clear(opt('protect')!) ? null : opt('protect'),
    if (opt('from') != null)
      'source_entry': clear(opt('from')!) ? null : store.resolveId('diary', opt('from')!),
  };
}

class AddCommand extends Cmd {
  AddCommand() : super('add', 'Add a task: myvault add Buy milk -d tomorrow -t 18:00') {
    addTaskOptions(this);
  }

  @override
  void run() {
    needArgs('a title');
    final time = opt('time') == null ? null : parseTimeRange(opt('time')!);
    // A time without a date means today.
    final date = opt('date') != null
        ? parseDate(opt('date')!)
        : time != null
        ? today()
        : null;
    final more = commitmentOptions(this);
    final t = store.addTask(
      title: rest.join(' '),
      listId: opt('list') == null ? null : store.ensureList(opt('list')!).id,
      date: date,
      startTime: time?.$1,
      endTime: time?.$2,
      tag: opt('tag'),
      notes: opt('notes'),
      dueDate: more['due_date'] as String?,
      estimateMin: more['estimate_min'] as int?,
      protect: more['protect'] as String?,
      sourceEntry: more['source_entry'] as String?,
    );
    out(t.toJson(), () => 'Added ${taskLine(t)}');
  }
}

class ListCommand extends Cmd {
  ListCommand()
    : super('list', 'List tasks: myvault list [today|tomorrow|week|overdue|backlog|due|all|undated|DATE]') {
    argParser
      ..addOption('list', abbr: 'l', help: 'Only this list.')
      ..addFlag('open', negatable: false, help: 'Hide ticked tasks.');
  }

  @override
  List<String> get aliases => ['ls'];

  @override
  void run() {
    final when = rest.isEmpty ? 'today' : rest.first.toLowerCase();
    String? listId;
    if (opt('list') != null) {
      final l = store.findList(opt('list')!);
      if (l == null) throw TodoException('No list called "${opt('list')}"');
      listId = l.id;
    }
    final includeDone = !argResults!.flag('open');
    final now = today();
    final tasks = switch (when) {
      'all' => store.tasks(undated: true, listId: listId, includeDone: includeDone),
      'undated' =>
        store
            .tasks(undated: true, listId: listId, includeDone: includeDone)
            .where((t) => t.date == null)
            .toList(),
      'overdue' => store.tasks(overdueBefore: now, listId: listId),
      // Open commitments with no day yet.
      'backlog' =>
        store.tasks(undated: true, listId: listId, includeDone: false).where((t) => t.date == null).toList(),
      // Open tasks with a deadline, soonest first.
      'due' =>
        store
            .tasks(undated: true, listId: listId, includeDone: false)
            .where((t) => t.dueDate != null)
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!)),
      'week' => store.tasks(from: now, to: addDays(now, 6), listId: listId, includeDone: includeDone),
      _ => store.tasks(from: parseDate(when), to: parseDate(when), listId: listId, includeDone: includeDone),
    };
    out([for (final t in tasks) t.toJson()], () => taskLines(tasks));
  }
}

class TodayCommand extends Cmd {
  TodayCommand() : super('today', 'Tasks, habits and focus for today (or a given date).');

  @override
  void run() {
    final date = rest.isEmpty ? today() : parseDate(rest.first);
    final snap = store.snapshot(date);
    out(snap, () {
      final items = (snap['items'] as List).cast<Map<String, Object?>>();
      final done = items.where((i) => i['done'] == true).length;
      return [
        '${prettyDate(date)}: $done of ${items.length} done'
            '${snap['overdue'] == 0 ? '' : ', ${snap['overdue']} overdue'}',
        if (items.isEmpty) 'Nothing today.',
        for (final i in items)
          '${i['done'] == true ? '[x]' : '[ ]'} ${short(i['id'] as String)}  '
              '${(i['time'] as String? ?? '').padRight(5)}  ${i['title']}'
              '${i['kind'] == 'habit' ? '  (habit)' : ''}',
        '',
        '${focusLine(store.currentFocus())} ${snap['focused_min']} min focused today.',
      ].join('\n');
    });
  }
}

class DoneCommand extends Cmd {
  DoneCommand(super.name, super.description, this.done);

  final bool done;

  @override
  void run() {
    needArgs('one or more task ids');
    final ids = [for (final ref in rest) store.resolveId('tasks', ref)];
    final tasks = [for (final id in ids) store.setDone(id, done)];
    out([for (final t in tasks) t.toJson()], () => taskLines(tasks));
  }
}

class EditCommand extends Cmd {
  EditCommand()
    : super(
        'edit',
        'Change a task: myvault edit ID -d fri -t 10:00. Use "none" to clear a field. Moving a protected task '
            'off its day, a fixed one at all, or changing a deadline needs --reason.',
      ) {
    argParser
      ..addOption('title')
      ..addOption('reason', help: 'Why: kept in the task history.');
    addTaskOptions(this);
  }

  @override
  void run() {
    needArgs('a task id');
    final id = store.resolveId('tasks', rest.first);
    String? clearable(String v) => v.toLowerCase() == 'none' ? null : v;
    final changes = <String, Object?>{};
    if (opt('title') != null) changes['title'] = opt('title');
    if (opt('date') != null) {
      final v = clearable(opt('date')!);
      changes['date'] = v == null ? null : parseDate(v);
    }
    if (opt('time') != null) {
      final v = clearable(opt('time')!);
      final range = v == null ? null : parseTimeRange(v);
      changes['start_time'] = range?.$1;
      changes['end_time'] = range?.$2;
    }
    if (opt('list') != null) {
      final v = clearable(opt('list')!);
      changes['list_id'] = v == null ? null : store.ensureList(v).id;
    }
    if (opt('tag') != null) changes['tag'] = clearable(opt('tag')!);
    if (opt('notes') != null) changes['notes'] = clearable(opt('notes')!);
    changes.addAll(commitmentOptions(this));
    if (changes.isEmpty) usageException('Nothing to change.');
    // The command line is how an assistant changes tasks unattended, so the
    // rules that keep protected work and deadlines from slipping apply here.
    final t = store.updateTask(id, changes, reason: opt('reason'), guarded: true);
    out(t.toJson(), () => taskLine(t));
  }
}

class RmCommand extends Cmd {
  RmCommand() : super('rm', 'Delete tasks.');

  @override
  void run() {
    needArgs('one or more task ids');
    final ids = [for (final ref in rest) store.resolveId('tasks', ref)];
    final tasks = [for (final id in ids) store.task(id)];
    ids.forEach(store.deleteTask);
    out({'deleted': ids}, () => tasks.map((t) => 'Deleted ${short(t.id)}  ${t.title}').join('\n'));
  }
}

class ListsCommand extends Cmd {
  ListsCommand()
    : super('lists', 'Show lists; add one: myvault lists add NAME; rename: myvault lists rename OLD NEW');

  @override
  void run() {
    if (rest.length >= 2 && rest.first == 'add') store.ensureList(rest.skip(1).join(' '));
    if (rest.length == 3 && rest.first == 'rename') {
      final list = store.findList(rest[1]);
      if (list == null) throw TodoException('No list called "${rest[1]}"');
      store.renameList(list.id, rest[2]);
    }
    final lists = store.lists();
    out([
      for (final l in lists) l.toJson(),
    ], () => lists.isEmpty ? 'No lists.' : lists.map((l) => '${short(l.id)}  ${l.title}').join('\n'));
  }
}

class HabitCommand extends Cmd {
  HabitCommand() : super('habit', 'Daily habits.') {
    addSubcommand(_HabitList());
    addSubcommand(_HabitAdd());
    addSubcommand(_HabitCheck('check', 'Tick habits for a day: myvault habit check ID... [-d DATE]', true));
    addSubcommand(_HabitCheck('uncheck', 'Untick habits for a day.', false));
    addSubcommand(_HabitTime());
    addSubcommand(_HabitRm());
  }

  @override
  void run() => _HabitList.show(this, today());
}

class _HabitList extends Cmd {
  _HabitList() : super('list', 'Habits for today or a given date.');

  static void show(Cmd c, String date) {
    final habits = store.habits(activeOn: date);
    final checked = store.checkedHabitIds(date);
    c.out(
      [
        for (final h in habits) {...h.toJson(), 'date': date, 'done': checked.contains(h.id)},
      ],
      () => habits.isEmpty
          ? 'No habits on ${prettyDate(date)}.'
          : habits
                .map(
                  (h) =>
                      '${checked.contains(h.id) ? '[x]' : '[ ]'} ${short(h.id)}  '
                      '${h.time == null ? '' : '${h.time} '}${h.title}',
                )
                .join('\n'),
    );
  }

  @override
  void run() => show(this, rest.isEmpty ? today() : parseDate(rest.first));
}

class _HabitAdd extends Cmd {
  _HabitAdd() : super('add', 'Add a habit: myvault habit add Read 20 min --from today --to 2026-12-29') {
    argParser
      ..addOption('time', abbr: 't', help: 'Time of day it sits at in the timeline, e.g. 07:00.')
      ..addOption('from', help: 'First day (default: no start).')
      ..addOption('to', help: 'Last day (default: no end).');
  }

  @override
  void run() {
    needArgs('a title');
    final h = store.addHabit(
      title: rest.join(' '),
      time: opt('time') == null ? null : parseTimeRange(opt('time')!).$1,
      startDate: opt('from') == null ? null : parseDate(opt('from')!),
      endDate: opt('to') == null ? null : parseDate(opt('to')!),
    );
    out(h.toJson(), () => 'Added habit ${short(h.id)}  ${h.title}');
  }
}

class _HabitCheck extends Cmd {
  _HabitCheck(super.name, super.description, this.done) {
    argParser.addOption('date', abbr: 'd', help: 'Day to mark (default today).');
  }

  final bool done;

  @override
  void run() {
    needArgs('one or more habit ids or exact titles');
    final date = opt('date') == null ? today() : parseDate(opt('date')!);
    for (final ref in rest) {
      store.setHabitCheck(store.resolveHabit(ref), date, done);
    }
    _HabitList.show(this, date);
  }
}

class _HabitTime extends Cmd {
  _HabitTime() : super('time', 'Set a habit\'s time of day: myvault habit time ID 07:00 (or "none").');

  @override
  void run() {
    if (rest.length != 2) usageException('Give a habit id or exact title, then a time or "none".');
    final time = rest[1].toLowerCase() == 'none' ? null : parseTimeRange(rest[1]).$1;
    store.setHabitTime(store.resolveHabit(rest[0]), time);
    _HabitList.show(this, today());
  }
}

class _HabitRm extends Cmd {
  _HabitRm() : super('rm', 'Delete habits.');

  @override
  void run() {
    needArgs('one or more habit ids');
    final ids = [for (final ref in rest) store.resolveHabit(ref)];
    ids.forEach(store.deleteHabit);
    out({'deleted': ids}, () => 'Deleted ${ids.length} habit${ids.length == 1 ? '' : 's'}.');
  }
}

class FocusCommand extends Cmd {
  FocusCommand() : super('focus', 'Focus timer.') {
    addSubcommand(_FocusStart());
    addSubcommand(_FocusStop());
    addSubcommand(_FocusStatus());
  }

  @override
  void run() => _FocusStatus.show(this);
}

class _FocusStart extends Cmd {
  _FocusStart() : super('start', 'Start a session: myvault focus start [TASK_ID] [-m 25] [--break]') {
    argParser
      ..addOption('minutes', abbr: 'm', help: 'Length (default 25, or 5 for a break).')
      ..addFlag('break', negatable: false, help: 'A break instead of a focus session.');
  }

  @override
  void run() {
    final isBreak = argResults!.flag('break');
    final minutes = int.tryParse(opt('minutes') ?? (isBreak ? '5' : '25'));
    if (minutes == null) usageException('Minutes must be a number.');
    final s = store.startFocus(
      taskId: rest.isEmpty ? null : store.resolveId('tasks', rest.first),
      minutes: minutes,
      kind: isBreak ? 'break' : 'focus',
    );
    out(s.toJson(), () => focusLine(s));
  }
}

class _FocusStop extends Cmd {
  _FocusStop() : super('stop', 'Stop the running session.');

  @override
  void run() {
    final s = store.stopFocus();
    out(
      s?.toJson(),
      () => s == null
          ? 'No focus session running.'
          : 'Stopped after ${s.endedAt!.difference(s.startedAt).inMinutes} min.',
    );
  }
}

class _FocusStatus extends Cmd {
  _FocusStatus() : super('status', 'Show the running session and minutes focused today.');

  static void show(Cmd c) {
    final s = store.currentFocus();
    final minutes = store.focusedMinutes(today());
    c.out({
      'session': s?.toJson(),
      'focused_min': minutes,
    }, () => '${focusLine(s)} $minutes min focused today.');
  }

  @override
  void run() => show(this);
}

/// `myvault diary`: what was written, and a way to write more.
class DiaryCommand extends Cmd {
  DiaryCommand([String name = 'diary'])
    : super(
        name,
        'Diary: myvault diary (recent entries), or myvault diary Finally got hash maps --task 6e495e',
      ) {
    argParser
      ..addOption('date', abbr: 'd', help: 'Day the entry is about (default today).')
      ..addOption('task', help: 'A task the entry is about (id or prefix).')
      ..addOption('habit', help: 'A habit the entry is about (title or id).')
      ..addOption(
        'as',
        allowed: [DiaryEntry.me, DiaryEntry.assistant],
        defaultsTo: DiaryEntry.me,
        help: 'Who is writing.',
      )
      ..addOption('days', defaultsTo: '7', help: 'How many days back to show.')
      ..addFlag('unfiled', negatable: false, help: 'Only your entries not yet filed into the vault.')
      ..addFlag(
        'unprocessed',
        negatable: false,
        help: 'Only your entries of the last 14 days with no recorded outcome yet.',
      );
  }

  // `myvault brief` still works: the nightly routine was written against it.
  @override
  bool get hidden => name != 'diary';

  @override
  void run() {
    final taskId = opt('task') == null ? null : store.resolveId('tasks', opt('task')!);
    final habitId = opt('habit') == null ? null : store.resolveHabit(opt('habit')!);
    if (rest.isNotEmpty) {
      final e = store.addDiary(
        rest.join(' '),
        date: opt('date') == null ? null : parseDate(opt('date')!),
        author: opt('as')!,
        taskId: taskId,
        habitId: habitId,
      );
      out(
        e.toJson(),
        () => 'Saved to the diary for ${prettyDate(e.date)}${e.about == null ? '' : ', on "${e.about}"'}.',
      );
      return;
    }
    if (argResults!.flag('unprocessed')) {
      final waiting = store.unprocessedDiary();
      out([for (final e in waiting) e.toJson()], () {
        if (waiting.isEmpty) return 'Every entry has an outcome.';
        return [
          for (final e in waiting)
            '  ${short(e.id)}  ${prettyDate(e.date)} ${hm(e.createdAt)}  ${e.body.replaceAll('\n', ' ')}',
        ].join('\n');
      });
      return;
    }
    final unfiled = argResults!.flag('unfiled');
    final days = int.tryParse(opt('days')!);
    if (days == null || days < 1) usageException('Days must be a number.');
    final to = opt('date') == null ? today() : parseDate(opt('date')!);
    final entries = store.diary(
      // Unfiled entries are wanted however old they are.
      from: unfiled ? null : addDays(to, -(days - 1)),
      to: to,
      taskId: taskId,
      habitId: habitId,
      author: unfiled ? DiaryEntry.me : null,
      unfiledOnly: unfiled,
    );
    out([for (final e in entries) e.toJson()], () {
      if (entries.isEmpty) return unfiled ? 'Nothing waiting to be filed.' : 'No diary entries.';
      final lines = <String>[];
      String? day;
      for (final e in entries) {
        if (e.date != day) {
          if (day != null) lines.add('');
          lines.add(prettyDate(day = e.date));
        }
        final who = e.author == DiaryEntry.me ? '' : 'Claude: ';
        final about = e.about == null ? '' : '[${e.about}] ';
        lines.add(
          '  ${short(e.id)}  ${hm(e.createdAt)}  $who$about${e.body.replaceAll('\n', '\n                 ')}',
        );
        if (e.outcome != null) lines.add('                 -> ${e.outcome}');
      }
      return lines.join('\n');
    });
  }
}

class _DiaryRm extends Cmd {
  _DiaryRm() : super('diary-rm', 'Delete diary entries: myvault diary-rm ID...');

  @override
  void run() {
    needArgs('at least one entry id');
    final ids = [for (final ref in rest) store.resolveId('diary', ref)];
    for (final id in ids) {
      store.deleteDiary(id);
    }
    out({'deleted': ids}, () => 'Deleted ${ids.length} ${ids.length == 1 ? 'entry' : 'entries'}.');
  }
}

/// Used by an assistant once it has filed entries into the vault.
class _DiaryFiled extends Cmd {
  _DiaryFiled()
    : super('diary-filed', 'Mark diary entries as filed into the vault: myvault diary-filed ID...');

  @override
  bool get hidden => true;

  @override
  void run() {
    needArgs('at least one entry id');
    final ids = [for (final ref in rest) store.resolveId('diary', ref)];
    store.markDiaryFiled(ids);
    out({'filed': ids}, () => 'Marked ${ids.length} as filed.');
  }
}

class _DiaryOutcome extends Cmd {
  _DiaryOutcome()
    : super(
        'diary-outcome',
        'Record what became of a diary entry: myvault diary-outcome ID Captured 3 commitments...',
      );

  @override
  bool get hidden => true;

  @override
  void run() {
    if (rest.length < 2) usageException('Give the entry id and the outcome.');
    final id = store.resolveId('diary', rest.first);
    store.setDiaryOutcome(id, rest.skip(1).join(' '));
    out({'id': id, 'outcome': rest.skip(1).join(' ')}, () => 'Outcome recorded.');
  }
}

class ShowCommand extends Cmd {
  ShowCommand()
    : super('show', 'Everything about one task, with its history and the diary entry it came from.');

  @override
  void run() {
    needArgs('a task id');
    final t = store.task(store.resolveId('tasks', rest.first));
    final source = t.sourceEntry == null
        ? null
        : store.diary().where((e) => e.id == t.sourceEntry).firstOrNull;
    out(
      {...t.toJson(), 'source': source?.toJson()},
      () => [
        taskLine(t),
        if (t.estimateMin != null) '    estimate: ${t.estimateMin} min',
        if (t.notes != null) '    notes: ${t.notes}',
        if (source != null)
          '    from the diary, ${prettyDate(source.date)} ${hm(source.createdAt)}: ${source.body.replaceAll('\n', ' ')}',
        if (t.history != null) ...['    history:', for (final l in t.history!.split('\n')) '      $l'],
      ].join('\n'),
    );
  }
}

class StatsCommand extends Cmd {
  StatsCommand()
    : super('stats', 'What recent days actually looked like: wake times, tasks done, deadlines, backlog.') {
    argParser.addOption('days', defaultsTo: '14', help: 'How many days back.');
  }

  @override
  void run() {
    final days = int.tryParse(opt('days')!);
    if (days == null || days < 1) usageException('Days must be a number.');
    final s = store.stats(days: days);
    out(s.toJson(), () {
      final t = s.toJson()['typical'] as Map<String, Object?>;
      String pct(Object? v) => v == null ? 'no data' : '$v%';
      return [
        'Typical wake: ${t['wake_last_3_days'] ?? 'no data'} (last 3 days), ${t['wake_last_7_days'] ?? 'no data'} (7)',
        'Typical bedtime: ${t['bed_last_3_days'] ?? 'no data'}',
        'Tasks done: ${pct(t['completion'])}; protected ones: ${pct(t['protected_completion'])}; '
            '${t['done_min_per_day'] ?? 0} min of planned work done a day',
        'Backlog: ${s.backlog} without a day. Overdue: ${s.overdue}. Diary entries waiting for an outcome: ${s.unprocessed}',
        if (s.dueSoon.isNotEmpty) 'Due in the next 14 days:',
        for (final d in s.dueSoon)
          '  ${prettyDate(d.dueDate!)}  ${d.title}${d.date == null ? '  (no day planned)' : ''}',
        '',
        for (final d in s.days)
          '${prettyDate(d.date).padRight(11)} woke ${d.wake == null ? '  -  ' : clockText(d.wake!)}  '
              'bed ${d.bed == null ? '  -  ' : clockText(d.bed!)}  done ${d.done}/${d.planned}  focus ${d.focusMin} min',
      ].join('\n');
    });
  }
}

class CheckPlanCommand extends Cmd {
  CheckPlanCommand()
    : super(
        'check-plan',
        'Check a day\'s plan: nothing left in the past, no deadline broken, every diary entry accounted for, '
            'the day no fuller than the time there really is. Exits 1 if anything must be fixed.',
      ) {
    argParser
      ..addOption(
        'wake',
        help: 'When the day starts (HH:MM); default: the typical wake time of the last 3 days.',
      )
      ..addOption('end', help: 'When the day ends (HH:MM); default 22:30.')
      ..addOption('capacity', defaultsTo: '0.75', help: 'Share of the available time that may be planned.');
  }

  @override
  void run() {
    final date = rest.isEmpty ? today() : parseDate(rest.first);
    final capacity = double.tryParse(opt('capacity')!);
    if (capacity == null || capacity <= 0 || capacity > 1) usageException('Capacity is between 0 and 1.');
    final c = store.checkPlan(
      date,
      wake: opt('wake') == null ? null : parseTimeRange(opt('wake')!).$1,
      end: opt('end') == null ? null : parseTimeRange(opt('end')!).$1,
      capacity: capacity,
    );
    out(
      c.toJson(),
      () => [
        '${prettyDate(date)}: from ${clockText(c.start)} to ${clockText(c.end)}, '
            '${c.plannedMin} of ${c.budgetMin} min planned (${(capacity * 100).round()}%).',
        c.ok ? 'The plan holds.' : 'To fix:',
        for (final e in c.errors) '  - ${e.message}',
        if (c.warnings.isNotEmpty) 'To mention:',
        for (final w in c.warnings) '  - ${w.message}',
      ].join('\n'),
    );
    if (!c.ok) exitCode = 1;
  }
}

class VaultCommand extends Cmd {
  VaultCommand()
    : super(
        'notes',
        'Your vault of notes: the memory your diary is filed into and your agents read (opens in Obsidian).',
      ) {
    addSubcommand(_VaultInit());
    addSubcommand(_VaultUse());
    addSubcommand(_VaultStatus());
    addSubcommand(_VaultLint());
    addSubcommand(_NotesSave());
    addSubcommand(_NotesPublish());
    addSubcommand(_NotesLog());
  }

  // Its name before Vault became the product's name.
  @override
  List<String> get aliases => ['vault'];
}

String _vaultLine(Map<String, Object?> s) {
  if (s['path'] == null) return 'No vault on this device. Create one with: myvault notes init';
  if (s['exists'] != true) return 'The vault is set to ${s['path']}, but that folder is missing.';
  final where = s['remote'] == null ? '' : '  (${s['remote']})';
  final waiting = s['unfiled'] as int;
  return 'Vault: ${s['path']}$where\n'
      '${waiting == 0 ? 'Nothing waiting to be filed.' : '$waiting diary ${waiting == 1 ? 'entry' : 'entries'} waiting to be filed.'}';
}

class _VaultStatus extends Cmd {
  _VaultStatus() : super('status', 'Where the vault is and how many diary entries are waiting to be filed.');

  @override
  void run() {
    final s = vaultStatus(store);
    out(s, () => _vaultLine(s));
  }
}

class _VaultLint extends Cmd {
  _VaultLint()
    : super(
        'lint',
        'Check the vault: broken links, links into raw/, notes missing from INDEX.md, unlinked notes, frontmatter, log format.',
      );

  @override
  void run() {
    final path = vaultStatus(store)['path'] as String?;
    if (path == null || !Directory(path).existsSync()) {
      throw TodoException('No vault on this device. Create one with: myvault notes init');
    }
    final issues = lintVault(path);
    final errors = issues.where((i) => i.isError).length;
    out(
      {
        'path': path,
        'errors': errors,
        'warnings': issues.length - errors,
        'issues': [for (final i in issues) i.toJson()],
      },
      () {
        if (issues.isEmpty) return 'The vault is healthy.';
        return [
          if (errors > 0) 'To fix:',
          for (final i in issues.where((i) => i.isError)) '  - ${i.file}: ${i.message}',
          if (issues.length > errors) 'To look at:',
          for (final i in issues.where((i) => !i.isError)) '  - ${i.file}: ${i.message}',
        ].join('\n');
      },
    );
    if (errors > 0) exitCode = 1;
  }
}

class _VaultUse extends Cmd {
  _VaultUse() : super('use', 'Point this device at a vault that already exists: myvault notes use PATH');

  @override
  void run() {
    if (rest.length != 1) usageException('Give the folder of the vault.');
    final path = Directory(rest.first).absolute.path;
    if (!Directory(path).existsSync()) throw TodoException('There is no folder at $path');
    store.setMeta(vaultPathKey, path);
    final s = vaultStatus(store);
    out(s, () => _vaultLine(s));
  }
}

class _VaultInit extends Cmd {
  _VaultInit() : super('init', 'Create a vault: myvault notes init [PATH] [--github [NAME]]') {
    argParser.addOption(
      'github',
      help:
          'Also keep it in a new private GitHub repo with this name, so an assistant in the cloud can file into it.',
    );
  }

  @override
  void run() {
    if (rest.length > 1) usageException('Give at most one folder.');
    final path = Directory(rest.isEmpty ? defaultVaultPath() : rest.first).absolute.path;
    final written = scaffoldVault(path);
    store.setMeta(vaultPathKey, path);

    final notes = <String>[];
    final repo = opt('github');
    if (repo != null) notes.addAll(vaultToGitHub(path, repo));

    out({...vaultStatus(store), 'created': written}, () {
      final lines = [
        written.isEmpty
            ? 'The vault at $path already had every starter note; nothing was changed.'
            : 'Created the vault at $path (${written.where((f) => f.endsWith('.md')).join(', ')}).',
        ...notes,
        'Open that folder as a vault in Obsidian. Start by filling in Me.md.',
      ];
      return lines.join('\n');
    });
  }
}

class UsageCommand extends Cmd {
  UsageCommand() : super('usage', 'Screen time: myvault usage [today|yesterday|week|DATE]');

  @override
  void run() {
    final arg = rest.isEmpty ? 'today' : rest.first;
    final (from, to) = arg == 'week' ? (addDays(today(), -6), today()) : (parseDate(arg), parseDate(arg));
    final s = store.usageSummary(from, to);
    out(s, () {
      final total = s['total_seconds'] as int;
      if (total == 0) return 'No screen time recorded.';
      final lines = [
        '${from == to ? prettyDate(from) : '${prettyDate(from)} – ${prettyDate(to)}'}: ${formatDuration(total)}',
        for (final e in (s['by_device'] as Map<String, int>).entries)
          '  ${e.key}: ${formatDuration(e.value)}',
        '',
      ];
      for (final a in (s['apps'] as List).cast<Map<String, Object?>>().take(15)) {
        lines.add('${formatDuration(a['seconds'] as int).padLeft(7)}  ${a['name']}');
      }
      if (from != to) {
        lines.add('');
        for (final e in (s['by_day'] as Map<String, int>).entries) {
          lines.add('${prettyDate(e.key)}  ${formatDuration(e.value)}');
        }
      } else {
        final hours = s['by_hour'] as List<int>;
        final peak = hours.reduce((a, b) => a > b ? a : b);
        lines.add('');
        for (var h = 0; h < 24; h++) {
          if (hours[h] == 0) continue;
          lines.add(
            '${h.toString().padLeft(2, '0')}:00  ${'█' * (hours[h] * 30 ~/ peak).clamp(1, 30)} ${formatDuration(hours[h])}',
          );
        }
      }
      return lines.join('\n');
    });
  }
}

class MoneyCommand extends Cmd {
  MoneyCommand()
      : super('money',
            'Spending, from bank and UPI messages on the phone: myvault money [YYYY-MM]; add cash: money add 120 chai; '
            'fix one: money set ID Food, money remove ID; your own name on payments: money me "Alok Chaudhary"');

  @override
  void run() {
    if (rest.isNotEmpty && rest.first == 'set') {
      if (rest.length < 3 || !Categories.all.contains(rest.sublist(2).join(' '))) {
        throw UsageException('myvault money set ID CATEGORY, with one of: ${Categories.all.join(', ')}', usage);
      }
      store.setExpenseCategory(rest[1], rest.sublist(2).join(' '));
      final e = store.expense(rest[1])!;
      return out(e.toJson(), () => '${e.merchant ?? rupees(e.amount)} is now ${e.category}.');
    }
    if (rest.isNotEmpty && rest.first == 'remove') {
      if (rest.length < 2) throw UsageException('myvault money remove ID', usage);
      store.deleteExpense(rest[1]);
      return out({'removed': rest[1]}, () => 'Removed.');
    }
    if (rest.isNotEmpty && rest.first == 'me') {
      if (rest.length > 1) store.addOwnName(rest.sublist(1).join(' '));
      store.markOwnTransfers();
      return out({'own_names': store.ownNames}, () => 'Your names on payments: ${store.ownNames.join(', ')}');
    }
    if (rest.isNotEmpty && rest.first == 'add') {
      final rupeesIn = rest.length < 2 ? null : double.tryParse(rest[1].replaceAll(',', ''));
      if (rupeesIn == null || rupeesIn <= 0) throw UsageException('Say how much: myvault money add 120 chai', usage);
      final e = store.addExpense(amount: (rupeesIn * 100).round(), merchant: rest.length > 2 ? rest.sublist(2).join(' ') : null);
      return out(e.toJson(), () => 'Added ${rupees(e.amount)}${e.merchant == null ? '' : ' at ${e.merchant}'} (${e.category}).');
    }
    final s = store.moneySummary(rest.isEmpty ? null : rest.first);
    final recurring = store.recurring();
    out({...s.toJson(), 'recurring': [for (final r in recurring) r.toJson()]}, () {
      if (s.items.isEmpty) return 'No payments recorded for ${s.month}. The phone app reads them from bank messages.';
      return [
        '${s.month}: spent ${rupees(s.spent)}, received ${rupees(s.received)}'
            '${s.budget == null ? '' : ', budget ${rupees(s.budget!)} (${rupees(s.budget! - s.spent)} left)'}',
        '',
        for (final (c, v) in s.byCategory) '${rupees(v).padLeft(12)}  $c',
        '',
        'Top: ${s.topMerchants.take(5).map((m) => '${m.$1} ${rupees(m.$2)}').join(', ')}',
        if (recurring.isNotEmpty) 'Every month: ${recurring.map((r) => '${r.merchant} ${rupees(r.amount)}').join(', ')}',
      ].join('\n');
    });
  }
}

class HealthCommand extends Cmd {
  HealthCommand()
      : super('health', 'Sleep, steps, water, weight and workouts: myvault health [DAYS]; log: health water 500, health weight 71.5, health workout Push day');

  @override
  void run() {
    if (rest.isNotEmpty && ['water', 'weight', 'workout'].contains(rest.first)) {
      final value = rest.length > 1 ? rest.sublist(1).join(' ') : '';
      switch (rest.first) {
        case 'water':
          final ml = int.tryParse(value);
          if (ml == null) throw UsageException('Say how much in ml: myvault health water 500', usage);
          final total = store.addWater(ml);
          return out({'water_ml': total}, () => 'Water today: $total ml');
        case 'weight':
          final kg = double.tryParse(value);
          if (kg == null) throw UsageException('Say the weight in kg: myvault health weight 71.5', usage);
          store.setHealth(today(), HealthKind.weight, kg);
          return out({'weight_kg': kg}, () => 'Weight: $kg kg');
        default:
          final id = store.addWorkout(value);
          return out({'id': id, 'workout': value}, () => 'Logged: $value');
      }
    }
    final days = store.healthDays(days: rest.isEmpty ? 7 : int.parse(rest.first));
    out([for (final d in days) d.toJson()], () => [
          for (final d in days)
            [
              prettyDate(d.date).padRight(12),
              if (d.sleepMin != null)
                'slept ${d.sleepMin! ~/ 60}h${(d.sleepMin! % 60).toString().padLeft(2, '0')}${d.sleepGuessed ? '~' : ''}',
              if (d.steps != null) '${d.steps} steps',
              if (d.water > 0) '${d.water} ml',
              if (d.weight != null) '${d.weight} kg',
              ...d.workouts.map((w) => w.detail),
            ].join('  '),
          '(~ = worked out from phone use)',
        ].join('\n'));
  }
}

/// Used by the GNOME extension to report which window had focus.
class _UsageAdd extends Cmd {
  @override
  bool get hidden => true;

  _UsageAdd()
    : super(
        'usage-add',
        'Record foreground time: myvault usage-add \'[{"app":..,"name":..,"start":ISO,"end":ISO}]\'',
      );

  @override
  void run() {
    needArgs('a JSON list of spans');
    final spans = [
      for (final s in jsonDecode(rest.first) as List)
        UsageSpan(
          s['app'] as String,
          s['name'] as String,
          DateTime.parse(s['start'] as String).toLocal(),
          DateTime.parse(s['end'] as String).toLocal(),
        ),
    ];
    if (store.getMeta('device_name') == null) store.setDeviceName(Platform.localHostname);
    store.addUsage(spans);
    out({'recorded': spans.length}, () => 'Recorded ${spans.length} spans.');
  }
}

class McpCommand extends Cmd {
  McpCommand() : super('mcp', 'Run the tool server for an assistant (MCP on stdin/stdout).');

  @override
  Future<void> run() => serveMcp(store);
}

String prompt(String label, {bool secret = false}) {
  stderr.write('$label: ');
  if (!secret || !stdin.hasTerminal) return stdin.readLineSync()?.trim() ?? '';
  stdin.echoMode = false;
  try {
    return stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = true;
    stderr.writeln();
  }
}

/// Asks a yes-or-no question; Enter takes [fallback].
bool confirm(String question, {required bool fallback}) {
  final answer = prompt('$question [${fallback ? 'Y/n' : 'y/N'}]').toLowerCase();
  return answer.isEmpty ? fallback : answer.startsWith('y');
}

/// Asks for a line; Enter takes [fallback].
String ask(String label, String fallback) {
  final answer = prompt('$label [$fallback]');
  return answer.isEmpty ? fallback : answer;
}

String _expandHome(String path) => path == '~' || path.startsWith('~/') ? homeDir + path.substring(1) : path;

class SchemaCommand extends Cmd {
  SchemaCommand()
    : super('schema', 'Print the SQL that sets up a sync server. Paste it into your Supabase SQL editor.');

  @override
  void run() => stdout.write(schemaSql);
}

class InitCommand extends Cmd {
  InitCommand()
    : super(
        'init',
        'Set up Vault: your notes, a few questions about you, your agents, then (optionally) GitHub and sync. '
            'Safe to run again.',
      ) {
    argParser
      ..addOption('vault', help: 'Keep your notes in this folder (default ~/Vault).')
      ..addOption('name', help: 'What your agents should call you.')
      ..addMultiOption('goal', help: 'A goal, for Me.md. Repeat for more.')
      ..addOption('wake', help: 'When you usually wake up, HH:MM.')
      ..addOption('sleep', help: 'When you usually go to sleep, HH:MM.')
      ..addMultiOption(
        'assistant',
        allowed: [for (final a in assistants) a.id],
        help: 'Connect this assistant.',
      )
      ..addOption('github', help: 'Keep your notes in a new private GitHub repository with this name.')
      ..addOption('server', help: 'Sync: your Supabase project URL.')
      ..addOption('key', help: 'Sync: its publishable key.')
      ..addOption(
        'email',
        help: 'Sync: the account to sign in with. The password is asked for, or read from standard input.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help:
            'Take every default without asking: notes in ~/Vault, '
            'every agent found connected, no GitHub, no sync.',
      )
      ..addFlag('defaults', negatable: false, help: 'Ask nothing: do only what the options above say.');
  }

  @override
  Future<void> run() async {
    final yes = argResults!.flag('yes');
    final asking = stdin.hasTerminal && !argResults!.flag('defaults') && !yes;
    final done = <String>[];
    final left = <String>[];
    void say(String text) => stderr.writeln(text);

    if (asking) {
      say(
        'Setting up Vault: a private second brain that your agents share.\n'
        'Five short steps; Enter takes the answer in capitals. Run this again any time to change an answer.\n',
      );
    }

    // 1. Notes: the vault itself.
    String? vault = vaultPath(store);
    if (vault != null && opt('vault') == null && Directory(vault).existsSync()) {
      done.add('Notes: $vault');
    } else {
      var path = opt('vault');
      if (asking && path == null) {
        say(
          '1. Your notes. A folder of plain Markdown (it opens in Obsidian) that your diary is filed into:\n'
          '   you, your goals, projects, people, what you learn and decide. Your agents read it.',
        );
        if (confirm('   Keep your notes?', fallback: true)) path = ask('   Where', defaultVaultPath());
        say('');
      } else if (path == null && yes) {
        path = defaultVaultPath();
      }
      if (path != null) {
        path = Directory(_expandHome(path)).absolute.path;
        final written = scaffoldVault(path);
        store.setMeta(vaultPathKey, path);
        vault = path;
        done.add(written.isEmpty ? 'Notes: $path (already there).' : 'Notes: created at $path.');
      } else {
        vault = null;
        done.add('Notes: none. Tasks, habits and the diary still work.');
      }
    }

    // 2. About you: the start of Me.md.
    if (vault != null && meIsBlank(vault)) {
      var name = opt('name');
      var goalList = argResults!.multiOption('goal');
      var wake = opt('wake');
      var sleep = opt('sleep');
      if (asking) {
        say('2. About you. Your agents read this first, so they never start from zero. Leave any blank.');
        name ??= prompt('   What should your agents call you?');
        if (goalList.isEmpty) {
          say('   What are you working towards? One goal per line; an empty line ends.');
          goalList = [
            for (String? line = prompt('   -'); line != null && line.isNotEmpty; line = prompt('   -')) line,
          ];
        }
        wake ??= prompt('   When do you usually wake up? (HH:MM)');
        sleep ??= prompt('   And go to sleep? (HH:MM)');
        say('');
      }
      if ((name ?? '').isNotEmpty ||
          goalList.isNotEmpty ||
          (wake ?? '').isNotEmpty ||
          (sleep ?? '').isNotEmpty) {
        fillMe(vault, name: name, goals: goalList, wake: wake, sleep: sleep);
        done.add('About you: written to Me.md. Add to it any time; agents read it first.');
      } else {
        left.add('About you: fill in $vault/Me.md, or run: myvault goals add ...');
      }
    }

    // 3. Agents.
    final wanted = argResults!.multiOption('assistant');
    final found = [
      for (final a in assistants)
        if (isInstalled(a.command)) a,
    ];
    final chosen = <Assistant>[
      for (final a in assistants)
        if (wanted.contains(a.id)) a,
    ];
    if (yes && wanted.isEmpty) chosen.addAll(found);
    if (asking && wanted.isEmpty) {
      say(
        '3. Your agents. Connected, they share this memory and your plan: they can read your notes, save what\n'
        '   is worth keeping, log their work to your projects and plan your day.',
      );
      if (found.isEmpty) say('   Neither Claude Code nor Codex is installed on this machine.');
      for (final a in found) {
        if (confirm('   Connect ${a.name}?', fallback: true)) chosen.add(a);
      }
      say('');
    }
    final command = todoCommand();
    for (final a in chosen) {
      done.addAll(connect(a, todo: command));
    }
    if (chosen.isEmpty) {
      left.add(
        found.isEmpty
            ? 'Agents: install Claude Code or Codex, then run `myvault init` again to connect it.'
            : 'Agents: not connected. Run `myvault init` again when you want it.',
      );
    }

    // 4. GitHub, so a cloud routine can reach the notes.
    if (vault != null) {
      var repo = opt('github');
      final hasRemote = Process.runSync('git', ['-C', vault, 'remote', 'get-url', 'origin']).exitCode == 0;
      if (hasRemote) {
        done.add('GitHub: the notes already have a remote.');
      } else {
        if (asking && repo == null) {
          say(
            '4. Back up your notes to a private GitHub repository? That also lets a nightly routine in the\n'
            '   cloud file your diary and plan your day while your laptop is off.',
          );
          if (confirm('   Keep them on GitHub?', fallback: false)) {
            repo = ask('   Repository name', 'my-vault');
          }
          say('');
        }
        if (repo != null) {
          done.addAll(vaultToGitHub(vault, repo));
        } else if (!Directory('$vault/.git').existsSync()) {
          if (gitInit(vault)) {
            done.add('Notes: kept under git on this machine, so every change has a history.');
          } else {
            left.add(
              'Notes: git could not make a first commit. Tell it who you are '
              '(git config --global user.name "..." and user.email "..."), then run: myvault notes save',
            );
          }
        }
      }
    }

    // 5. Sync, for the phone and other computers.
    final remote = SupabaseRemote(store);
    if (remote.signedIn) {
      done.add('Sync: signed in as ${remote.email}.');
    } else {
      var url = opt('server') ?? remote.url;
      var key = opt('key');
      if (asking) {
        say(
          '5. Sync with your phone? Your diary, tasks and plan live on this machine. To have them in the Vault\n'
          '   app too, they sync through a free Supabase project of your own; nobody else holds your data.',
        );
        if (confirm('   Set up sync now?', fallback: false)) {
          if (url == null || !confirm('   Use the server already set ($url)?', fallback: true)) {
            final sql = File('${Directory.systemTemp.path}/myvault-schema.sql')..writeAsStringSync(schemaSql);
            say(
              '   a. Create a project at https://supabase.com/dashboard\n'
              '   b. Open its SQL editor, paste the contents of ${sql.path} and run it.\n'
              '   c. Under Authentication > Users, add a user for yourself (email and password).\n'
              '   d. Under Project Settings > API keys, copy the project URL and the publishable key.',
            );
            url = prompt('   Project URL');
            key = prompt('   Publishable key');
          }
        } else {
          url = null;
        }
        say('');
      } else if (opt('server') == null) {
        url = null;
      }
      if (url != null && url.isNotEmpty) {
        if (key != null && key.isNotEmpty) remote.configure(url: url, anonKey: key);
        final email = opt('email') ?? (asking ? prompt('   Email of that user') : '');
        if (email.isEmpty) {
          left.add('Sync: the server is set. Sign in with: myvault login');
        } else {
          try {
            await remote.signIn(email, prompt('   Password', secret: true));
            final r = await SyncEngine(store, remote).sync();
            done.add('Sync: signed in as $email.');
            if (r.missing.isNotEmpty) {
              left.add(
                'Sync: the server has no ${r.missing.join(', ')} table yet. Run the SQL from `myvault schema` in its SQL editor.',
              );
            }
          } on SyncException catch (e) {
            left.add('Sync: could not sign in (${e.message}). Try again with: myvault login');
          } on SocketException {
            left.add('Sync: could not reach the server. Try again with: myvault login');
          } on http.ClientException {
            left.add('Sync: could not reach the server. Try again with: myvault login');
          }
        }
      } else {
        done.add('Sync: off. Everything works on this device; `myvault init` again to add the phone.');
      }
    }

    out({'done': done, 'left': left}, () {
      return [
        'Set up:',
        for (final line in done) '  $line',
        if (left.isNotEmpty) ...['Left to do:', for (final line in left) '  $line'],
        '',
        'Start here:',
        '  myvault capture Finish the report by Friday     put anything in your diary',
        '  myvault today                                   your day',
        '  myvault search report                           your notes, diary and tasks',
        '  myvault doctor                                  check the setup',
        '  myvault routine                                 a nightly routine that plans tomorrow',
      ].join('\n');
    });
  }
}

class LoginCommand extends Cmd {
  LoginCommand() : super('login', 'Sign in to the sync server (set it first with: myvault server).') {
    argParser.addOption('email');
  }

  @override
  Future<void> run() async {
    final remote = SupabaseRemote(store);
    final email = opt('email') ?? prompt('Email');
    await remote.signIn(email, prompt('Password', secret: true));
    final r = await SyncEngine(store, remote).sync();
    out({
      'email': email,
      ...r.toJson(),
    }, () => 'Signed in as $email. Pulled ${r.pulled}, pushed ${r.pushed}.');
  }
}

class ServerCommand extends Cmd {
  ServerCommand() : super('server', 'Show the sync server, or set it: myvault server URL PUBLISHABLE_KEY');

  @override
  void run() {
    final remote = SupabaseRemote(store);
    if (rest.length == 2) {
      remote.configure(url: rest[0], anonKey: rest[1]);
    } else if (rest.isNotEmpty) {
      usageException('Give the project URL and its publishable key, or nothing to show the current server.');
    }
    out(
      {'url': remote.url, 'signed_in': remote.signedIn, 'email': remote.email},
      () => remote.url == null
          ? 'No sync server set.'
          : '${remote.url}  (${remote.signedIn ? 'signed in as ${remote.email}' : 'not signed in'})',
    );
  }
}

class LogoutCommand extends Cmd {
  LogoutCommand() : super('logout', 'Sign out of sync on this device. Local data stays.');

  @override
  void run() {
    SupabaseRemote(store).signOut();
    out({'signed_in': false}, () => 'Signed out.');
  }
}

class SyncCommand extends Cmd {
  SyncCommand() : super('sync', 'Sync with the server now.');

  @override
  Future<void> run() async {
    // The phone cannot read the vault, so what it shows of it travels as pages.
    final vault = vaultPath(store);
    if (vault != null && Directory(vault).existsSync()) publishPages(store, vault);
    final r = await SyncEngine(store, SupabaseRemote(store)).sync();
    out(
      r.toJson(),
      () =>
          'Pulled ${r.pulled}, pushed ${r.pushed}.'
          '${r.missing.isEmpty ? '' : '\nNot synced, the server has no table for: ${r.missing.join(', ')}. '
                    'Run the latest supabase/schema.sql.'}'
          '${r.missingColumns.isEmpty ? '' : '\nThe server is missing ${[for (final e in r.missingColumns.entries) ...e.value.map((c) => '${e.key}.$c')].join(', ')}; '
                    'those values stay on this device until you run the output of `myvault schema` in its SQL editor.'}',
    );
  }
}

// ---------------------------------------------------------------------------
// The second brain: capture, search, notes, projects, goals, pages, health.

String get _vault => requireVault(vaultPath(store));

String _readAllStdin() {
  final b = StringBuffer();
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    b.writeln(line);
  }
  return b.toString().trim();
}

class CaptureCommand extends Cmd {
  CaptureCommand()
    : super(
        'capture',
        'Put a thought in your diary, fast: myvault capture Call Ansh about fellowships tomorrow',
      ) {
    argParser.addOption('task', help: 'A task it is about (id or prefix).');
  }

  @override
  List<String> get aliases => ['c'];

  @override
  void run() {
    needArgs('what to capture');
    final body = rest.length == 1 && rest.first == '-' ? _readAllStdin() : rest.join(' ');
    if (body.trim().isEmpty) usageException('Give what to capture.');
    final e = store.addDiary(
      body,
      taskId: opt('task') == null ? null : store.resolveId('tasks', opt('task')!),
    );
    out(e.toJson(), () => 'Captured. It is filed into your notes and plans tonight.');
  }
}

class SearchCommand extends Cmd {
  SearchCommand()
    : super(
        'search',
        'Search your notes, diary and tasks: myvault search hash maps [--in notes|diary|tasks]',
      ) {
    argParser
      ..addMultiOption(
        'in',
        allowed: ['notes', 'diary', 'tasks'],
        help: 'Where to look (default: everywhere).',
      )
      ..addOption('limit', abbr: 'n', defaultsTo: '20');
  }

  @override
  List<String> get aliases => ['s'];

  @override
  void run() {
    needArgs('what to look for');
    final kinds = {
      for (final k in argResults!.multiOption('in'))
        k == 'notes'
            ? 'note'
            : k == 'tasks'
            ? 'task'
            : k,
    };
    final hits = search(
      store,
      vaultPath(store),
      rest.join(' '),
      kinds: kinds,
      limit: int.parse(opt('limit')!),
    );
    out([for (final h in hits) h.toJson()], () {
      if (hits.isEmpty) return 'Nothing found.';
      return [
        for (final h in hits)
          '${h.kind.padRight(5)} ${h.where}${h.line == null ? '' : ':${h.line}'}\n      ${h.text.length > 110 ? '${h.text.substring(0, 110)}…' : h.text}',
      ].join('\n');
    });
  }
}

class NoteCommand extends Cmd {
  NoteCommand() : super('note', 'Notes worth keeping: myvault note new TITLE, note show TITLE, note list') {
    addSubcommand(_NoteNew());
    addSubcommand(_NoteShow());
    addSubcommand(_NoteList());
  }
}

class _NoteNew extends Cmd {
  _NoteNew()
    : super('new', 'Save a note: myvault note new "CS229 or Karpathy" --body "..." (or --body - for stdin)') {
    argParser
      ..addOption('body', help: 'Its text; - reads standard input.')
      ..addOption('project', abbr: 'p', help: 'Put it in this project\'s folder instead of notes/.')
      ..addOption('source', help: 'The link it summarises, for something you shared.');
  }

  @override
  void run() {
    needArgs('a title');
    final body = opt('body') == '-' ? _readAllStdin() : (opt('body') ?? '');
    final rel = newNote(_vault, rest.join(' '), body: body, project: opt('project'), source: opt('source'));
    out({'path': rel}, () => 'Saved $rel. Run `myvault notes save` to commit it.');
  }
}

class _NoteShow extends Cmd {
  _NoteShow() : super('show', 'Print a note: myvault note show TITLE (or a path in the vault)');

  @override
  void run() {
    needArgs('a title or path');
    final n = readNote(_vault, rest.join(' '));
    out({'path': n.path, 'text': n.text}, () => n.text.trimRight());
  }
}

class _NoteList extends Cmd {
  _NoteList() : super('list', 'List the notes in notes/.');

  @override
  void run() {
    final dir = Directory('$_vault/notes');
    final names = dir.existsSync()
        ? ([
            for (final f in dir.listSync().whereType<File>())
              if (f.path.endsWith('.md')) f.uri.pathSegments.last.replaceAll('.md', ''),
          ]..sort())
        : <String>[];
    out(
      names,
      () => names.isEmpty ? 'No notes yet. Save one with: myvault note new TITLE' : names.join('\n'),
    );
  }
}

class ProjectCommand extends Cmd {
  ProjectCommand() : super('project', 'Your projects in the vault: project list, new, log, link') {
    addSubcommand(_ProjectList());
    addSubcommand(_ProjectNew());
    addSubcommand(_ProjectLog());
    addSubcommand(_ProjectLink());
  }
}

class _ProjectList extends Cmd {
  _ProjectList() : super('list', 'List projects, most recently updated first.');

  @override
  void run() {
    final ps = listProjects(_vault);
    out([for (final x in ps) x.toJson()], () {
      if (ps.isEmpty) return 'No projects yet. Start one with: myvault project new NAME';
      return [
        for (final x in ps) '${x.name.padRight(28)} ${(x.status ?? '').padRight(9)} ${x.updated ?? ''}',
      ].join('\n');
    });
  }
}

class _ProjectNew extends Cmd {
  _ProjectNew()
    : super(
        'new',
        'Start a project: myvault project new Helios --what "security scanning that ships fixes" [--repo URL]',
      ) {
    argParser
      ..addOption('what', help: 'What it is, in a line.')
      ..addOption('repo', help: 'Its repository.')
      ..addOption('folder', help: 'A code folder to link to it (see: project link).');
  }

  @override
  void run() {
    needArgs('a name');
    final name = rest.join(' ');
    final base = newProject(_vault, name, what: opt('what'), repo: opt('repo'));
    final linked = opt('folder') == null ? const <String>[] : linkFolder(_vault, opt('folder')!, name);
    out({
      'path': base,
      'linked': linked,
    }, () => ['Started $base (overview, log and info).', ...linked].join('\n'));
  }
}

class _ProjectLog extends Cmd {
  _ProjectLog()
    : super(
        'log',
        'Log finished work: myvault project log Helios "Sessions and API tokens done" --ref "PR #12"',
      ) {
    argParser.addOption('ref', help: 'The pull request, commit or link it came from.');
  }

  @override
  void run() {
    if (rest.length < 2) usageException('Give the project and what was done.');
    final rel = logProject(_vault, rest.first, rest.skip(1).join(' '), ref: opt('ref'));
    out({'path': rel}, () => 'Logged in $rel.');
  }
}

class _ProjectLink extends Cmd {
  _ProjectLink()
    : super(
        'link',
        'Tie a code folder to a project, so agents working there log to it: myvault project link Helios [FOLDER]',
      );

  @override
  void run() {
    needArgs('the project');
    final lines = linkFolder(_vault, rest.length > 1 ? rest[1] : Directory.current.path, rest.first);
    out({'done': lines}, () => lines.join('\n'));
  }
}

class GoalsCommand extends Cmd {
  GoalsCommand()
    : super(
        'goals',
        'Your goals, from Me.md: myvault goals, or add one: myvault goals add Land an ML internship',
      );

  @override
  void run() {
    if (rest.isNotEmpty && rest.first == 'add') {
      if (rest.length < 2) usageException('Give the goal.');
      addGoal(_vault, rest.skip(1).join(' '));
      out({'added': rest.skip(1).join(' ')}, () => 'Added to Me.md.');
      return;
    }
    final gs = goals(_vault);
    out(
      gs,
      () => gs.isEmpty
          ? 'No goals in Me.md yet. Add one: myvault goals add ...'
          : [for (final g in gs) '- $g'].join('\n'),
    );
  }
}

class PageCommand extends Cmd {
  PageCommand(String name, this.folder, String what) : super(name, what);
  final String folder;

  @override
  void run() {
    final pg = page(_vault, folder, date: rest.isEmpty ? null : parseDate(rest.first));
    if (pg == null) {
      throw TodoException(
        folder == 'morning'
            ? 'No morning page yet. The nightly routine writes one into morning/ (see docs/briefing-agent.md).'
            : 'No weekly page yet. The Saturday night run writes one into weekly/.',
      );
    }
    out({'path': pg.path, 'text': pg.text}, () => pg.text.trimRight());
  }
}

class _NotesPublish extends Cmd {
  _NotesPublish()
    : super(
        'publish',
        'Copy your morning and weekly pages, goals and projects into sync for the phone (sync does it too).',
      );

  @override
  void run() {
    final n = publishPages(store, _vault);
    out(
      {'changed': n},
      () => n == 0 ? 'Nothing new to publish.' : 'Published $n pages; they reach the phone on the next sync.',
    );
  }
}

class _NotesSave extends Cmd {
  _NotesSave() : super('save', 'Commit the vault and push it: myvault notes save [-m MESSAGE]') {
    argParser.addOption('message', abbr: 'm');
  }

  @override
  void run() {
    final lines = saveVault(_vault, message: opt('message'));
    out({'done': lines}, () => lines.join('\n'));
  }
}

class _NotesLog extends Cmd {
  _NotesLog()
    : super('log', 'Add a line to the vault\'s log.md: myvault notes log query "CS229 or Karpathy"');

  @override
  void run() {
    if (rest.length < 2 || !logOps.contains(rest.first)) {
      usageException('Give one of ${logOps.join(', ')}, then the text.');
    }
    appendLog(_vault, rest.first, rest.skip(1).join(' '));
    out({'ok': true}, () => 'Logged.');
  }
}

class DoctorCommand extends Cmd {
  DoctorCommand() : super('doctor', 'Check the setup: data, sync, notes, agents and the nightly routine.');

  @override
  void run() {
    final checks = <Check>[];
    checks.add(Check(true, 'Data', defaultDbPath()));
    final remote = SupabaseRemote(store);
    checks.add(
      remote.signedIn
          ? Check(true, 'Sync', 'signed in as ${remote.email}')
          : Check(
              false,
              'Sync',
              remote.url == null ? 'off (this device only)' : 'server set, not signed in',
              fix: remote.url == null ? 'myvault init (optional)' : 'myvault login',
            ),
    );
    final v = vaultStatus(store);
    if (v['path'] == null || v['exists'] != true) {
      checks.add(const Check(false, 'Notes', 'no vault', fix: 'myvault notes init'));
    } else {
      checks.add(Check(true, 'Notes', '${v['path']}${v['remote'] == null ? ' (no git remote)' : ''}'));
      final issues = lintVault(v['path'] as String);
      final errors = issues.where((i) => i.isError).length;
      checks.add(
        Check(
          errors == 0,
          'Notes health',
          '$errors errors, ${issues.length - errors} warnings',
          fix: errors == 0 ? null : 'myvault notes lint',
        ),
      );
      checks.add(
        Check(
          (v['unfiled'] as int) == 0,
          'Diary',
          "${v['unfiled']} ${v['unfiled'] == 1 ? 'entry' : 'entries'} waiting to be filed",
          fix: (v['unfiled'] as int) == 0
              ? null
              : 'ask your agent to "file my diary", or wait for the nightly run',
        ),
      );
      final m = page(v['path'] as String, 'morning');
      checks.add(
        Check(
          m != null,
          'Morning page',
          m?.path ?? 'none yet',
          fix: m == null ? 'set up the nightly routine: myvault routine' : null,
        ),
      );
    }
    for (final a in assistants) {
      if (!isInstalled(a.command)) continue;
      final known = Process.runSync(a.command, ['mcp', 'get', 'myvault']).exitCode == 0;
      checks.add(
        Check(
          known,
          a.name,
          known ? 'connected (tool server myvault)' : 'not connected',
          fix: known ? null : 'myvault init --assistant ${a.id}',
        ),
      );
    }
    out(
      [for (final c in checks) c.toJson()],
      () => [
        for (final c in checks)
          '${c.ok ? 'ok  ' : 'todo'}  ${c.what.padRight(13)} ${c.detail}${c.fix == null ? '' : '\n                     → ${c.fix}'}',
      ].join('\n'),
    );
  }
}

/// The prompt for a scheduled cloud session that runs every night: it plans
/// the next day, files the diary into the vault and writes the morning page.
/// [notesRepo] is the vault's GitHub repository, if it has one.
String routinePrompt({String? notesRepo, String? timezone}) => [
  'You are the nightly assistant for the owner of these repositories: you keep track of everything they commit '
      'to, plan their next day, file their diary into their vault of notes, and write their morning page. Nobody '
      'is watching this run.',
  'First run `export TZ=${timezone ?? 'YOUR/Timezone'}` and keep it set for every command.',
  'The repositories checked out are vault-app (Vault, the tool; its command is `myvault`)'
      '${notesRepo == null ? '' : ' and $notesRepo (their private notes)'}. Find them with `pwd; ls; ls ..`.',
  'Go into vault-app and read docs/briefing-agent.md. Follow it completely: setup, reading the facts, processing '
      'every unprocessed diary entry, closing the day, planning, `myvault check-plan` until the plan holds, the '
      'limits, the vault and writing back. The setup script needs MYVAULT_SUPABASE_URL, MYVAULT_SUPABASE_KEY, '
      'MYVAULT_EMAIL and MYVAULT_PASSWORD from this environment; if any is missing or setup fails, stop and report '
      'it without printing the values.',
  if (notesRepo != null)
    'In the vault, before planning, read `Rules.md`, then `Me.md`, then `README.md` (the schema: layout, filing, '
        'editing rules, lint, log format, the morning and weekly pages) and `INDEX.md`. Rules.md wins over '
        'everything, Me.md over general advice. File the diary as README.md says, run `myvault notes lint` and fix '
        'its errors, write the morning page into `morning/` (and on the night before Sunday the weekly page into '
        '`weekly/`), then commit in the vault and `git push origin HEAD:main`, never forcing it.',
  'Your final message is the morning page. Do not edit, commit or push anything in the vault-app repository.',
].join('\n\n');

class RoutineCommand extends Cmd {
  RoutineCommand()
    : super('routine', 'Set up the nightly routine: prints the steps and the prompt to paste.');

  @override
  void run() {
    final v = vaultStatus(store);
    final remote = v['remote'] as String?;
    final notesRepo = remote == null
        ? null
        : RegExp(r'github\.com[:/](.+?)(\.git)?$').firstMatch(remote)?.group(1);
    final tz = Platform.environment['TZ'] ?? DateTime.now().timeZoneName;
    final prompt = routinePrompt(
      notesRepo: notesRepo?.split('/').last,
      timezone: tz.contains('/') ? tz : null,
    );
    final syncOn = SupabaseRemote(store).signedIn;
    out(
      {'prompt': prompt, 'notes_repo': notesRepo, 'sync': syncOn},
      () => [
        'The nightly routine is a Claude Code session in the cloud that runs every night, even with your laptop off.',
        '',
        'Before you start:',
        '  ${syncOn ? 'ok' : 'todo'}  Sync is on (the cloud reads your diary through it).${syncOn ? '' : '  → myvault init'}',
        '  ${notesRepo != null ? 'ok' : 'todo'}  Your notes are in a private GitHub repository${notesRepo == null ? '.  → myvault notes init --github NAME' : ' ($notesRepo).'}',
        '',
        'Then:',
        '  1. Open https://claude.ai/code/routines and create a routine, every day just after midnight.',
        '  2. Repositories: Atharv-tw/vault-app${notesRepo == null ? '' : ' and $notesRepo (allow pushes to main)'}.',
        '  3. Environment variables: MYVAULT_SUPABASE_URL, MYVAULT_SUPABASE_KEY, MYVAULT_EMAIL, MYVAULT_PASSWORD, TZ.',
        '  4. Tools: Bash, Read, Write, Edit, Glob, Grep.',
        '  5. Paste this prompt:',
        '',
        prompt,
      ].join('\n'),
    );
  }
}
