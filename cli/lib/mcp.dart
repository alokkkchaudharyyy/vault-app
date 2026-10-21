import 'dart:convert';
import 'dart:io';

import 'package:vault_core/vault_core.dart';

import 'brain.dart';
import 'vault.dart';
import 'vault_lint.dart';

typedef _Handler = Object? Function(Store store, Map<String, Object?> args);

class _Tool {
  const _Tool(this.name, this.description, this.properties, this.handler, {this.required = const []});

  final String name;
  final String description;
  final Map<String, Object?> properties;
  final List<String> required;
  final _Handler handler;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': {'type': 'object', 'properties': properties, 'required': required},
  };
}

Map<String, Object?> _str(String description) => {'type': 'string', 'description': description};

const _dateHelp = 'today, tomorrow, a weekday, +N days, or YYYY-MM-DD';

final _taskFields = {
  'date': _str(
    'The day it is planned for: $_dateHelp. Not its deadline; leave empty to keep it in the backlog.',
  ),
  'due': _str('Its deadline, when it must be done by: $_dateHelp. Re-planning never moves this.'),
  'estimate_min': {
    'type': 'integer',
    'description': 'Minutes it should take, for a task without a time slot.',
  },
  'protect': _str('"day": must stay on its day, may move within it. "time": fixed in time. "none": free.'),
  'source_entry': _str('Id (or prefix) of the diary entry this commitment was captured from.'),
  'time': _str('Start time or range in 24h local time: 17:30 or 17:30-18:15.'),
  'list': _str('List name; created if it does not exist.'),
  'tag': _str('Short label, e.g. Exam prep.'),
  'notes': _str('Free-text notes.'),
};

String? _s(Map<String, Object?> a, String key) => a[key] as String?;

String _taskId(Store store, Map<String, Object?> a) => store.resolveId('tasks', a['id'] as String);

