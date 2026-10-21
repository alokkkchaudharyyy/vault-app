import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  group('reads bank and UPI messages', () {
    test('UPI debit to a merchant VPA', () {
      final p = parseBankSms('AD-HDFCBK-S',
          'Rs.250.00 debited from A/c XX1234 on 22-10-26 to VPA swiggy.stores@axisbank (UPI Ref No 629512345678). Not you? Call 18002586161')!;
      expect(p.amount, 25000);
      expect(p.direction, Expense.out);
      expect(p.merchant, 'Swiggy Stores');
      expect(p.account, 'HDFC ••1234');
    });

    test('HDFC "Sent" format with the name on its own line', () {
      final p = parseBankSms('VM-HDFCBK',
          'Sent Rs.1,200.00\nFrom HDFC Bank A/C *5678\nTo RAHUL SHARMA\nOn 22/10/26\nRef 629511112222\nNot You?')!;
      expect(p.amount, 120000);
      expect(p.merchant, 'Rahul Sharma');
    });

    test('card spend at a merchant', () {
      final p = parseBankSms('JD-ICICIB', 'INR 3,499.00 spent using ICICI Bank Card XX9012 on 22-Oct-26 on AMAZON PAY IN. Avl Limit: INR 45,000.00')!;
      expect(p.amount, 349900);
      expect(p.direction, Expense.out);
      expect(p.account, 'ICICI ••9012');
    });

    test('money received is "in"', () {
      final p = parseBankSms('BZ-SBIUPI', 'Dear UPI user A/C X4321 credited by Rs 5,000.00 on 22Oct26 by rahul.s@okaxis (Ref no 1234)')!;
      expect(p.direction, Expense.into);
      expect(p.amount, 500000);
    });

    test('ignores OTPs, offers, reminders, failures and personal numbers', () {
      expect(parseBankSms('AD-HDFCBK', '123456 is your OTP for txn of Rs 500 at Amazon'), isNull);
      expect(parseBankSms('AD-HDFCBK', 'Your credit card bill of Rs 4,500 is due on 05-Nov'), isNull);
      expect(parseBankSms('AD-BAJAJF', 'Pre-approved loan of Rs 2,00,000 credited instantly! Apply now'), isNull);
      expect(parseBankSms('AD-SBIUPI', 'Your UPI txn of Rs 300 to zomato@icici failed'), isNull);
      expect(parseBankSms('+919876543210', 'Rs 500 debited from your account'), isNull);
      expect(parseBankSms('AD-HDFCBK', 'Rs 499 will be debited on 01-Nov for your Netflix mandate'), isNull);
    });
  });

  test('categories come from the merchant', () {
    expect(guessCategory('Swiggy Stores'), Categories.food);
    expect(guessCategory('Uber India'), Categories.transport);
    expect(guessCategory('Netflix'), Categories.subscriptions);
    expect(guessCategory('Rahul Sharma'), Categories.other);
  });

  test('rupees groups the Indian way', () {
    expect(rupees(12345678), '₹1,23,456.78');
    expect(rupees(25000), '₹250');
  });

  group('store', () {
    late Store store;
    setUp(() => store = Store(openMemoryDb()));

    final msg = (
      sender: 'AD-HDFCBK',
      body: 'Rs.250.00 debited from A/c XX1234 on 22-10-26 to VPA swiggy.stores@axisbank (UPI Ref No 1)',
      at: DateTime(2026, 10, 22, 13, 5),
    );

    test('reading the same message twice stores it once, and a deleted one stays gone', () {
      expect(store.importSms([msg]), 1);
      expect(store.importSms([msg]), 0);
      store.deleteExpense(store.expenses().single.id);
      expect(store.importSms([msg]), 0);
      expect(store.expenses(), isEmpty);
    });

    test('a category chosen for a merchant sticks for its next payments', () {
      store.importSms([msg]);
      store.setExpenseCategory(store.expenses().single.id, Categories.fun);
      store.importSms([(sender: msg.sender, body: msg.body.replaceAll('250', '300'), at: DateTime(2026, 10, 23))]);
      expect(store.expenses().map((e) => e.category).toSet(), {Categories.fun});
    });

    test('a month sums by category; steady monthly payments are recurring', () {
      for (final (i, m) in ['2026-08', '2026-09', '2026-10'].indexed) {
        store.addExpense(amount: 64900, merchant: 'Netflix', at: DateTime.parse('$m-05 10:00'));
        store.addExpense(amount: 10000 * (i + 1), merchant: 'Zomato', at: DateTime.parse('$m-0${i + 2} 20:00'));
      }
      final s = store.moneySummary('2026-10');
      expect(s.spent, 64900 + 30000);
      expect(s.byCategory.first, (Categories.subscriptions, 64900));
      expect(store.recurring(months: 6).map((r) => r.merchant), ['Netflix']);
    });
  });
}
