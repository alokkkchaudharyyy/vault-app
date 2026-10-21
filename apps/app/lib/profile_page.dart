import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'brain_page.dart';
import 'collections_page.dart';
import 'habits_page.dart';
import 'health_page.dart';
import 'money_page.dart';
import 'screen_page.dart';
import 'screenshots_page.dart';
import 'state.dart';
import 'sync_page.dart';
import 'theme.dart';
import 'voice.dart';
import 'voice_sheet.dart';

/// You, and how Vault is set up: what your notes say about you, your habits,
/// screen time, sync, the calendar and voice.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  /// The name `Me.md` gives ("Call me Sam."), if the laptop published it.
  static String? nameFrom(VaultPage? me) =>
      me == null ? null : RegExp(r'Call me ([^.\n]+)\.').firstMatch(me.body)?.group(1)?.trim();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final me = app.store.page('me');
    final name = nameFrom(me);
    final email = app.remote.email;
    final habits = app.store.habits().length;
    final goals = app.store.page('goals')?.body.split('\n').where((g) => g.trim().isNotEmpty).length ?? 0;

    Future<void> open(String title, Widget body) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
            ),
          ),
        ),
      ),
    );

    Widget tile(String key, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) => Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('profile-$key'),
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.16),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: t.bodySmall?.copyWith(color: AppColors.muted)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        onTap: onTap,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              spacing: 16,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.orange,
                  child: Text(
                    (name ?? email ?? 'You').characters.first.toUpperCase(),
                    style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(name ?? 'You', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        email ?? 'Not syncing: everything stays on this phone',
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                      Text(
                        '$goals ${goals == 1 ? 'goal' : 'goals'} · $habits ${habits == 1 ? 'habit' : 'habits'}',
                        style: t.labelMedium?.copyWith(color: AppColors.lavender),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        tile(
          'info',
          Icons.badge_rounded,
          AppColors.orange,
          'About you',
          me == null ? 'From Me.md in your notes, after your laptop syncs' : 'What your agents know about you, from Me.md',
          () => me == null
              ? open(
                  'About you',
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'This is Me.md from your notes: your goals, how you like your days, what your agents '
                      'should know. On your laptop, run `myvault init`, then `myvault sync`, and it shows up here.',
                    ),
                  ),
                )
              : openPage(context, me),
        ),
        const SizedBox(height: 8),
        tile(
          'habits',
          Icons.grid_view_rounded,
          AppColors.green,
          'Habits',
          'Things you do every day, at a set time or not, with streaks',
          () => open('Habits', const HabitsPage()),
        ),
        const SizedBox(height: 8),
        tile(
          'screen',
          Icons.phone_android_rounded,
          AppColors.lavender,
          'Screen time',
          'Which apps, how long and when, on the phone and the laptop',
          () => open('Screen time', const ScreenPage()),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 8),
          tile(
            'money',
            Icons.account_balance_wallet_rounded,
            AppColors.cream,
            'Money',
            'Spending from bank and UPI messages, budget and subscriptions',
            () => open('Money', const MoneyPage()),
          ),
        ],
        const SizedBox(height: 8),
        tile(
          'health',
          Icons.favorite_rounded,
          AppColors.red,
          'Health',
          'Sleep, steps, water, weight and workouts',
          () => open('Health', const HealthPage()),
        ),
        const SizedBox(height: 8),
        tile(
          'collections',
          Icons.collections_bookmark_rounded,
          AppColors.orange,
          'Collections',
          'Places, recipes, watchlist, wishlist: what you shared or kept',
          () => open('Collections', const CollectionsPage()),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 8),
          tile(
            'screenshots',
            Icons.photo_library_rounded,
            AppColors.green,
            'Screenshots',
            'Swipe right to keep (its text goes to your diary), left to delete',
            () => open('Screenshots', const ScreenshotsPage()),
          ),
        ],
        const SizedBox(height: 8),
        tile(
          'sync',
          app.remote.signedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          AppColors.cream,
          'Sync',
          app.remote.signedIn ? 'Signed in; your laptop and phone share everything' : 'Off: connect your own server',
          () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncPage())),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 8),
          tile(
            'calendar',
            Icons.calendar_month_rounded,
            AppColors.red,
            'Calendar',
            'Mirror timed tasks into a calendar of your choice',
            () => open(
              'Calendar',
              ListView(padding: const EdgeInsets.all(16), children: const [CalendarSection()]),
            ),
          ),
        ],
        if (voiceSupported) ...[
          const SizedBox(height: 8),
          tile(
            'voice',
            Icons.settings_voice_rounded,
            AppColors.orange,
            'Voice',
            'How speech becomes text, on this device',
            () => showVoiceSettings(context),
          ),
        ],
        const SizedBox(height: 24),
        Center(
          child: Text(
            'G.ONE · a private second brain your agents share',
            style: t.labelSmall?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
