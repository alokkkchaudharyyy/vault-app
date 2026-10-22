import 'package:flutter/services.dart';
import 'package:vault_core/vault_core.dart';

/// Reading the phone for G.ONE's money and health: bank and UPI messages,
/// and Health Connect. Only what is parsed out (an amount and a merchant,
/// steps, hours slept) is stored and synced; the messages themselves never
/// leave the phone.
const sms = MethodChannel('todo/sms');
const healthConnect = MethodChannel('todo/health');

const _smsSinceKey = 'sms_since';

/// False where the phone side is missing (the Linux app, tests).
Future<bool> _ask(MethodChannel channel, String method) async {
  try {
    return await channel.invokeMethod<bool>(method) ?? false;
  } on MissingPluginException {
    return false;
  }
}

Future<bool> hasSmsAccess() => _ask(sms, 'hasAccess');
Future<bool> requestSmsAccess() => _ask(sms, 'requestAccess');

Future<bool> healthAvailable() => _ask(healthConnect, 'available');
Future<bool> hasHealthAccess() => _ask(healthConnect, 'hasAccess');
Future<bool> requestHealthAccess() => _ask(healthConnect, 'requestAccess');
Future<void> openHealthSettings() async {
  try {
    await healthConnect.invokeMethod('openSettings');
  } on MissingPluginException {
    // Not a phone.
  }
}

/// Raised when the reading of messages improves, so the last 90 days are read
/// again.
const _smsReader = '2';
const _smsReaderKey = 'sms_reader';

/// Stores payments from messages received since the last read (the last 90
/// days the first time, or after the reader improved). Returns how many were
/// new.
Future<int> collectSms(Store store) async {
  if (!await hasSmsAccess()) return 0;
  final refresh = store.getMeta(_smsReaderKey) != _smsReader;
  final since = (refresh ? null : int.tryParse(store.getMeta(_smsSinceKey) ?? '')) ??
      DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
  final rows = await sms.invokeListMethod<Map<Object?, Object?>>('inbox', {'since': since}) ?? const [];
  final added = store.importSms([
    for (final r in rows)
      (
        sender: r['sender'] as String,
        body: r['body'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((r['date'] as num).toInt()),
      ),
  ], refresh: refresh);
  if (rows.isNotEmpty) store.setMeta(_smsSinceKey, '${(rows.last['date'] as num).toInt()}');
  store.setMeta(_smsReaderKey, _smsReader);
  return added;
}

/// Copies the last week's steps and sleep from Health Connect.
Future<void> collectHealth(Store store) async {
  if (!await hasHealthAccess()) return;
  final days = await healthConnect.invokeListMethod<Map<Object?, Object?>>(
        'days',
        {'from': addDays(today(), -7), 'to': today()},
      ) ??
      const [];
  for (final d in days) {
    final date = d['date'] as String;
    if (d['steps'] case final num steps) store.setHealth(date, HealthKind.steps, steps.toDouble());
    if (d['sleep'] case final num minutes) {
      store.setHealth(date, HealthKind.sleep, minutes.toDouble(), detail: d['sleepDetail'] as String?);
    }
  }
}
