import 'package:flutter/material.dart';

import 'sync_page.dart';
import 'theme.dart';

/// Local meta key: set once the welcome has been seen on this device.
const welcomedKey = 'welcomed';

/// What Vault is, shown once on a new device.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget point(IconData icon, Color color, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 14,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(icon, color: color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(body, style: t.bodyMedium?.copyWith(color: AppColors.muted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              children: [
                Text(
                  'G.ONE',
                  style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: AppColors.orange),
                ),
                const SizedBox(height: 6),
                Text(
                  'A private second brain that your agents share.',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 32),
                point(
                  Icons.mic_rounded,
                  AppColors.orange,
                  'Say or write anything',
                  'Your diary takes it any time: what you did, what you have to do, ideas, how the day went. '
                      'Speech is written down on the phone; nothing you say leaves it.',
                ),
                point(
                  Icons.psychology_rounded,
                  AppColors.lavender,
                  'It becomes your memory',
                  'Every night your agent files it into your notes (you, your goals, projects, people, what you '
                      'learned) and turns what you committed to into tasks.',
                ),
                point(
                  Icons.wb_sunny_rounded,
                  AppColors.cream,
                  'And a plan you can keep',
                  'Each morning: a page with your day, built around when you really wake and what really fits, '
                      'with your routines protected.',
                ),
                point(
                  Icons.hub_rounded,
                  AppColors.green,
                  'Shared by your agents',
                  'Claude Code, Codex and any MCP agent read the same notes and the same plan, so none of them '
                      'starts from zero. Your data stays on your devices, your server and your own git repository.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                  child: Text.rich(
                    TextSpan(
                      style: t.bodyMedium?.copyWith(height: 1.4),
                      children: const [
                        TextSpan(text: 'On your laptop, run '),
                        TextSpan(
                          text: 'myvault init',
                          style: TextStyle(fontFamily: 'monospace', color: AppColors.orange),
                        ),
                        TextSpan(text: ' to set up your notes and agents. Then connect this phone with sync.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('welcome-start'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: onDone,
                  child: const Text('Start'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('welcome-sync'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncPage()));
                    onDone();
                  },
                  child: const Text('Connect sync'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
