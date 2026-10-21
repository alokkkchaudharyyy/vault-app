
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';

import 'calendar_sync.dart';
import 'state.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  final _key = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _filled = false;

  /// The server's address and key are being entered or changed.
  bool _editServer = false;

  @override
  void dispose() {
    for (final c in [_email, _password, _url, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signIn(AppState app) async {
    if (_editServer) {
      final url = _url.text.trim(), key = _key.text.trim();
      if (!url.startsWith('https://') || key.isEmpty) {
        return setState(() => _error = 'Give the project URL (it starts with https://) and its publishable key.');
      }
      app.remote.configure(url: url, anonKey: key);
    }
    setState(() {
      _busy = true;
      _error = null;
      _editServer = false;
    });
    try {
      await app.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      _password.clear();
    } catch (e) {
      _error = e.toString().startsWith('ClientException') || e.toString().startsWith('SocketException')
          ? 'Could not reach the server. Check your connection.'
          : e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    if (!_filled) {
      _filled = true;
      _email.text = app.remote.email ?? '';
      _url.text = app.remote.url ?? '';
      _editServer = !app.remote.configured;
    }

    final List<Widget> children;
    if (app.remote.signedIn) {
      final last = app.lastSync;
      children = [
        Text('Signed in as ${app.remote.email ?? 'your account'}', style: theme.textTheme.titleMedium),
        Text(
          app.syncError ??
              (app.syncing
                  ? 'Syncing…'
                  : last == null
                      ? 'Not synced yet in this session.'
                      : 'Last synced at ${TimeOfDay.fromDateTime(last).format(context)}.'),
          style: TextStyle(color: app.syncError == null ? null : theme.colorScheme.error),
        ),
        Row(
          spacing: 12,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
              onPressed: app.syncing ? null : app.sync,
            ),
            TextButton(onPressed: app.signOut, child: const Text('Sign out')),
          ],
        ),
        const Text('Signing out keeps everything on this device; it only stops syncing.'),
      ];
    } else {
      children = [
        const Text(
          'Everything works without signing in. Sign in to sync this device with your others.',
        ),
        if (_editServer) ...[
          const Text(
            'Sync goes through a Supabase project of your own. Its address and publishable key are under '
            'Project Settings in the Supabase dashboard; the README explains how to set one up.',
          ),
          TextField(
            key: const ValueKey('sync-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co'),
          ),
          TextField(
            key: const ValueKey('sync-key'),
            controller: _key,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Publishable key'),
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: Text(
                  'Server: ${Uri.tryParse(app.remote.url ?? '')?.host ?? app.remote.url}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: () => setState(() => _editServer = true), child: const Text('Change')),
            ],
          ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _signIn(app),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : () => _signIn(app),
            child: Text(_busy ? 'Signing in…' : 'Sign in'),
          ),
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone only: choose the calendar that timed tasks are mirrored into.
class CalendarSection extends StatefulWidget {
  const CalendarSection({super.key});

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<CalendarSection> {
  List<Calendar>? _calendars;

  Future<void> _load(CalendarSync sync) async {
    final calendars = await sync.writableCalendars();
    if (mounted) setState(() => _calendars = calendars);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final sync = CalendarSync(app.store);
    final calendars = _calendars;
    if (calendars == null && sync.calendarId != null) _load(sync);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const Divider(),
        Text('Calendar', style: theme.textTheme.titleMedium),
        const Text(
          'Tasks with a time appear as events in the calendar you pick, and moving or renaming '
          'one of those events there updates the task. Other events are never touched.',
        ),
        if (calendars == null)
          OutlinedButton(
            onPressed: () => _load(sync),
            child: Text(sync.calendarId == null ? 'Choose a calendar' : 'Loading calendars…'),
          )
        else if (calendars.isEmpty)
          const Text('No calendar available. Allow calendar access for G.ONE in system settings.')
        else
          RadioGroup<String?>(
            groupValue: calendars.any((c) => c.id == sync.calendarId) ? sync.calendarId : null,
            onChanged: (id) {
              setState(() => sync.calendarId = id);
              app.sync();
            },
            child: Column(
              children: [
                const RadioListTile<String?>(value: null, title: Text('Off')),
                for (final c in calendars)
                  RadioListTile<String?>(
                    value: c.id,
                    title: Text(c.name),
                    subtitle: c.accountName == null ? null : Text(c.accountName!),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
