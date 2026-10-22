import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/diary_page.dart';
import 'package:vault_app/main.dart';
import 'package:vault_app/reminder_page.dart';
import 'package:vault_app/reminders.dart';
import 'package:vault_app/speech_models.dart';
import 'package:vault_app/state.dart';
import 'package:vault_app/sync_page.dart';
import 'package:vault_app/today_page.dart';
import 'package:vault_app/voice.dart';
import 'package:vault_app/voice_sheet.dart';
import 'package:vault_app/welcome_page.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late AppState state;

  setUp(() => state = AppState(Store(openMemoryDb())..setMeta(welcomedKey, '1')));
  tearDown(() => state.dispose());

  /// A tab, or Habits, which opens from Profile.
  Future<void> go(WidgetTester tester, String page) async {
    if (page == 'Habits') {
      await go(tester, 'Profile');
      await tester.tap(find.byKey(const ValueKey('profile-habits')));
      await tester.pumpAndSettle();
      return;
    }
    final pill = find.byKey(ValueKey('nav-$page'));
    await tester.tap(pill.evaluate().isNotEmpty ? pill : find.text(page).last);
    await tester.pumpAndSettle();
  }

  /// Opens the app; on the To-do tab unless [page] says otherwise.
  Future<void> pump(WidgetTester tester, Size size, {String page = 'To-do'}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TodoApp(state: state));
    if (page != 'Brain') await go(tester, page);
  }

  /// The + in the middle of the bar: the diary box.
  Future<void> plus(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('nav-plus')));
    await tester.pumpAndSettle();
  }

  testWidgets('ticking from the timeline updates the store and the progress card', (tester) async {
    final t = state.store.addTask(title: 'Revise OS', date: today(), startTime: '00:00', endTime: '00:01');
    final h = state.store.addHabit(title: 'Train', time: '00:02');
    state.store.addTask(title: 'Old one', date: addDays(today(), -1));
    await pump(tester, const Size(390, 800));

    expect(find.text('Revise OS'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.textContaining('1 overdue'), findsNWidgets(2));

    await tester.tap(find.byKey(ValueKey('timeline-${t.id}')));
    await tester.pump();
    expect(state.store.task(t.id).done, isTrue);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('timeline-${h.id}')));
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), {h.id});
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('All done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Now card shows the task on now, and its tick marks it done', (tester) async {
    final soon = DateTime.now().add(const Duration(hours: 1));
    final late = soon.hour < DateTime.now().hour; // within an hour of midnight
    final t = state.store.addTask(title: 'On now', date: today(), startTime: '00:00', endTime: '23:59', tag: 'DSA');
    if (!late) state.store.addTask(title: 'Up next', date: today(), startTime: hm(soon));
    await pump(tester, const Size(390, 800));
    final card = find.byKey(const ValueKey('now-card'));
    expect(find.descendant(of: card, matching: find.text('NOW')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('On now')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('until 23:59')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('now-done')));
    await tester.pump();
    expect(state.store.task(t.id).done, isTrue);
    if (!late) {
      expect(find.descendant(of: card, matching: find.text('NEXT')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Up next')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the full-screen reminder: Doing it ticks the task, Dismiss leaves it', (tester) async {
    final t = state.store.addTask(
      title: 'DSA: Two Sum',
      date: today(),
      startTime: '00:00',
      endTime: '23:59',
      tag: 'DSA',
      notes: 'Try 25 min alone first.',
    );
    Reminder reminder() =>
        Reminder(kind: 'task', id: t.id, date: today(), title: t.title, start: '00:00', end: '23:59');
    Future<void> open(Size size) async {
      await pump(tester, size);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(builder: (_) => ReminderPage(reminder())));
      await tester.pumpAndSettle();
    }

    await open(const Size(360, 640));
    expect(find.text('DSA: Two Sum'), findsWidgets);
    expect(find.text('00:00–23:59 · DSA'), findsOneWidget);
    expect(find.text('Try 25 min alone first.'), findsOneWidget);
    expect(find.text('Now, until 23:59'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderPage), findsNothing);
    expect(state.store.task(t.id).done, isFalse);
    expect(reminder().isHandled(state.store), isFalse);

    await open(const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('reminder-done')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderPage), findsNothing);
    expect(state.store.task(t.id).done, isTrue);
    expect(reminder().isHandled(state.store), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the + in the middle of the bar opens a diary box and saves an entry', (tester) async {
    await pump(tester, const Size(390, 800), page: 'Brain');
    await plus(tester);
    expect(find.byKey(const ValueKey('quick-log-bar')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('diary-draft')), 'Only did Top K today');
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    expect(state.store.diary().single.body, 'Only did Top K today');
    expect(find.byKey(const ValueKey('quick-log-bar')), findsNothing);
    expect(find.byKey(const ValueKey('nav-plus')), findsOneWidget);
    expect(find.text('Saved to the diary'), findsOneWidget);
  });

  testWidgets('adding a task through the sheet, from the + or from To-do', (tester) async {
    await pump(tester, const Size(390, 800));
    await tester.tap(find.byKey(const ValueKey('add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Read 20 pages');
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await plus(tester);
    await tester.tap(find.byKey(const ValueKey('quick-log-task')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Buy milk');
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    expect(state.store.tasks(from: today(), to: today()).map((t) => t.title), containsAll(['Read 20 pages', 'Buy milk']));
    expect(find.text('Buy milk'), findsWidgets);
  });

  testWidgets('a task can be protected from its sheet, and keeps its deadline when its day moves', (tester) async {
    final t = state.store.addTask(
      title: "Dad's project",
      date: today(),
      startTime: '23:00',
      endTime: '23:30',
      dueDate: '2026-11-05',
    );
    await pump(tester, const Size(390, 800));
    // A tap on the timeline ticks it off; holding it opens its sheet.
    final row = find.byKey(ValueKey('timeline-${t.id}'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.descendant(of: find.byType(TodayPage), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('Due ${prettyDate('2026-11-05')}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-protect')));
    await tester.pump();
    expect(find.text('Protected: stays on its day'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.store.task(t.id).protect, Task.protectDay);

    // Moving it in the app is the person's own choice: allowed, logged, deadline kept.
    state.change((s) => s.updateTask(t.id, {'date': addDays(today(), 1)}));
    expect(state.store.task(t.id).dueDate, '2026-11-05');
    expect(state.store.task(t.id).history, contains('day ${today()} -> ${addDays(today(), 1)}'));
  });

  testWidgets('every page lays out without overflow at phone and desktop widths', (tester) async {
    state.store.addHabit(title: 'Water 4 L', time: '21:00');
    state.store.addHabit(title: 'A habit with quite a long name to wrap', startDate: addDays(today(), 3));
    state.store.addTask(
      title: 'Computer Networks assignment 2, then Software Engineering assignment 1',
      date: today(),
      startTime: '11:30',
      endTime: '13:45',
      tag: 'Assignments',
      listId: state.store.ensureList('Mid-sems').id,
    );
    state.store.addTask(title: 'Karpathy 1', date: addDays(today(), 5));
    final noon = DateTime.now().copyWith(hour: 12, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    state.store.addUsage([
      UsageSpan('firefox', 'Firefox', noon, noon.add(const Duration(minutes: 50))),
      UsageSpan(
        'code',
        'A very long application name that should be cut short, not overflow',
        noon,
        noon.add(const Duration(minutes: 20)),
      ),
    ]);
    for (final size in const [Size(360, 740), Size(390, 844), Size(1200, 800)]) {
      await pump(tester, size);
      for (final page in ['To-do', 'Diary', 'Profile', 'Brain']) {
        await go(tester, page);
        expect(tester.takeException(), isNull, reason: '$page at $size');
      }
      await go(tester, 'Habits');
      expect(tester.takeException(), isNull, reason: 'Habits at $size');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await plus(tester);
      expect(tester.takeException(), isNull, reason: 'the + at $size');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      // Focus is not a tab: it opens from the button at the top.
      await tester.tap(find.byTooltip('Focus'));
      await tester.pumpAndSettle();
      expect(find.text('Start focus'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Focus at $size');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('a habit group is one tile, done when every step is ticked', (tester) async {
    final a = state.store.addHabit(title: '5 meals / Breakfast', time: '08:15');
    final b = state.store.addHabit(title: '5 meals / Lunch', time: '13:15');
    await pump(tester, const Size(390, 844));
    await go(tester, 'Habits');
    expect(find.text('5 meals'), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('habit-${a.id}')));
    await tester.pump();
    expect(find.text('0 of 1'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('habit-${b.id}')));
    await tester.pump();
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('the New habit dialog can make a habit with steps', (tester) async {
    await pump(tester, const Size(390, 844));
    await go(tester, 'Habits');
    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('habit-title')), 'Water');
    await tester.tap(find.byKey(const ValueKey('add-step')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-0')), 'Morning');
    await tester.tap(find.byKey(const ValueKey('add-step')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-1')), 'Evening');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(state.store.habits().map((h) => h.title), ['Water / Morning', 'Water / Evening']);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('0 of 2 today · 0-day streak'), findsOneWidget);
  });

  testWidgets('diary: write an entry, see it with its time, what it is about and the agent\'s note', (tester) async {
    final t = state.store.addTask(title: 'DSA: Two Sum', date: today());
    state.store.addDiary('Moved DSA to 13:30', author: DiaryEntry.assistant);
    state.store.addDiary('Finally got hash maps', taskId: t.id);
    await pump(tester, const Size(360, 740));
    await go(tester, 'Diary');
    expect(find.text('Your agent'), findsOneWidget);
    expect(find.text('DSA: Two Sum'), findsOneWidget); // the chip on the entry about the task
    expect(find.text('Today'), findsOneWidget);

    await plus(tester);
    await tester.enterText(find.byKey(const ValueKey('diary-draft')), 'Decided to park Onyx');
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    final mine = state.store.diary(author: DiaryEntry.me);
    expect(mine.map((e) => e.body), ['Finally got hash maps', 'Decided to park Onyx']);
    expect(find.text('Decided to park Onyx'), findsOneWidget);
    expect(find.text(hm(mine.last.createdAt)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diary: a day that is over folds into one tile, ten days at a time', (tester) async {
    // Three weeks of days, two entries each, and one entry today.
    for (var back = 21; back >= 1; back--) {
      state.store.addDiary('Morning of day $back', date: addDays(today(), -back));
      state.store.addDiary('Evening of day $back', date: addDays(today(), -back));
    }
    state.store.addDiary('Woke at seven');
    await pump(tester, const Size(360, 740));
    await go(tester, 'Diary');

    // Today is open; nothing from an earlier day is.
    expect(find.text('Woke at seven'), findsOneWidget);
    expect(find.text('Evening of day 1'), findsNothing);
    final list = find.descendant(of: find.byType(DiaryPage), matching: find.byType(Scrollable)).first;
    Finder tile(int back) => find.byKey(ValueKey('diary-day-${addDays(today(), -back)}'));

    // A folded day says which day it is, how much was written, and how it began.
    expect(find.descendant(of: tile(1), matching: find.text('Yesterday')), findsOneWidget);
    expect(find.descendant(of: tile(1), matching: find.text('2 entries')), findsOneWidget);
    expect(find.descendant(of: tile(1), matching: find.text('Morning of day 1')), findsOneWidget);

    // Tapping it opens that day, and tapping again folds it.
    await tester.tap(tile(1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Evening of day 1'), 100, scrollable: list);
    expect(find.text('Evening of day 1'), findsOneWidget);
    await tester.scrollUntilVisible(tile(1), -100, scrollable: list);
    await tester.tap(tile(1));
    await tester.pumpAndSettle();
    expect(find.text('Evening of day 1'), findsNothing);

    // Ten earlier days are listed; the rest come ten at a time.
    final more = find.byKey(const ValueKey('diary-more'));
    await tester.scrollUntilVisible(more, 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(tile(10), findsOneWidget);
    expect(tile(11), findsNothing);
    expect(find.text('Show 10 more days'), findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(more, 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.text('Show 1 more days'), findsNothing);
    expect(find.text('Show 1 more day'), findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(tile(21), 200, scrollable: list);
    expect(more, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diary: text deleted while the mic is on does not come back when it is turned off', (tester) async {
    final mic = _FakeDictation();
    dictationForTest = () => mic;
    addTearDown(() => dictationForTest = null);
    await pump(tester, const Size(360, 740), page: 'Diary');
    await plus(tester);
    final box = find.byKey(const ValueKey('diary-draft'));
    String text() => tester.widget<TextField>(box).controller!.text;

    await tester.tap(find.byKey(const ValueKey('diary-mic')));
    await tester.pumpAndSettle();
    mic.say('I skipped the workout and felt bad about it');
    await tester.pump();
    expect(text(), 'I skipped the workout and felt bad about it');

    // Delete the end by hand while the mic is still on, then turn it off.
    await tester.enterText(box, 'I skipped the workout');
    await tester.tap(find.byKey(const ValueKey('diary-mic')));
    await tester.pumpAndSettle();
    expect(mic.listening, isFalse);
    expect(text(), 'I skipped the workout');

    // What is saved is what is in the box.
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    expect(state.store.diary(author: DiaryEntry.me).single.body, 'I skipped the workout');
  });

  testWidgets('diary: the box has a mic and a send button in one row, and the page counts what you wrote', (tester) async {
    state.store.addDiary('Woke at seven');
    await pump(tester, const Size(360, 740), page: 'Diary');
    expect(find.descendant(of: find.byKey(const ValueKey('diary-stat-today')), matching: find.text('1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diary-filter-agent')));
    await tester.pumpAndSettle();
    expect(find.text('Woke at seven'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diary-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Woke at seven'), findsOneWidget);

    await plus(tester);
    final box = tester.getRect(find.byKey(const ValueKey('diary-draft')));
    final mic = tester.getRect(find.byKey(const ValueKey('diary-mic')));
    final send = tester.getRect(find.byKey(const ValueKey('diary-save')));
    expect(mic.left, greaterThan(box.right));
    expect(send.left, greaterThan(mic.right));
    expect(send.center.dy, closeTo(mic.center.dy, 1));
    expect(find.text('Speak'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('sync: a build with no server asks for one before signing in', (tester) async {
    await pump(tester, const Size(360, 740), page: 'Profile');
    await tester.tap(find.byKey(const ValueKey('profile-sync')));
    await tester.pumpAndSettle();
    expect(state.remote.configured, isFalse);
    expect(find.byKey(const ValueKey('sync-url')), findsOneWidget);

    // Signing in without them says what is missing and sets nothing.
    final signIn = find.text('Sign in');
    // The page's own list, not the scrolling inside a text field.
    final page = find.descendant(of: find.byType(SyncPage), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(signIn, 80, scrollable: page);
    await tester.tap(signIn);
    await tester.pump();
    expect(find.textContaining('starts with https://'), findsOneWidget);
    expect(state.remote.configured, isFalse);

    await tester.enterText(find.byKey(const ValueKey('sync-url')), 'https://example.supabase.co/');
    await tester.enterText(find.byKey(const ValueKey('sync-key')), 'sb_publishable_test');
    await tester.scrollUntilVisible(signIn, 80, scrollable: page);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(state.remote.url, 'https://example.supabase.co');
    expect(state.remote.anonKey, 'sb_publishable_test');
    // The server is kept, and can still be changed.
    expect(find.text('Server: example.supabase.co'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice: Speak asks for a speech model first, and a downloaded one can be chosen', (tester) async {
    final dir = Directory.systemTemp.createTempSync('speech');
    final library = SpeechLibrary.override = SpeechLibrary(dir);
    addTearDown(() {
      SpeechLibrary.override = null;
      dir.deleteSync(recursive: true);
    });
    void keep(SpeechModel model) {
      File(library.detectorPath).createSync(recursive: true);
      for (final f in model.files) {
        File(library.pathOf(model, f.name)).createSync(recursive: true);
      }
    }

    await pump(tester, const Size(360, 740), page: 'Diary');
    await plus(tester);

    // Nothing to listen with yet, so the mic opens the choice of models.
    await tester.tap(find.byKey(const ValueKey('diary-mic')));
    await tester.pumpAndSettle();
    expect(find.text('Voice'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-language')), findsNothing);
    for (final model in speechModels) {
      // The list is longer than a phone screen.
      await tester.scrollUntilVisible(find.text(model.name), 80, scrollable: find.byType(Scrollable).last);
      expect(find.byKey(ValueKey('voice-get-${model.id}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    Navigator.pop(tester.element(find.byType(VoiceSettings)));
    await tester.pumpAndSettle();

    // With two models on the device, the first is used until another is picked.
    final base = speechModels.firstWhere((m) => m.id == 'base');
    final hinglish = speechModels.firstWhere((m) => m.id == 'hinglish');
    keep(base);
    keep(hinglish);
    // Close the diary box; the voice button is at the top of the Diary.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-settings')));
    await tester.pumpAndSettle();
    expect(find.text(base.size), findsNothing);
    expect(find.byTooltip('Remove from this device'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('voice-language')), findsOneWidget); // base writes any language
    await tester.tap(find.text(hinglish.name));
    await tester.pumpAndSettle();
    expect(state.store.getMeta('voice_engine'), 'hinglish');
    expect(find.byKey(const ValueKey('voice-language')), findsNothing); // this one always writes Hinglish
    expect(tester.takeException(), isNull);
  });

  testWidgets('a task\'s sheet shows its diary and adds to it', (tester) async {
    final t = state.store.addTask(title: 'Karpathy 1', date: today(), startTime: '00:00', endTime: '23:59');
    state.store.addDiary('Watched up to manual backprop', taskId: t.id);
    await pump(tester, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('now-card')));
    await tester.pumpAndSettle();
    expect(find.text('Diary · 1'), findsOneWidget);
    expect(find.textContaining('Watched up to manual backprop'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-diary-add')));
    await tester.pumpAndSettle();
    expect(find.text('About: Karpathy 1'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('diary-draft')), 'Chain rule clicked');
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    expect(state.store.diary(taskId: t.id).map((e) => e.body), ['Watched up to manual backprop', 'Chain rule clicked']);
    expect(find.text('Diary · 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('habit tiles: tap to mark done, with streaks; tasks stay out', (tester) async {
    final h = state.store.addHabit(title: 'Read', startDate: addDays(today(), -40));
    state.store.setHabitCheck(h.id, addDays(today(), -1), true);
    state.store.addHabit(title: 'Later', startDate: addDays(today(), 5));
    final t = state.store.addTask(title: 'A task', date: today());
    state.store.setDone(t.id, true);
    await pump(tester, const Size(390, 844));
    await go(tester, 'Habits');

    expect(find.text('A task'), findsNothing);
    expect(find.text('0 of 1'), findsOneWidget);
    expect(find.textContaining('1-day streak'), findsOneWidget);
    expect(find.text('Not started yet'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('habit-${h.id}')));
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), {h.id});
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.textContaining('2-day streak'), findsOneWidget);
    expect(find.text('2 days'), findsNWidgets(2));

    await tester.tap(find.byKey(ValueKey('habit-${h.id}')));
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity calendar: tapping a day opens it', (tester) async {
    final yesterday = addDays(today(), -1);
    state.store.addTask(title: 'From yesterday', date: yesterday);
    await pump(tester, const Size(390, 844));
    expect(find.text('From yesterday'), findsNothing);
    await tester.tap(find.byKey(ValueKey('day-$yesterday')));
    await tester.pump();
    expect(find.text('From yesterday'), findsOneWidget);
    expect(find.textContaining('back to today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus starts and stops from the Focus page', (tester) async {
    await pump(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(state.store.currentFocus()!.plannedMin, 25);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(state.store.currentFocus(), isNull);
  });

  testWidgets('the welcome shows once on a new device', (tester) async {
    state.store.setMeta(welcomedKey, null);
    await pump(tester, const Size(390, 800), page: 'Brain');
    expect(find.text('A private second brain that your agents share.'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('welcome-start')), 200);
    await tester.tap(find.byKey(const ValueKey('welcome-start')));
    await tester.pumpAndSettle();
    // Brain is where the app opens.
    expect(find.byKey(const ValueKey('nav-Brain')), findsOneWidget);
    expect(find.byKey(const ValueKey('brain-connect')), findsOneWidget);
    expect(state.store.getMeta(welcomedKey), '1');
  });

  testWidgets('Brain: says how to connect the notes, then shows the morning page, goals and projects', (tester) async {
    await pump(tester, const Size(390, 800), page: 'Brain');
    expect(find.byKey(const ValueKey('brain-connect')), findsOneWidget);

    state.store
      ..putPage('morning', today(), '# Today\n\n## The day\n\n- 07:00–08:00 Workout\n- 11:15–12:45 DSA\n\n## Facts\n\n- 3 of 5 done',
          title: 'Today')
      ..putPage('goals', 'all', 'Land an ML internship (2026-10-14).\nShip Helios')
      ..putPage(
        'projects',
        'all',
        '[{"name":"Helios","status":"building","what":"Security scanning that ships fixes","overview":"# Helios\\n\\nThe overview."}]',
      );
    state.change((_) {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('brain-connect')), findsNothing);
    expect(find.text('This morning'), findsOneWidget);
    expect(find.text('07:00–08:00 Workout', findRichText: true), findsOneWidget);
    expect(find.text('Land an ML internship'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Helios'), 200);
    await tester.tap(find.text('Helios'));
    await tester.pumpAndSettle();
    expect(find.text('The overview.', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Brain opens with the morning page, which opens in full, and Profile reads Me.md', (tester) async {
    state.store
      ..putPage('morning', today(), '# Today\n\n## The day\n\n- 07:00–08:00 Workout\n\n## Open questions\n\n- Which internship?')
      ..putPage('me', 'all', '# Me\n\nCall me Atharv.\n\n## Goals\n\n- Ship Helios');
    await pump(tester, const Size(390, 800), page: 'Brain');
    expect(find.byKey(const ValueKey('brain-morning')), findsOneWidget);
    expect(find.text('Which internship?', findRichText: true), findsNothing);
    await tester.tap(find.byKey(const ValueKey('brain-morning')));
    await tester.pumpAndSettle();
    expect(find.text('Which internship?', findRichText: true), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await go(tester, 'Profile');
    expect(find.text('Atharv'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-info')));
    await tester.pumpAndSettle();
    expect(find.text('Ship Helios', findRichText: true), findsOneWidget);
  });

  testWidgets('the morning page answers its questions straight into the diary', (tester) async {
    state.store.putPage(
      'morning',
      today(),
      '# Today\n\n## The day\n\n- 07:00–08:00 Workout\n\n'
          '## Waiting for your yes\n\n- Move **Guitar** to 21:00?\n\n'
          '## Open questions\n\n- Which internship first?\n- Keep the 27 Oct goal?',
    );
    await pump(tester, const Size(390, 800), page: 'Brain');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brain-morning')));
    await tester.pumpAndSettle();

    // One item: straight to the answer.
    await tester.tap(find.byKey(const ValueKey<String>('answer-waiting for your yes')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('diary-reply-to')), matching: find.text('Move Guitar to 21:00?')),
        findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('diary-draft')), 'Yes');
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();

    // Several: pick one first.
    final open = find.byKey(const ValueKey<String>('answer-open questions'));
    await tester.scrollUntilVisible(open, 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-item-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('diary-draft')), 'No, drop it');
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();

    expect(state.store.diary().map((e) => e.body), [
      'Answer to "Move Guitar to 21:00?": Yes',
      'Answer to "Keep the 27 Oct goal?": No, drop it',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a diary entry shows what Vault did with it', (tester) async {
    final e = state.store.addDiary('I have to finish Helios');
    state.store.setDiaryOutcome(e.id, '1 commitment captured (Finish Helios).');
    await pump(tester, const Size(390, 800));
    await go(tester, 'Diary');
    expect(find.byKey(ValueKey('outcome-${e.id}')), findsOneWidget);
    expect(find.text('1 commitment captured (Finish Helios).'), findsOneWidget);
  });

}

/// A speech engine a test can speak through.
class _FakeDictation extends Dictation {
  bool _on = false;
  String _text = '';

  void say(String everythingSoFar) {
    _text = everythingSoFar;
    notifyListeners();
  }

  @override
  String get setup => 'fake';

  @override
  bool get listening => _on;

  @override
  String get text => _text;

  @override
  Future<void> start() async {
    _on = true;
    _text = '';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _on = false;
    notifyListeners();
  }
}
