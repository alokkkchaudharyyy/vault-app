import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Laptop location of the shared database. The desktop app, the CLI and the
/// GNOME widget all open this same file; `MYVAULT_DB` overrides it. A
/// database from before the rename to Vault (`todo/todo.db`) keeps being
/// used where it is, so nothing has to move.
String defaultDbPath() {
  final env = Platform.environment;
  final override = env['MYVAULT_DB'] ?? env['TODO_DB'];
  if (override != null && override.isNotEmpty) return override;
  final data =
      env['XDG_DATA_HOME'] ?? p.join(env['HOME'] ?? '.', '.local', 'share');
  final current = p.join(data, 'myvault', 'myvault.db');
  final before = p.join(data, 'todo', 'todo.db');
  if (!File(current).existsSync() && File(before).existsSync()) return before;
  return current;
}

Database openDb([String? path]) {
  path ??= defaultDbPath();
  final dir = Directory(p.dirname(path));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    // The database also holds the sync session, so keep the folder private.
    if (Platform.isLinux) Process.runSync('chmod', ['700', dir.path]);
  }
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA busy_timeout = 5000');
  migrate(db);
  return db;
}

Database openMemoryDb() {
  final db = sqlite3.openInMemory();
  migrate(db);
  return db;
}

/// Tables that sync. Each has `updated_at` (client clock, used for
/// last-write-wins), `deleted_at` (tombstone) and `dirty` (needs pushing).
const syncedTables = [
  'lists', 'tasks', 'habits', 'habit_checks', 'focus_sessions', 'screen_usage', 'diary', 'pages', 'expenses', 'health',
];

const _sync = '''
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  dirty INTEGER NOT NULL DEFAULT 1''';

const _migrations = [
  '''
  CREATE TABLE lists (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    $_sync
  );
  CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    list_id TEXT,
    title TEXT NOT NULL,
    notes TEXT,
    tag TEXT,
    date TEXT,
    start_time TEXT,
    end_time TEXT,
    done_at TEXT,
    calendar_event_id TEXT,
    $_sync
  );
  CREATE INDEX tasks_date ON tasks(date);
  CREATE TABLE habits (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    $_sync
  );
  CREATE TABLE habit_checks (
    id TEXT PRIMARY KEY,
    habit_id TEXT NOT NULL,
    date TEXT NOT NULL,
    done INTEGER NOT NULL,
    $_sync
  );
  CREATE INDEX habit_checks_date ON habit_checks(date);
  CREATE TABLE focus_sessions (
    id TEXT PRIMARY KEY,
    task_id TEXT,
    kind TEXT NOT NULL,
    started_at TEXT NOT NULL,
    planned_min INTEGER NOT NULL,
    ended_at TEXT,
    $_sync
  );
  CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT
  );
  ''',
  'ALTER TABLE habits ADD COLUMN time TEXT;',
  // One row per device, app and local hour; `seconds` is time in the foreground.
  '''
  CREATE TABLE screen_usage (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    device TEXT NOT NULL,
    app TEXT NOT NULL,
    name TEXT NOT NULL,
    date TEXT NOT NULL,
    hour INTEGER NOT NULL,
    seconds INTEGER NOT NULL,
    $_sync
  );
  CREATE INDEX screen_usage_date ON screen_usage(date);
  ''',
  // Daily notes: what happened and what should change, from the user or the
  // assistant that re-plans the day.
  '''
  CREATE TABLE briefs (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    author TEXT NOT NULL,
    body TEXT NOT NULL,
    $_sync
  );
  CREATE INDEX briefs_date ON briefs(date);
  ''',
  // Briefs became the diary: entries at any time of day, optionally about one
  // task or habit. `filed_at` is set once an assistant has filed the entry
  // into the user's vault.
  '''
  ALTER TABLE briefs RENAME TO diary;
  DROP INDEX briefs_date;
  CREATE INDEX diary_date ON diary(date);
  ALTER TABLE diary ADD COLUMN task_id TEXT;
  ALTER TABLE diary ADD COLUMN habit_id TEXT;
  ALTER TABLE diary ADD COLUMN filed_at TEXT;
  UPDATE meta SET key = 'pulled:diary' WHERE key = 'pulled:briefs';
  ''',
  // Commitments. A task's `date` is the day it is planned for; `due_date` is
  // when it must be done, and moving one never moves the other. `protect` is
  // null, 'day' (must stay on its day, may move within it) or 'time' (fixed
  // in time). `source_entry` is the diary entry a task was captured from.
  // `history` is an append-only log of changes to its day, time or deadline.
  // A diary entry's `outcome` says what became of it once processed.
  '''
  ALTER TABLE tasks ADD COLUMN due_date TEXT;
  ALTER TABLE tasks ADD COLUMN estimate_min INTEGER;
  ALTER TABLE tasks ADD COLUMN protect TEXT;
  ALTER TABLE tasks ADD COLUMN source_entry TEXT;
  ALTER TABLE tasks ADD COLUMN history TEXT;
  CREATE INDEX tasks_due ON tasks(due_date);
  ALTER TABLE diary ADD COLUMN outcome TEXT;
  ''',
  // Pages: what a device without the vault (the phone) shows of it: the
  // morning and weekly pages, the goals, the projects. `kind` and `key` name
  // one ('morning' and a date, 'goals' and 'all'); the laptop that has the
  // vault writes them, every device reads them.
  '''
  CREATE TABLE pages (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    key TEXT NOT NULL,
    title TEXT,
    body TEXT NOT NULL,
    $_sync
  );
  CREATE INDEX pages_kind ON pages(kind, key);
  ''',
  // Money: payments read from bank and UPI messages or typed in. `amount` is
  // in paise; `direction` is 'out' or 'in'. Health: one row per day and kind
  // for steps, sleep, water and weight, and one per workout.
  '''
  CREATE TABLE expenses (
    id TEXT PRIMARY KEY,
    at TEXT NOT NULL,
    date TEXT NOT NULL,
    amount INTEGER NOT NULL,
    direction TEXT NOT NULL,
    merchant TEXT,
    category TEXT,
    account TEXT,
    source TEXT,
    note TEXT,
    $_sync
  );
  CREATE INDEX expenses_date ON expenses(date);
  CREATE TABLE health (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    kind TEXT NOT NULL,
    value REAL,
    detail TEXT,
    $_sync
  );
  CREATE INDEX health_date ON health(date);
  ''',
];

/// Brings [db] up to the current schema, or (for tests of a migration) only
/// as far as schema version [upTo].
void migrate(Database db, {int? upTo}) {
  var version = db.select('PRAGMA user_version').first.values.first as int;
  while (version < (upTo ?? _migrations.length)) {
    db.execute('BEGIN');
    db.execute(_migrations[version]);
    version++;
    db.execute('PRAGMA user_version = $version');
    db.execute('COMMIT');
  }
}
