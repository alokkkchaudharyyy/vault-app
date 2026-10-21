import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:home_widget/home_widget.dart';
import 'package:vault_core/vault_core.dart';

import 'background.dart';
import 'brain_icon.dart';
import 'brain_page.dart';
import 'diary_page.dart';
import 'focus_page.dart';
import 'profile_page.dart';
import 'reminder_page.dart';
import 'reminders.dart';
import 'state.dart';
import 'theme.dart';
import 'today_page.dart';
import 'voice.dart';
import 'voice_sheet.dart';
import 'welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = await appDbPath();
  if (Platform.isAndroid) {
    await HomeWidget.registerInteractivityCallback(widgetAction);
    await startBackgroundWork();
  }
  final state = AppState(Store(openDb(path)))..start(watchDir: Platform.isLinux ? p.dirname(path) : null);
  runApp(TodoApp(state: state));
  if (Platform.isAndroid) {
    _watchWidgetLaunches(state);
    await _watchReminders(state);
  }
}

/// A widget asked for the diary composer: `todo://diary/new`, optionally
/// `?voice=1` to start listening and `?task=ID` or `?habit=ID` for what the
/// entry is about.
void _openFromWidget(AppState state, Uri? uri) {
  if (uri == null || uri.host != 'diary') return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    final q = uri.queryParameters;
    final habitId = q['habit'];
    showDiaryComposer(
      context,
      task: q['task'] == null ? null : state.store.findTask(q['task']!),
      habit: habitId == null ? null : state.store.habits().where((h) => h.id == habitId).firstOrNull,
      listen: q['voice'] == '1',
    );
  });
  WidgetsBinding.instance.scheduleFrame();
}

Future<void> _watchWidgetLaunches(AppState state) async {
  HomeWidget.widgetClicked.listen((uri) => _openFromWidget(state, uri));
  _openFromWidget(state, await HomeWidget.initiallyLaunchedFromHomeWidget());
}

final _navigator = GlobalKey<NavigatorState>();
final _reminderOpen = <String>{};

/// Opens the full-screen reminder for [r], unless it is already up or the
/// item has been ticked in the meantime.
Future<void> _showReminder(AppState state, Reminder r) async {
  final navigator = _navigator.currentState;
  if (navigator == null) return;
  if (r.isHandled(state.store)) return clearReminder(r);
  if (!_reminderOpen.add(r.key)) return;
  await navigator.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ReminderPage(r)));
  _reminderOpen.remove(r.key);
}

/// Shows a reminder when one is tapped or raised full screen by the system,
/// including when that is what started the app.
Future<void> _watchReminders(AppState state) async {
  onReminderOpened = (r) => _showReminder(state, r);
  await initNotifications();
  final launch = await notifications.getNotificationAppLaunchDetails();
  final first = launch?.didNotificationLaunchApp == true
      ? Reminder.fromPayload(launch!.notificationResponse?.payload)
      : null;
  if (first != null) WidgetsBinding.instance.addPostFrameCallback((_) => _showReminder(state, first));
  await requestNotificationPermission(state.store);
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'G.ONE',
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const Shell(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static final _pages = <({Widget Function(Color color) icon, String label, Widget page})>[
    (icon: (c) => BrainIcon(color: c), label: 'Brain', page: const BrainPage()),
    (icon: (c) => Icon(Icons.task_alt_rounded, color: c), label: 'To-do', page: const TodayPage()),
    (icon: (c) => Icon(Icons.auto_stories_rounded, color: c), label: 'Diary', page: const DiaryPage()),
    (icon: (c) => Icon(Icons.person_rounded, color: c), label: 'Profile', page: const ProfilePage()),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.store.getMeta(welcomedKey) == null) {
      return WelcomePage(onDone: () => setState(() => app.store.setMeta(welcomedKey, '1')));
    }
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final focusing = app.store.currentFocus() != null;
    final label = _pages[_index].label;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // The first page greets you; the others carry the date.
                  _index == 0
                      ? switch (DateTime.now().hour) {
                          < 5 => 'Still up',
                          < 12 => 'Good morning',
                          < 17 => 'Good afternoon',
                          _ => 'Good evening',
                        }
                      : prettyDate(today()),
                  style: text.labelLarge?.copyWith(color: AppColors.muted),
                ),
                Text(label, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
              ],
            ),
          ),
          // How speech becomes text is chosen where it is used.
          if (label == 'Diary' && voiceSupported) ...[
            IconButton.filled(
              key: const ValueKey('voice-settings'),
              tooltip: 'Voice',
              style: IconButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.ink),
              icon: const Icon(Icons.settings_voice_rounded),
              onPressed: () => showVoiceSettings(context),
            ),
            const SizedBox(width: 8),
          ],
          IconButton.filled(
            tooltip: 'Focus',
            // Lit while a session is running, wherever you are in the app.
            style: focusing
                ? IconButton.styleFrom(backgroundColor: AppColors.lavender, foregroundColor: AppColors.onLight)
                : IconButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.ink),
            icon: const Icon(Icons.timer_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _FocusScreen())),
          ),
        ],
      ),
    );

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [header, Expanded(child: _pages[_index].page)]),
      ),
    );

    final plus = _PlusButton(onPressed: () => showQuickLog(context));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: AppColors.bg,
                    indicatorColor: AppColors.orange,
                    leading: Padding(padding: const EdgeInsets.only(top: 8, bottom: 16), child: plus),
                    destinations: [
                      for (final (i, p) in _pages.indexed)
                        NavigationRailDestination(
                          icon: p.icon(i == _index ? Colors.white : AppColors.muted),
                          label: Text(p.label),
                        ),
                    ],
                  ),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: const ShapeDecoration(color: AppColors.card, shape: StadiumBorder()),
                  child: Row(
                    children: [
                      for (final (i, p) in _pages.indexed) ...[
                        if (i == 2) plus,
                        Expanded(
                          child: _NavItem(
                            key: ValueKey('nav-${p.label}'),
                            icon: p.icon,
                            label: p.label,
                            selected: i == _index,
                            onTap: () => setState(() => _index = i),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The + in the middle of the bar: say or write anything into the diary.
class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Log an entry',
    child: Material(
      key: const ValueKey('nav-plus'),
      color: AppColors.orange,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1)],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    ),
  );
}

/// The focus timer, opened from the button at the top of every page.
class _FocusScreen extends StatelessWidget {
  const _FocusScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Focus')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: const FocusPage()),
          ),
        ),
      );
}

/// A tab in the floating bar: an icon, with its label under it when chosen.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget Function(Color color) icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: ShapeDecoration(
              color: selected ? AppColors.orange.withValues(alpha: 0.18) : Colors.transparent,
              shape: const StadiumBorder(),
            ),
            child: icon(selected ? AppColors.orange : AppColors.muted),
          ),
          ExcludeSemantics(
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
