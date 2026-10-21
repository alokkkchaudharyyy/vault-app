import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/health_page.dart';
import 'package:vault_app/money_page.dart';
import 'package:vault_app/state.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  Widget host(AppState state, Widget page) =>
      AppScope(state: state, child: MaterialApp(home: Scaffold(body: page)));

  testWidgets('Money shows the month total and each payment', (tester) async {
    final state = AppState(Store(openMemoryDb()));
    state.store.importSms([
      (
        sender: 'AD-HDFCBK',
        body: 'Rs.250.00 debited from A/c XX1234 to VPA swiggy.stores@axisbank (UPI Ref No 1)',
        at: DateTime.now(),
      ),
    ]);
    await tester.pumpWidget(host(state, const MoneyPage()));
    await tester.pump();
    expect(find.text('₹250'), findsWidgets);
    expect(find.text('−₹250'), findsOneWidget);
    expect(find.text('Swiggy Stores'), findsOneWidget);
    expect(find.text('Food'), findsWidgets);
  });

  testWidgets('Health adds a glass of water', (tester) async {
    final state = AppState(Store(openMemoryDb()));
    await tester.pumpWidget(host(state, const HealthPage()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('water-add')));
    await tester.pump();
    expect(find.text('250 ml'), findsOneWidget);
  });
}
