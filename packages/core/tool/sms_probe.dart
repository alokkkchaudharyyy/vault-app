import 'dart:io';
import 'package:vault_core/vault_core.dart';

/// Reads an `adb shell content query --uri content://sms/inbox` dump into a
/// scratch store and prints the months it makes, to check the reading of
/// bank messages against real ones.
void main(List<String> args) {
  final text = File(args[0]).readAsStringSync();
  final rows = RegExp(r'Row: \d+ address=(.*?), date=(\d+), body=([\s\S]*?)(?=\nRow: \d+ address=|$)').allMatches(text);
  final store = Store(openMemoryDb());
  store.importSms([
    for (final r in rows.toList().reversed)
      (sender: r.group(1)!, body: r.group(3)!, at: DateTime.fromMillisecondsSinceEpoch(int.parse(r.group(2)!))),
  ]);
  print('own names: ${store.ownNames}');
  for (final month in args.skip(1)) {
    final s = store.moneySummary(month);
    print('\n== $month spent ${rupees(s.spent)} received ${rupees(s.received)} own left out ${s.ownTransfers}');
    for (final (c, v) in s.byCategory) print('${rupees(v).padLeft(12)}  $c');
    for (final e in s.items) {
      print('  ${e.date} ${e.spent ? '-' : '+'}${rupees(e.amount).padLeft(10)} ${e.category.padRight(13)} ${e.merchant} · ${e.account}');
    }
  }
}