final _tools = <_Tool>[
  _Tool(
    'today',
    'One day: `items` is the timeline of tasks and habits in time order; also the running focus session and minutes focused.',
    {'date': _str('Day to show ($_dateHelp). Defaults to today.')},
    (store, a) => store.snapshot(_s(a, 'date') == null ? null : parseDate(_s(a, 'date')!)),
  ),
  _Tool(
    'list_tasks',
    'List tasks in a date range, or overdue, or everything.',
    {
      'from': _str('First day ($_dateHelp).'),
      'to': _str('Last day ($_dateHelp).'),
      'overdue': {'type': 'boolean', 'description': 'Only open tasks dated before today.'},
      'include_undated': {'type': 'boolean', 'description': 'Also return tasks with no date.'},
      'open_only': {'type': 'boolean', 'description': 'Hide completed tasks.'},
      'list': _str('Only tasks in this list.'),
    },
    (store, a) {
      String? listId;
      if (_s(a, 'list') != null) {
        final l = store.findList(_s(a, 'list')!);
        if (l == null) throw TodoException('No list called "${_s(a, 'list')}"');
        listId = l.id;
      }
      final tasks = store.tasks(
        from: _s(a, 'from') == null ? null : parseDate(_s(a, 'from')!),
        to: _s(a, 'to') == null ? null : parseDate(_s(a, 'to')!),
        overdueBefore: a['overdue'] == true ? today() : null,
        undated: a['include_undated'] == true,
        includeDone: a['open_only'] != true,
        listId: listId,
      );
      return [for (final t in tasks) t.toJson()];
    },
  ),
  _Tool('add_task', 'Add a task.', {'title': _str('What to do.'), ..._taskFields}, required: ['title'], (
    store,
    a,
  ) {
    final time = _s(a, 'time') == null ? null : parseTimeRange(_s(a, 'time')!);
    final date = _s(a, 'date') != null
        ? parseDate(_s(a, 'date')!)
        : time != null
        ? today()
        : null;
    return store
        .addTask(
          title: a['title'] as String,
          listId: _s(a, 'list') == null ? null : store.ensureList(_s(a, 'list')!).id,
          date: date,
          startTime: time?.$1,
          endTime: time?.$2,
          tag: _s(a, 'tag'),
          notes: _s(a, 'notes'),
          dueDate: _s(a, 'due') == null ? null : parseDate(_s(a, 'due')!),
          estimateMin: a['estimate_min'] as int?,
          protect: _s(a, 'protect') == 'none' ? null : _s(a, 'protect'),
          sourceEntry: _s(a, 'source_entry') == null
              ? null
              : store.resolveId('diary', _s(a, 'source_entry')!),
        )
        .toJson();
  }),
  _Tool(
    'update_task',
    'Change fields of a task. Pass "none" to clear a field. Moving a protected task off its day, a fixed one at '
        'all, or changing a deadline is refused without a reason; the reason is kept in the task history.',
    {
      'id': _str('Task id or unique prefix.'),
      'title': _str('New title.'),
      ..._taskFields,
      'reason': _str('Why it is being moved or its deadline changed.'),
    },
    required: ['id'],
    (store, a) {
      String? clearable(String v) => v.toLowerCase() == 'none' ? null : v;
      final changes = <String, Object?>{};
      if (_s(a, 'title') != null) changes['title'] = _s(a, 'title');
      if (_s(a, 'date') != null) {
        final v = clearable(_s(a, 'date')!);
        changes['date'] = v == null ? null : parseDate(v);
      }
      if (_s(a, 'time') != null) {
        final v = clearable(_s(a, 'time')!);
        final range = v == null ? null : parseTimeRange(v);
        changes['start_time'] = range?.$1;
        changes['end_time'] = range?.$2;
      }
      if (_s(a, 'list') != null) {
        final v = clearable(_s(a, 'list')!);
        changes['list_id'] = v == null ? null : store.ensureList(v).id;
      }
      if (_s(a, 'tag') != null) changes['tag'] = clearable(_s(a, 'tag')!);
      if (_s(a, 'notes') != null) changes['notes'] = clearable(_s(a, 'notes')!);
      if (_s(a, 'due') != null) {
        final v = clearable(_s(a, 'due')!);
        changes['due_date'] = v == null ? null : parseDate(v);
      }
      if (a.containsKey('estimate_min')) changes['estimate_min'] = a['estimate_min'] as int?;
      if (_s(a, 'protect') != null) changes['protect'] = clearable(_s(a, 'protect')!);
      if (_s(a, 'source_entry') != null) {
        final v = clearable(_s(a, 'source_entry')!);
        changes['source_entry'] = v == null ? null : store.resolveId('diary', v);
      }
      return store.updateTask(_taskId(store, a), changes, reason: _s(a, 'reason'), guarded: true).toJson();
    },
  ),
  _Tool(
    'set_task_done',
    'Tick or untick a task.',
    {
      'id': _str('Task id or unique prefix.'),
      'done': {'type': 'boolean', 'description': 'Defaults to true.'},
    },
    required: ['id'],
    (store, a) => store.setDone(_taskId(store, a), a['done'] != false).toJson(),
  ),
  _Tool('delete_task', 'Delete a task.', {'id': _str('Task id or unique prefix.')}, required: ['id'], (
    store,
    a,
  ) {
    final id = _taskId(store, a);
    store.deleteTask(id);
    return {'deleted': id};
  }),
  _Tool(
    'add_habit',
    'Add a daily habit, optionally limited to a date range.',
    {
      'title': _str('The habit.'),
      'time': _str('Time of day it sits at in the timeline, e.g. 07:00.'),
      'from': _str('First day ($_dateHelp).'),
      'to': _str('Last day ($_dateHelp).'),
    },
    required: ['title'],
    (store, a) => store
        .addHabit(
          title: a['title'] as String,
          time: _s(a, 'time') == null ? null : parseTimeRange(_s(a, 'time')!).$1,
          startDate: _s(a, 'from') == null ? null : parseDate(_s(a, 'from')!),
          endDate: _s(a, 'to') == null ? null : parseDate(_s(a, 'to')!),
        )
        .toJson(),
  ),
  _Tool(
    'set_habit_done',
    'Tick or untick a habit for one day. Habits and their state are listed by the today tool.',
    {
      'habit': _str('Habit id, unique id prefix, or exact title.'),
      'date': _str('Day ($_dateHelp). Defaults to today.'),
      'done': {'type': 'boolean', 'description': 'Defaults to true.'},
    },
    required: ['habit'],
    (store, a) {
      final id = store.resolveHabit(a['habit'] as String);
      final date = _s(a, 'date') == null ? today() : parseDate(_s(a, 'date')!);
      store.setHabitCheck(id, date, a['done'] != false);
      return {'habit_id': id, 'date': date, 'done': a['done'] != false};
    },
  ),
  _Tool(
    'focus_start',
    'Start a focus (or break) timer, optionally on a task. Replaces any running session.',
    {
      'task_id': _str('Task id or unique prefix.'),
      'minutes': {'type': 'integer', 'description': 'Length; default 25, or 5 for a break.'},
      'break': {'type': 'boolean', 'description': 'A break rather than a focus session.'},
    },
    (store, a) {
      final isBreak = a['break'] == true;
      return store
          .startFocus(
            taskId: _s(a, 'task_id') == null ? null : store.resolveId('tasks', _s(a, 'task_id')!),
            minutes: (a['minutes'] as num?)?.toInt() ?? (isBreak ? 5 : 25),
            kind: isBreak ? 'break' : 'focus',
          )
          .toJson();
    },
  ),
  _Tool(
    'focus_stop',
    'Stop the running focus session.',
    {},
    (store, a) => store.stopFocus()?.toJson() ?? {'stopped': false, 'reason': 'No session running'},
  ),
  _Tool(
    'screen_time',
    'Screen time across the laptop and phone: total, per device, per day, apps ranked by time, and (for one day) minutes per hour.',
    {
      'from': _str('First day ($_dateHelp). Defaults to today.'),
      'to': _str('Last day ($_dateHelp). Defaults to the first day.'),
    },
    (store, a) {
      final from = _s(a, 'from') == null ? today() : parseDate(_s(a, 'from')!);
      return store.usageSummary(from, _s(a, 'to') == null ? from : parseDate(_s(a, 'to')!));
    },
  ),
  _Tool(
    'list_diary',
    'The diary, newest day first: what the user logged through each day (author "me": ideas, decisions, how things went, sometimes about one task or habit) and notes the assistant left (author "claude"). `time` is when it was logged, on the user\'s clock.',
    {
      'from': _str('First day ($_dateHelp). Defaults to 6 days before the last day.'),
      'to': _str('Last day ($_dateHelp). Defaults to today.'),
      'task': _str('Only entries about this task (id or unique prefix).'),
      'unfiled': {
        'type': 'boolean',
        'description': 'Only the user\'s entries not yet filed into their vault, however old.',
      },
      'unprocessed': {
        'type': 'boolean',
        'description': 'Only the user\'s entries of the last 14 days with no recorded outcome yet.',
      },
    },
    (store, a) {
      if (a['unprocessed'] == true) return [for (final e in store.unprocessedDiary()) e.toJson()];
      final unfiled = a['unfiled'] == true;
      final to = _s(a, 'to') == null ? today() : parseDate(_s(a, 'to')!);
      final from = _s(a, 'from') == null ? (unfiled ? null : addDays(to, -6)) : parseDate(_s(a, 'from')!);
      final entries = store.diary(
        from: from,
        to: to,
        taskId: _s(a, 'task') == null ? null : store.resolveId('tasks', _s(a, 'task')!),
        author: unfiled ? DiaryEntry.me : null,
        unfiledOnly: unfiled,
      );
      return [for (final e in entries) e.toJson()];
    },
  ),
  _Tool(
    'add_diary_entry',
    'Write a diary entry. As the assistant, use it to note what you changed in the plan and why. Pass author "me" only to record something the user said in their own words.',
    {
      'text': _str('The entry.'),
      'date': _str('Day it is about ($_dateHelp). Defaults to today.'),
      'task': _str('A task it is about (id or unique prefix).'),
      'author': {
        'type': 'string',
        'enum': [DiaryEntry.assistant, DiaryEntry.me],
        'description': 'Who is writing. Defaults to "claude".',
      },
    },
    required: ['text'],
    (store, a) => store
        .addDiary(
          a['text'] as String,
          date: _s(a, 'date') == null ? null : parseDate(_s(a, 'date')!),
          author: _s(a, 'author') ?? DiaryEntry.assistant,
          taskId: _s(a, 'task') == null ? null : store.resolveId('tasks', _s(a, 'task')!),
        )
        .toJson(),
  ),
  _Tool(
    'set_diary_outcome',
    'Record what became of one of the user\'s diary entries: the commitments captured (with task ids), the projects '
        'updated, or that it was only an idea or context, or what needs their answer. Every entry needs one.',
    {'id': _str('Entry id or unique prefix.'), 'outcome': _str('One or two plain sentences.')},
    required: ['id', 'outcome'],
    (store, a) {
      final id = store.resolveId('diary', a['id'] as String);
      store.setDiaryOutcome(id, a['outcome'] as String);
      return {'id': id, 'outcome': a['outcome']};
    },
  ),
  _Tool(
    'stats',
    'What recent days actually looked like, computed from the records: wake and bed times, tasks planned and done, '
        'protected ones done, focus, the backlog, overdue tasks, deadlines in the next 14 days and diary entries '
        'still without an outcome. Plan from this, not from an ideal day.',
    {
      'days': {'type': 'integer', 'description': 'How many days back; default 14.'},
    },
    (store, a) => store.stats(days: a['days'] as int? ?? 14).toJson(),
  ),
  _Tool(
    'check_plan',
    'Check a day\'s plan against what must hold: nothing left in the past, no deadline broken, no overlaps, nothing '
        'before the day really starts, every diary entry accounted for, at most five new commitments in the day, and '
        'the day no fuller than 75% of the time available. Fix every error, or explain it if it cannot be avoided.',
    {
      'date': _str('The day ($_dateHelp). Defaults to today.'),
      'wake': _str(
        'When the day starts, HH:MM, if the diary says; default: the typical wake time of the last 3 days.',
      ),
      'end': _str('When the day ends, HH:MM; default 22:30.'),
    },
    (store, a) => store
        .checkPlan(
          _s(a, 'date') == null ? today() : parseDate(_s(a, 'date')!),
          wake: _s(a, 'wake'),
          end: _s(a, 'end'),
        )
        .toJson(),
  ),
  _Tool(
    'money',
    'The user\'s money for a month, read from their bank and UPI messages on the phone (plus cash they typed in): '
        'spent, received, budget left, by category, top merchants, every payment, and payments that recur monthly '
        '(subscriptions, rent). Amounts are rupees.',
    {
      'month': _str('YYYY-MM; defaults to this month.'),
      'items': {'type': 'boolean', 'description': 'Include each payment; default true.'},
    },
    (store, a) => {
      ...store.moneySummary(_s(a, 'month')).toJson(withItems: a['items'] as bool? ?? true),
      'recurring': [for (final r in store.recurring()) r.toJson()],
    },
  ),
  _Tool(
    'add_expense',
    'Record a payment no bank message covers (cash), when the user mentions one.',
    {
      'amount': {'type': 'number', 'description': 'Rupees.'},
      'merchant': _str('Who was paid.'),
      'category': _str('One of: ${Categories.all.join(', ')}. Guessed from the merchant if left out.'),
      'note': _str('Anything else.'),
      'direction': _str('"out" (spent, default) or "in" (received).'),
    },
    required: ['amount'],
    (store, a) => store
        .addExpense(
          amount: ((a['amount'] as num) * 100).round(),
          merchant: _s(a, 'merchant'),
          category: _s(a, 'category'),
          note: _s(a, 'note'),
          direction: _s(a, 'direction') ?? Expense.out,
        )
        .toJson(),
  ),
  _Tool(
    'health',
    'Recent days of health: sleep (from a tracker, or from when the phone was last and first used), steps, water, '
        'weight and workouts. Plan around how they actually slept.',
    {
      'days': {'type': 'integer', 'description': 'How many days back; default 7.'},
    },
    (store, a) => [for (final d in store.healthDays(days: a['days'] as int? ?? 7)) d.toJson()],
  ),
  _Tool(
    'log_health',
    'Log water (ml, added to the day), weight (kg) or a workout (what was done) the user mentions.',
    {
      'kind': _str('"water", "weight" or "workout".'),
      'value': _str('Millilitres, kilograms, or what the workout was.'),
      'minutes': {'type': 'integer', 'description': 'Workout length, if known.'},
      'date': _str('The day ($_dateHelp). Defaults to today.'),
    },
    required: ['kind', 'value'],
    (store, a) {
      final date = _s(a, 'date') == null ? today() : parseDate(_s(a, 'date')!);
      final value = a['value'] as String;
      switch (a['kind']) {
        case 'water':
          return {'water_ml': store.addWater(int.parse(value), date: date)};
        case 'weight':
          store.setHealth(date, HealthKind.weight, double.parse(value));
          return {'weight_kg': double.parse(value)};
        case 'workout':
          return {'id': store.addWorkout(value, minutes: a['minutes'] as int?, date: date)};
        default:
          throw TodoException('kind is water, weight or workout');
      }
    },
  ),
  _Tool(
    'vault_status',
    'The user\'s vault: an optional folder of Markdown notes (it opens in Obsidian) that their diary is filed into. Gives its path on this machine, or a null path if they have none, its git remote, and how many diary entries are waiting to be filed. The vault\'s README.md holds the rules for filing.',
    {},
    (store, a) => vaultStatus(store),
  ),
  _Tool(
    'vault_lint',
    'Check the user\'s vault for upkeep: links to notes that do not exist, links into raw/ (the private diary), main notes '
        'missing from INDEX.md, notes nothing links to, missing or stale frontmatter, diary days without a summary, and '
        'log.md lines out of format. Errors break the vault\'s rules; warnings are upkeep to look at.',
    {},
    (store, a) {
      final path = vaultStatus(store)['path'] as String?;
      if (path == null) throw TodoException('No vault on this device.');
      final issues = lintVault(path);
      return {
        'path': path,
        'issues': [for (final i in issues) i.toJson()],
      };
    },
  ),
  _Tool(
    'search',
    'Search the user\'s memory: their vault of notes (never the private raw/ diary), their diary and their tasks. Every '
        'word must appear. Use it before answering anything about their projects, people, goals, past decisions or what '
        'they learned. Returns where each match is (a note\'s path and line, a diary entry\'s date and time, a task id).',
    {
      'query': _str('The words to look for.'),
      'in': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['notes', 'diary', 'tasks'],
        },
        'description': 'Where to look; default everywhere.',
      },
    },
    required: ['query'],
    (store, a) {
      final kinds = {
        for (final k in ((a['in'] as List?) ?? const []).cast<String>())
          k == 'notes' ? 'note' : (k == 'tasks' ? 'task' : k),
      };
      return {
        'hits': [for (final h in search(store, vaultPath(store), _s(a, 'query')!, kinds: kinds)) h.toJson()],
      };
    },
  ),
  _Tool(
    'read_note',
    'Read one note from the user\'s vault by its path (projects/Helios/Helios) or its title. Start with INDEX.md to '
        'find the right note. raw/ is refused: it is the word-for-word diary, read only by the filing agent.',
    {'note': _str('The note\'s path in the vault or its title.')},
    required: ['note'],
    (store, a) {
      final n = readNote(requireVault(vaultPath(store)), _s(a, 'note')!);
      return {'path': n.path, 'text': n.text};
    },
  ),
  _Tool(
    'add_note',
    'Save an answer worth keeping into the user\'s vault: an analysis, a comparison, a plan, a recommendation they '
        'act on, or a summary of a link they shared. Goes to notes/<title>.md (or a project\'s folder), is listed in '
        'INDEX.md and logged. Start the body with the question it answers; keep the substance, drop the chatter. Then '
        'call save_notes.',
    {
      'title': _str('The note\'s title, which is also its file name.'),
      'body': _str('Its Markdown text.'),
      'project': _str('A project to put it under instead of notes/.'),
      'source': _str('The link it summarises, if it is about something the user shared.'),
    },
    required: ['title', 'body'],
    (store, a) => {
      'path': newNote(
        requireVault(vaultPath(store)),
        _s(a, 'title')!,
        body: _s(a, 'body')!,
        project: _s(a, 'project'),
        source: _s(a, 'source'),
      ),
    },
  ),
  _Tool(
    'list_projects',
    'The user\'s projects in their vault, most recently updated first, each with its status and what it is.',
    {},
    (store, a) => {
      'projects': [for (final x in listProjects(requireVault(vaultPath(store)))) x.toJson()],
    },
  ),
  _Tool(
    'log_project_work',
    'Record a finished piece of work on one of the user\'s projects (a feature or fix that works, a merged pull '
        'request, a release, a decision): one dated line in projects/<name>/log.md. Results, not process; real '
        'numbers only. Then call save_notes.',
    {
      'project': _str('The project\'s name, as list_projects gives it.'),
      'text': _str('What was done, in one plain sentence.'),
      'ref': _str('The pull request, commit or link, if any.'),
    },
    required: ['project', 'text'],
    (store, a) => {
      'path': logProject(
        requireVault(vaultPath(store)),
        _s(a, 'project')!,
        _s(a, 'text')!,
        ref: _s(a, 'ref'),
      ),
    },
  ),
  _Tool(
    'list_goals',
    'The user\'s goals, from Me.md in their vault. Tie plans and suggestions to these.',
    {},
    (store, a) => {'goals': goals(requireVault(vaultPath(store)))},
  ),
  _Tool(
    'morning_page',
    'The user\'s morning page (written overnight: the day\'s plan, facts, guesses, what is waiting for their yes, '
        'open questions), or with kind weekly the latest weekly look back.',
    {
      'kind': {
        'type': 'string',
        'enum': ['morning', 'weekly'],
        'description': 'Default morning.',
      },
      'date': _str('A day ($_dateHelp); default the newest.'),
    },
    (store, a) {
      final kind = _s(a, 'kind') == 'weekly' ? 'weekly' : 'morning';
      final pg = page(
        requireVault(vaultPath(store)),
        kind,
        date: _s(a, 'date') == null ? null : parseDate(_s(a, 'date')!),
      );
      return pg == null ? {'page': null} : {'path': pg.path, 'text': pg.text};
    },
  ),
  _Tool('save_notes', 'Commit the user\'s vault and push it, after you changed notes in it.', {
    'message': _str('The commit message; default "Notes: <date>".'),
  }, (store, a) => {'done': saveVault(requireVault(vaultPath(store)), message: _s(a, 'message'))}),
  _Tool(
    'mark_diary_filed',
    'Record that diary entries have been filed into the user\'s vault, so they are not filed twice.',
    {
      'ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Entry ids or unique prefixes.',
      },
    },
    required: ['ids'],
    (store, a) {
      final ids = [for (final ref in (a['ids'] as List).cast<String>()) store.resolveId('diary', ref)];
      store.markDiaryFiled(ids);
      return {'filed': ids};
    },
  ),
];

