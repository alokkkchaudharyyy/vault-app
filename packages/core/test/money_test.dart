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
      expect(parseBankSms('JX-RZRPAY-S', 'Settlement worth ₹ 997.96 for Razorpay MID X has been processed. It will be credited in your bank account before 9 PM today!'), isNull);
      expect(parseBankSms('AD-CANBNK-S', 'Dear Customer, auto pay facility has been successfully activated on your Canara Bank Card XX7967 for INR 200000.00'), isNull);
    });

    test('numbers with hidden characters in them', () {
      final p = parseBankSms('BT-SLCBNK-S', 'You transferred Rs. 1,‌00,‌000 from nexera new to slice xx2074 savings successfully.')!;
      expect(p.amount, 10000000);
      expect(saysOwnTransfer('You transferred Rs. 50 from nexera new to slice xx2074 savings successfully.'), isTrue);
    });

    test('slice and Canara formats name who was paid', () {
      final sent = parseBankSms('BT-SLCBNK-S', 'Rs. 3,200 sent from a/c xx2074 on 18-Oct-26 to RADHIKA (UPI Ref: 629164942598). Not you? Call 08048329999 - slice')!;
      expect(sent.merchant, 'Radhika');
      expect(sent.toPerson, isTrue);
      final card = parseBankSms('AX-CANBNK-S', 'CardTxn:A/C XXX149 Dr INR 406.00 on 11/10/26 13:14 to PHP*MEESHOT;RRN:628413042114;Bal INR 33,901.34. If fraud,SMS SUSPECT to 56161')!;
      expect(card.merchant, 'Meeshot');
      expect(card.toPerson, isFalse);
      final neft = parseBankSms('AD-CANBNK-S', 'An amount of INR 997.96 has been credited to XXX149 on 17/10/2026 towards NEFT by Sender RAZORPAY PAYMENTS PVT LTD PAYM, IFSC UTIB0001506, Sender A/c XXXX6002, AXIS BANK')!;
      expect(neft.merchant, 'Razorpay Payments');
      expect(neft.account, 'Canara ••149');
      final pos = parseBankSms('AX-CANBNK-S', 'A/c XXX149 linked to card  debited INR 2,399.00 on 20/09/26 POS txn. Avl Bal INR 43,610.75. To stop further debit SMS SUSPECT to 56161')!;
      expect(pos.merchant, isNull);
      final autopay = parseBankSms('BG-SLCBNK-S', 'Successfully paid Rs.89 from slice a/c XX2074 to Google on 15-Oct-26 via UPI AutoPay. UMN - e500a9df598447858db4ebe3430dc697@slc - slice')!;
      expect(autopay.merchant, 'Google');
    });
  });

  test('categories come from the merchant', () {
    expect(guessCategory('Swiggy Stores'), Categories.food);
    expect(guessCategory('Uber India'), Categories.transport);
    expect(guessCategory('Netflix'), Categories.subscriptions);
    expect(guessCategory('Rahul Sharma'), Categories.other);
    // Short hints are whole words.
    expect(guessCategory('Slice Small', 'Not you? Call 080 - slice'), Categories.other);
    expect(guessCategory('Arvind Kumar', 'received via UPI'), Categories.other);
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

  group('own transfers', () {
    late Store store;
    setUp(() => store = Store(openMemoryDb()));

    test('money leaving one account and arriving in another is left out of the totals', () {
      final at = DateTime(2026, 10, 22, 10);
      store.importSms([
        (sender: 'AD-HDFCBK', body: 'Rs.10,000.00 debited from A/c XX1234 to VPA alok.c@oksbi (UPI Ref 1)', at: at),
        (sender: 'AD-SBIUPI', body: 'Your A/C X9876 credited by Rs 10,000.00 by alok.c@okhdfcbank (Ref 1)', at: at.add(const Duration(minutes: 1))),
        (sender: 'AD-HDFCBK', body: 'Rs.300.00 debited from A/c XX1234 to VPA zomato@icici (UPI Ref 2)', at: at),
      ]);
      final s = store.moneySummary('2026-10');
      expect(s.spent, 30000);
      expect(s.received, 0);
      expect(s.ownTransfers, 2);
    });

    test('a friend paying back into the same account is not an own transfer', () {
      final at = DateTime(2026, 10, 22, 10);
      store.importSms([
        (sender: 'AD-HDFCBK', body: 'Rs.500.00 debited from A/c XX1234 to VPA rahul.s@okaxis (UPI Ref 1)', at: at),
        (sender: 'AD-HDFCBK', body: 'A/c XX1234 credited with Rs.500.00 from rahul.s@okaxis (UPI Ref 2)', at: at.add(const Duration(minutes: 30))),
      ]);
      expect(store.moneySummary('2026-10').ownTransfers, 0);
    });

    test('"to self" in the message is enough, and marking a payee sticks', () {
      store.importSms([
        (sender: 'AD-ICICIB', body: 'Rs 2,000 debited from A/c XX5555 to self via IMPS Ref 9', at: DateTime(2026, 10, 1)),
        (sender: 'AD-HDFCBK', body: 'Rs.700.00 debited from A/c XX1234 to VPA alokpaytm@paytm (UPI Ref 3)', at: DateTime(2026, 10, 2)),
      ]);
      final paytm = store.expenses().firstWhere((e) => e.merchant == 'Alokpaytm');
      store.setExpenseCategory(paytm.id, Categories.own);
      store.importSms([
        (sender: 'AD-HDFCBK', body: 'Rs.900.00 debited from A/c XX1234 to VPA alokpaytm@paytm (UPI Ref 4)', at: DateTime(2026, 10, 9)),
      ]);
      final s = store.moneySummary('2026-10');
      expect(s.spent, 0);
      expect(s.ownTransfers, 3);
    });

    test("the user's own name is learned, and payments to it are own transfers", () {
      final messages = [
        for (final (i, day) in [3, 5, 18].indexed) ...[
          (
            sender: 'BT-SLCBNK-S',
            body: 'Rs. ${1000 + i} sent from a/c xx2074 on $day-Oct-26 to ALOK CHAUDHARY (UPI Ref: 1$i). Not you? - slice',
            at: DateTime(2026, 10, day, 10),
          ),
          (
            sender: 'AD-CANBNK-S',
            body: 'Dear Customer, Acct XXX149 credited with INR ${1000 + i}.00 on $day/10/26 from ALOK CHAUDHA; UPI:1$i; Bal INR 5.00-CanaraBank',
            at: DateTime(2026, 10, day, 10, 1),
          ),
        ],
        (
          sender: 'AD-CANBNK-S',
          body: 'Dear Customer, Acct XXX149 Dr. INR 864.00 on 13/10/26 to ALOK CHAUDHA; UPI: 9; Bal INR 5.00.Not you?',
          at: DateTime(2026, 10, 13),
        ),
        (
          sender: 'BG-SLCBNK-S',
          body: 'Rs. 500 sent from a/c xx2074 on 20-Oct-26 to PIHU (UPI Ref: 8). Not you? - slice',
          at: DateTime(2026, 10, 20),
        ),
      ];
      store.importSms(messages);
      expect(store.ownNames, ['alok chaudhary']);
      final s = store.moneySummary('2026-10');
      expect(s.spent, 50000);
      expect(s.byCategory, [(Categories.people, 50000)]);
    });

    test('refresh reads stored messages again', () {
      final m = (sender: 'AD-SLCBNK-S', body: 'Rs. 135 spent on your credit card xx1093 at Neetu medicos on 19-Oct-26 (UPI Ref: 6). - slice', at: DateTime(2026, 10, 19));
      store.importSms([m]);
      final id = store.expenses().single.id;
      store.setExpenseCategory(id, Categories.fun, remember: false);
      expect(store.importSms([m]), 0);
      expect(store.expense(id)!.category, Categories.fun);
      store.importSms([m], refresh: true);
      expect(store.expense(id)!.category, Categories.health);
    });
  });
}