/// Minimal MCP server: newline-delimited JSON-RPC on stdin/stdout.
Future<void> serveMcp(Store store) async {
  void send(Object? id, {Object? result, Map<String, Object?>? error}) {
    stdout.writeln(
      jsonEncode({'jsonrpc': '2.0', 'id': id, if (error != null) 'error': error else 'result': result}),
    );
  }

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final Map<String, Object?> msg;
    try {
      msg = jsonDecode(line) as Map<String, Object?>;
    } catch (_) {
      send(null, error: {'code': -32700, 'message': 'Parse error'});
      continue;
    }
    final id = msg['id'];
    final params = (msg['params'] as Map<String, Object?>?) ?? {};
    // Notifications carry no id and get no reply.
    if (!msg.containsKey('id')) continue;

    switch (msg['method']) {
      case 'initialize':
        send(
          id,
          result: {
            'protocolVersion': params['protocolVersion'] ?? '2025-06-18',
            'capabilities': {'tools': <String, Object?>{}},
            'serverInfo': {'name': 'myvault', 'version': '0.2.0'},
          },
        );
      case 'ping':
        send(id, result: <String, Object?>{});
      case 'tools/list':
        send(
          id,
          result: {
            'tools': [for (final t in _tools) t.toJson()],
          },
        );
      case 'tools/call':
        final tool = _tools.where((t) => t.name == params['name']).firstOrNull;
        if (tool == null) {
          send(id, error: {'code': -32602, 'message': 'Unknown tool: ${params['name']}'});
          break;
        }
        String text;
        var isError = false;
        try {
          final args = (params['arguments'] as Map<String, Object?>?) ?? {};
          text = jsonEncode(tool.handler(store, args));
        } on TodoException catch (e) {
          text = e.message;
          isError = true;
        } on FormatException catch (e) {
          text = e.message;
          isError = true;
        } on TypeError {
          text = 'Wrong argument type for ${tool.name}';
          isError = true;
        }
        send(
          id,
          result: {
            'content': [
              {'type': 'text', 'text': text},
            ],
            'isError': isError,
          },
        );
      default:
        send(id, error: {'code': -32601, 'message': 'Method not found: ${msg['method']}'});
    }
  }
}
