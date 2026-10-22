import 'dart:convert';

import 'dates.dart';
import 'store.dart';

/// Money in and out. Most rows come from the bank and UPI text messages the
/// phone receives; the rest are typed in (cash). Amounts are in paise.
class Expense {
  Expense.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        at = DateTime.parse(r['at'] as String),
        date = r['date'] as String,
        amount = r['amount'] as int,
        direction = r['direction'] as String,
        merchant = r['merchant'] as String?,
        category = r['category'] as String? ?? Categories.other,
        account = r['account'] as String?,
        source = r['source'] as String?,
        note = r['note'] as String?;

  final String id;
  final DateTime at;
  final String date;

  /// Paise, always positive; [direction] says which way.
  final int amount;

  /// [out] or [into].
  final String direction;
  final String? merchant;
  final String category;

  /// "HDFC ••1234", when the message said.
  final String? account;

  /// 'sms' or 'manual'.
  final String? source;
  final String? note;

  static const out = 'out';
  static const into = 'in';

  bool get spent => direction == out;

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'date': date,
        'amount': rupees(amount),
        'direction': direction,
        if (merchant != null) 'merchant': merchant,
        'category': category,
        if (account != null) 'account': account,
        if (note != null) 'note': note,
      };
}

/// "₹1,234.50" style text for [paise].
String rupees(int paise) {
  final whole = paise ~/ 100, rest = paise % 100;
  final digits = whole.toString();
  // Indian grouping: 12,34,567.
  final buf = StringBuffer();
  if (digits.length <= 3) {
    buf.write(digits);
  } else {
    final head = digits.substring(0, digits.length - 3);
    for (var i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 2 == 0) buf.write(',');
      buf.write(head[i]);
    }
    buf.write(',${digits.substring(digits.length - 3)}');
  }
  return '₹$buf${rest == 0 ? '' : '.${rest.toString().padLeft(2, '0')}'}';
}

abstract final class Categories {
  static const food = 'Food';
  static const groceries = 'Groceries';
  static const transport = 'Transport';
  static const shopping = 'Shopping';
  static const bills = 'Bills';
  static const subscriptions = 'Subscriptions';
  static const health = 'Health';
  static const fun = 'Fun';
  static const education = 'Education';
  static const transfers = 'Transfers';

  /// Money sent to friends and family over UPI.
  static const people = 'People';

  /// Money moved between the user's own accounts: neither spent nor
  /// received, so it is left out of every total.
  static const own = 'Own transfer';
  static const other = 'Other';

  static const all = [food, groceries, transport, shopping, bills, subscriptions, health, fun, education, people, transfers, own, other];
}

const _categoryHints = <String, List<String>>{
  Categories.food: [
    'swiggy', 'zomato', 'eatsure', 'dominos', 'domino', 'pizza', 'mcdonald', 'kfc', 'burger', 'starbucks', 'cafe',
    'restaurant', 'chai', 'tea', 'coffee', 'canteen', 'mess', 'sweets', 'juice', 'bakery', 'dhaba', 'food', 'biryani', 'haldiram', 'subway',
  ],
  Categories.groceries: [
    'blinkit', 'zepto', 'instamart', 'bigbasket', 'jiomart', 'dmart', 'grofers', 'kirana', 'supermarket', 'grocery',
    'fresh', 'milk', 'dairy', 'more retail', 'reliance smart',
  ],
  Categories.transport: [
    'uber', 'ola', 'rapido', 'irctc', 'metro', 'redbus', 'indigo', 'airindia', 'akasa', 'spicejet', 'fastag',
    'petrol', 'fuel', 'transport', 'ncrtc', 'dmrc', 'auto', 'hpcl', 'iocl', 'bpcl', 'indian oil', 'parking', 'yulu', 'namma yatri', 'makemytrip', 'cleartrip',
  ],
  Categories.shopping: [
    'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq', 'croma', 'decathlon', 'ikea',
    'lenskart', 'reliance digital', 'shoppers stop', 'zudio', 'westside', 'h&m', 'uniqlo', 'shopping', 'store', 'mart',
  ],
  Categories.bills: [
    'electricity', 'bescom', 'tneb', 'msedcl', 'tata power', 'adani', 'bill', 'recharge', 'jio', 'airtel', 'vodafone',
    'vi', 'bsnl', 'broadband', 'act fibernet', 'gas', 'water', 'rent', 'maintenance', 'insurance', 'lic',
  ],
  Categories.subscriptions: [
    'netflix', 'spotify', 'prime', 'hotstar', 'jiocinema', 'youtube', 'google play', 'apple', 'icloud', 'chatgpt',
    'openai', 'anthropic', 'claude', 'notion', 'github', 'zee5', 'sonyliv', 'linkedin', 'canva', 'subscription',
    'google', 'microsoft', 'godaddy', 'render', 'vercel', 'bunny', 'hostinger', 'aws', 'digitalocean', 'cloudflare',
    'kukufm', 'audible', 'autopay',
  ],
  Categories.health: ['pharmacy', 'apollo', '1mg', 'pharmeasy', 'netmeds', 'hospital', 'clinic', 'medical', 'medicos', 'medico', 'chemist', 'gym', 'cult', 'doctor', 'lab'],
  Categories.fun: ['bookmyshow', 'pvr', 'inox', 'cinepolis', 'steam', 'playstation', 'district', 'paytm insider', 'concert'],
  Categories.education: ['udemy', 'coursera', 'byju', 'unacademy', 'physicswallah', 'college', 'university', 'school', 'fees', 'books'],
};

/// The category [merchant] and the message most likely belong in.
String guessCategory(String? merchant, [String text = '']) {
  final hay = ' ${merchant ?? ''} $text '.toLowerCase().replaceAll(RegExp(r'[^a-z0-9&]+'), ' ');
  for (final MapEntry(key: c, value: words) in _categoryHints.entries) {
    // Short hints are whole words ("lic" is not in "slice", "vi" not in
    // "via"); longer ones start a word ("swiggy" is in "swiggyinstamart").
    if (words.any((w) => hay.contains(w.length <= 4 ? ' $w ' : ' $w'))) return c;
  }
  return Categories.other;
}

/// One expense read from a text message, before it is stored.
class ParsedSms {
  const ParsedSms({
    required this.amount,
    required this.direction,
    this.merchant,
    this.account,
    this.toPerson = false,
  });

  final int amount;
  final String direction;
  final String? merchant;
  final String? account;

  /// Sent over UPI from a bank account rather than spent on a card: most
  /// often a person, sometimes a shop's QR code.
  final bool toPerson;
}

/// Bank codes in sender ids ("AD-HDFCBK-S") and their short names.
const _banks = {
  'HDFC': 'HDFC', 'SBI': 'SBI', 'ICICI': 'ICICI', 'AXIS': 'Axis', 'KOTAK': 'Kotak', 'PNB': 'PNB', 'BOI': 'BOI',
  'BOB': 'BoB', 'PAYTM': 'Paytm', 'IDFC': 'IDFC', 'YESB': 'Yes', 'INDUS': 'IndusInd', 'AUBANK': 'AU',
  'FEDBNK': 'Federal', 'CANBNK': 'Canara', 'UNION': 'Union', 'JIOPB': 'Jio', 'AIRBNK': 'Airtel', 'CITI': 'Citi',
  'SCB': 'StanChart', 'IOB': 'IOB', 'UCO': 'UCO', 'RBL': 'RBL', 'SLICE': 'slice', 'SLCBNK': 'slice', 'ONECARD': 'OneCard',
  'MOBIKW': 'MobiKwik',
};

final _amount = RegExp(r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
final _debit = RegExp(r'\b(debited|spent|paid|sent|withdrawn|purchase|debit|dr\b|txn of|used at|transferred)', caseSensitive: false);
final _credit = RegExp(r'\b(credited|received|deposited|refund(ed)?|cr\b|credit)\b', caseSensitive: false);
final _ownWords = RegExp(
  r'\b(to self|self[- ]transfer|own account|to your (?:own )?(?:a/?c|account)|between your accounts|'
  r'sweep|fd (?:booked|created|opened)|fixed deposit|transferred to your|you transferred|you added|from credit card|'
  r'repayment of|credited to your card)\b',
  caseSensitive: false,
);

/// Whether the message itself says the money moved between the user's own
/// accounts (or into their own deposit).
bool saysOwnTransfer(String body) => _ownWords.hasMatch(body);

final _skip = RegExp(
  r'\b(otp|one time password|is due|due on|due date|minimum amount|min\.? amt|offer|pre-?approved|loan|'
  r'cashback of upto|win |winner|failed|declined|unsuccessful|requested|request money|will be debited|'
  r'scheduled|mandate.*(created|registered)|statement|bill generated|e-?statement|avl limit only|reward points|'
  // A payout announced before it lands (the bank's own message follows),
  // a card limit set up, a pension contribution.
  r'will be credited|auto ?pay facility|activated|pran\b|contribution of)',
  caseSensitive: false,
);
final _account = RegExp(r'(?<!sender )(?:a/?c|acct|account|card|credited to)\s*(?:no\.?\s*)?(?:ending\s*(?:with\s*)?)?[x*•.]*\s*(\d{3,6})', caseSensitive: false);
// Not an email address: "fraudalerts@mobikwik.com".
final _vpa = RegExp(r'\b([a-z0-9][a-z0-9._-]{1,40})@[a-z]{2,20}\b(?!\.)', caseSensitive: false);

/// "You transferred Rs. 50 from nexera new to ..." names a pocket the user
/// owns.
final _ownPocket = RegExp(r'\byou transferred rs\.? [\d,.]+ from (.+?) to\b', caseSensitive: false);
final _party = RegExp(
  r'(?:\bto\b|\bat\b|\btowards\b|\bby\b|\bfrom\b|trf to|info:?)\s+(?:vpa\s+|upi\s+|a/c\s+)?'
  r"([A-Za-z][A-Za-z0-9 .&'_*+-]{1,60}?)"
  r'(?=\s+(?:on|ref|upi|via|txn|avl|bal|using|for|dated|thru|through|not)\b|\s*[(.,;\n]|$)',
  caseSensitive: false,
);
final _p2p = RegExp(r'\bsent from\b|\bdr\.? inr [\d,.]+ on [\d/]+ to .*; ?upi', caseSensitive: false);
final _business = RegExp(
  r'\b(services|online|india|tech|technologies|pvt|private|ltd|limited|enterprises?|traders|store|stores|mart|'
  r'solutions|retail|foods?|industries|corporation|company|co)\b',
  caseSensitive: false,
);
final _card = RegExp(r'credit card|cardtxn|debit card|\bcard xx', caseSensitive: false);
final _neftSender = RegExp(r'\bby sender\s+([A-Za-z][A-Za-z .&]{2,60}?)\s*(?:,|;|$)', caseSensitive: false);

/// Characters some banks put inside numbers: "Rs. 1,‌00,‌000".
final _invisible = RegExp('[​-‏⁠﻿]');

/// Reads a bank or UPI text message from [sender]; null when it is not a
/// completed payment (an OTP, an offer, a bill reminder, a failed payment).
ParsedSms? parseBankSms(String sender, String body) {
  body = body.replaceAll(_invisible, '');
  // People's numbers are not banks; that is how forwarded scams look.
  if (RegExp(r'^\+?\d{6,}$').hasMatch(sender.trim())) return null;
  if (_skip.hasMatch(body)) return null;
  final amountMatch = _amount.firstMatch(body);
  if (amountMatch == null) return null;
  final debit = _debit.firstMatch(body), credit = _credit.firstMatch(body);
  if (debit == null && credit == null) return null;
  final direction = credit == null || (debit != null && debit.start < credit.start) ? Expense.out : Expense.into;
  final amount = (double.parse(amountMatch.group(1)!.replaceAll(',', '')) * 100).round();
  if (amount <= 0) return null;

  final bank = _banks.entries.where((b) => sender.toUpperCase().contains(b.key)).firstOrNull?.value;
  final digits = _account.firstMatch(body)?.group(1);
  final account = [?bank, if (digits != null) '••${digits.length > 4 ? digits.substring(digits.length - 4) : digits}']
      .join(' ');

  return ParsedSms(
    amount: amount,
    direction: direction,
    merchant: _merchant(body, direction),
    account: account.isEmpty ? null : account,
    toPerson: direction == Expense.out && _p2p.hasMatch(body) && !_card.hasMatch(body) && !_business.hasMatch(body),
  );
}

String? _merchant(String body, String direction) {
  // NEFT in: "towards NEFT by Sender RAZORPAY PAYMENTS PVT LTD PAYM, IFSC".
  if (_neftSender.firstMatch(body) case final m?) return _clean(m.group(1)!);
  // A UPI id names the other side best: "swiggy.stores@axisbank".
  for (final m in _vpa.allMatches(body)) {
    final local = m.group(1)!;
    // Phone numbers and mandate ids ("e500a9df5984...@slc") name no one.
    if (RegExp(r'\d').allMatches(local).length > 3) continue;
    final name = local.replaceAll(RegExp(r'[._-]+'), ' ').replaceAll(RegExp(r'\d+'), ' ').trim();
    if (name.length >= 2) return _title(name);
  }
  // "To RAHUL S", "at AMAZON", "from ACME PAYROLL"; for money in, "by"/"from".
  for (final m in _party.allMatches(body)) {
    final word = body.substring(m.start, m.start + 4).toLowerCase();
    final isFrom = word.startsWith('from') || word.startsWith('by');
    if (direction == Expense.out && isFrom) continue;
    final name = m.group(1)!.trim();
    final lower = name.toLowerCase();
    if (lower.startsWith('your') || lower.contains('a/c') || lower.contains('account') || lower.contains('bank')) continue;
    // "linked to card debited INR 2,399.00": no one named.
    if (lower.startsWith('card') || RegExp(r'\b(debited|credited|inr|rs|sms|suspect|stop|call|dial)\b').hasMatch(lower)) continue;
    if (RegExp(r'^[x*]*\d').hasMatch(lower)) continue;
    if (_clean(name) case final clean?) return clean;
  }
  return null;
}

/// A readable name from what the bank wrote: "PHP*MEESHOT" is Meeshot,
/// "PAYTM120477" is Paytm, "RENDER.COM+" is Render, "RAZORPAY PAYMENTS PVT
/// LTD PAYM" is Razorpay Payments.
String? _clean(String raw) {
  final name = (raw.contains('*') ? raw.substring(raw.lastIndexOf('*') + 1) : raw)
      .replaceAll(RegExp(r'\.(com|in|co|io)\b.*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b(pvt|private|ltd|limited|lim|llp|inc)\b.*', caseSensitive: false), '')
      .replaceAll(RegExp(r'[+_]|\d{3,}'), ' ')
      .trim();
  return name.length < 2 ? null : _title(name);
}

String _title(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length <= 3 && w == w.toUpperCase() && w.length > 1 ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

/// A month of money, for the phone and for agents.
class MoneySummary {
  MoneySummary(this.month, this.items, this.budget);

  /// YYYY-MM.
  final String month;
  final List<Expense> items;

  /// Paise, if a monthly budget is set.
  final int? budget;

  /// Everything but money moved between the user's own accounts.
  Iterable<Expense> get counted => items.where((e) => e.category != Categories.own);

  /// How many own transfers the month had, left out of the totals.
  int get ownTransfers => items.length - counted.length;

  int get spent => counted.where((e) => e.spent).fold(0, (s, e) => s + e.amount);
  int get received => counted.where((e) => !e.spent).fold(0, (s, e) => s + e.amount);

  /// Spending by category, biggest first.
  List<(String, int)> get byCategory {
    final m = <String, int>{};
    for (final e in counted.where((e) => e.spent)) {
      m.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Spending by merchant, biggest first.
  List<(String, int)> get topMerchants {
    final m = <String, int>{};
    for (final e in counted.where((e) => e.spent && e.merchant != null)) {
      m.update(e.merchant!, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  Map<String, Object?> toJson({bool withItems = true}) => {
        'month': month,
        'spent': rupees(spent),
        'received': rupees(received),
        if (budget != null) 'budget': rupees(budget!),
        if (budget != null) 'budget_left': rupees(budget! - spent),
        'by_category': {for (final (c, v) in byCategory) c: rupees(v)},
        'top_merchants': {for (final (m, v) in topMerchants.take(8)) m: rupees(v)},
        if (ownTransfers > 0) 'own_transfers_left_out': ownTransfers,
        if (withItems) 'items': [for (final e in counted) e.toJson()],
      };
}

/// A payment that comes back each month: same merchant, similar amount.
class Recurring {
  Recurring(this.merchant, this.amount, this.months, this.category);

  final String merchant;
  final int amount;
  final int months;
  final String category;

  Map<String, Object?> toJson() =>
      {'merchant': merchant, 'amount': rupees(amount), 'months_seen': months, 'category': category};
}

const _rememberedKey = 'merchant_categories';
const _budgetKey = 'money_budget';
const _ownNamesKey = 'money_own_names';

/// Paying one of these is paying off a card or topping up a wallet the user
/// owns; the spending itself shows up as card payments.
const _cardsAndWallets = {'slice', 'cred', 'onecard', 'uni', 'jupiter', 'fi', 'paytm wallet'};

String _plain(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

extension Money on Store {
  static const _select = 'SELECT * FROM expenses WHERE deleted_at IS NULL';

  /// Categories the user chose for merchants, so the next payment to the same
  /// place lands in the same one.
  Map<String, String> get _remembered {
    final raw = getMeta(_rememberedKey);
    return raw == null ? {} : (jsonDecode(raw) as Map).cast<String, String>();
  }

  String _categoryFor(String? merchant, String text) =>
      (merchant == null ? null : _remembered[merchant.toLowerCase()]) ?? guessCategory(merchant, text);

  /// Monthly budget in paise, or null.
  int? get moneyBudget => int.tryParse(getMeta(_budgetKey) ?? '');
  set moneyBudget(int? paise) => setMeta(_budgetKey, paise?.toString());

  /// Names the user goes by on payments ("alok chaudhary"): money sent to
  /// them is money moved between their own accounts.
  List<String> get ownNames => (jsonDecode(getMeta(_ownNamesKey) ?? '[]') as List).cast<String>();

  void addOwnName(String name) {
    final n = _plain(name);
    if (n.length < 4 || ownNames.contains(n)) return;
    setMeta(_ownNamesKey, jsonEncode([...ownNames, n]));
  }

  /// Banks cut names short ("ALOK CHAUDHA"), so a long enough start counts.
  bool _isOwnName(String? merchant) {
    if (merchant == null) return false;
    final m = _plain(merchant);
    return ownNames.any((n) {
      final short = m.length < n.length ? m : n, long = m.length < n.length ? n : m;
      if (!long.startsWith(short)) return false;
      // "nexera" is the pocket "nexera new"; "alok chaudha" is "alok chaudhary".
      return short.length >= 8 || (short.length >= 5 && (long.length == short.length || long[short.length] == ' '));
    });
  }

  String _categorize(ParsedSms p, String body) {
    final first = _plain(p.merchant ?? '').split(' ').first;
    if (saysOwnTransfer(body) || _isOwnName(p.merchant) || _cardsAndWallets.contains(first)) return Categories.own;
    final remembered = p.merchant == null ? null : _remembered[p.merchant!.toLowerCase()];
    if (remembered != null) return remembered;
    if (p.direction == Expense.into) return Categories.transfers;
    final guess = guessCategory(p.merchant, body);
    return guess == Categories.other && p.toPerson ? Categories.people : guess;
  }

  /// Stores the payments among [messages] that are not stored yet (or were
  /// deleted: deleting one means "not an expense"). Returns how many were added.
  /// With [refresh], payments already stored are read again, for when the
  /// reading of messages has improved; ones that no longer read as payments
  /// are removed.
  int importSms(Iterable<({String sender, String body, DateTime at})> messages, {bool refresh = false}) {
    var added = 0;
    db.execute('BEGIN');
    try {
      for (final m in messages) {
        if (_ownPocket.firstMatch(m.body.replaceAll(_invisible, '')) case final pocket?) addOwnName(pocket.group(1)!);
        final p = parseBankSms(m.sender, m.body);
        final id = 'sms-${_hash('${m.sender}|${m.at.millisecondsSinceEpoch}|${m.body}')}';
        final stored = db.select('SELECT deleted_at FROM expenses WHERE id = ?', [id]).firstOrNull;
        if (stored != null) {
          if (!refresh || stored['deleted_at'] != null) continue;
          if (p == null) {
            _touch(id, {'deleted_at': Store.nowUtc()});
          } else {
            _touch(id, {
              'amount': p.amount,
              'direction': p.direction,
              'merchant': p.merchant,
              'account': p.account,
              'category': _categorize(p, m.body),
            });
          }
          continue;
        }
        if (p == null) continue;
        _put(id, at: m.at, amount: p.amount, direction: p.direction, merchant: p.merchant, account: p.account,
            category: _categorize(p, m.body), source: 'sms');
        added++;
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    if (added > 0 || refresh) markOwnTransfers();
    return added;
  }

  /// Finds money that left one of the user's accounts and arrived in another
  /// of them (same amount, two different accounts, within two hours) and
  /// marks both sides as an own transfer. A friend paying back lands in the
  /// account it left, so it is not caught. Returns how many pairs were found.
  int markOwnTransfers({Duration within = const Duration(hours: 2)}) {
    final rows = db
        .select("$_select AND account IS NOT NULL AND category != ? ORDER BY at", [Categories.own])
        .map(Expense.fromRow)
        .toList();
    final used = <String>{};
    var pairs = 0;
    for (final out in rows.where((e) => e.spent)) {
      if (used.contains(out.id)) continue;
      final match = rows.where((e) =>
          !e.spent &&
          !used.contains(e.id) &&
          e.amount == out.amount &&
          // ₹1 and ₹2 card checks are everywhere; they pair by chance.
          out.amount >= 1000 &&
          e.account != out.account &&
          e.at.difference(out.at).abs() <= within);
      if (match.isEmpty) continue;
      final into = match.first;
      used..add(out.id)..add(into.id);
      _touch(out.id, {'category': Categories.own});
      _touch(into.id, {'category': Categories.own});
      pairs++;
      // Sent to "ALOK CHAUDHARY", arrived from "ALOK CHAUDHA": that is the
      // user's own name, and later payments to it are theirs too.
      // A friend paid back from another account would look the same once,
      // so the name has to keep turning up on both sides.
      final (a, b) = (_plain(out.merchant ?? ''), _plain(into.merchant ?? ''));
      final short = a.length < b.length ? a : b;
      if (short.length >= 8 && a.startsWith(short) && b.startsWith(short)) {
        final seen = db.select('$_select AND merchant IS NOT NULL').map(Expense.fromRow).where((e) {
          final m = _plain(e.merchant!);
          return m.length >= 8 && (m.startsWith(short) || short.startsWith(m));
        }).toList();
        if (seen.length >= 4 && seen.any((e) => e.spent) && seen.any((e) => !e.spent) && seen.map((e) => e.date).toSet().length >= 3) {
          addOwnName(a.length > b.length ? a : b);
        }
      }
    }
    for (final e in db.select('$_select AND category != ?', [Categories.own]).map(Expense.fromRow)) {
      if (_isOwnName(e.merchant)) _touch(e.id, {'category': Categories.own});
    }
    return pairs;
  }

  /// A payment typed in: cash, or one no message covered.
  Expense addExpense({
    required int amount,
    String direction = Expense.out,
    String? merchant,
    String? category,
    String? note,
    DateTime? at,
  }) {
    if (amount <= 0) throw TodoException('An amount must be more than zero');
    if (direction != Expense.out && direction != Expense.into) throw TodoException('Direction is "out" or "in"');
    final id = Store.newId();
    _put(id,
        at: at ?? DateTime.now(),
        amount: amount,
        direction: direction,
        merchant: merchant,
        category: category ?? _categoryFor(merchant, note ?? ''),
        note: note,
        source: 'manual');
    return expense(id)!;
  }

  void _put(String id,
      {required DateTime at,
      required int amount,
      required String direction,
      String? merchant,
      String? category,
      String? account,
      String? note,
      required String source}) {
    final now = Store.nowUtc();
    db.execute(
      'INSERT INTO expenses (id, at, date, amount, direction, merchant, category, account, source, note, '
      'created_at, updated_at, dirty) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)',
      [id, at.toIso8601String(), ymd(at), amount, direction, merchant, category, account, source, note, now, now],
    );
  }

  Expense? expense(String id) {
    final rows = db.select('$_select AND id = ?', [id]);
    return rows.isEmpty ? null : Expense.fromRow(rows.first);
  }

  /// Payments dated within [from]..[to], newest first.
  List<Expense> expenses({String? from, String? to}) => db
      .select('$_select AND date >= ? AND date <= ? ORDER BY at DESC', [from ?? '0000-00-00', to ?? '9999-99-99'])
      .map(Expense.fromRow)
      .toList();

  /// Moves a payment to [category]; with [remember], later payments to the
  /// same merchant follow, and so do this month's others.
  void setExpenseCategory(String id, String category, {bool remember = true}) {
    final e = expense(id);
    if (e == null) throw TodoException('No such payment');
    _touch(id, {'category': category});
    if (remember && e.merchant != null) {
      setMeta(_rememberedKey, jsonEncode({..._remembered, e.merchant!.toLowerCase(): category}));
      for (final other in db.select('$_select AND merchant = ? AND category != ? AND date >= ?',
          [e.merchant, category, addDays(e.date, -31)])) {
        _touch(other['id'] as String, {'category': category});
      }
    }
  }

  void setExpenseNote(String id, String? note) => _touch(id, {'note': note});

  /// Not an expense (a transfer between your own accounts, a misread
  /// message). Stays deleted when the message is read again.
  void deleteExpense(String id) => _touch(id, {'deleted_at': Store.nowUtc()});

  void _touch(String id, Map<String, Object?> values) {
    final row = {...values, 'updated_at': Store.nowUtc(), 'dirty': 1};
    db.execute('UPDATE expenses SET ${row.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?', [...row.values, id]);
  }

  /// The month [month] (YYYY-MM; this month if null).
  MoneySummary moneySummary([String? month]) {
    final m = month ?? today().substring(0, 7);
    return MoneySummary(m, expenses(from: '$m-01', to: '$m-31'), moneyBudget);
  }

  /// Payments seen in at least two of the last [months] months to the same
  /// merchant for about the same amount: subscriptions, rent, EMIs.
  List<Recurring> recurring({int months = 4}) {
    final from = addDays(today(), -31 * months);
    final groups = <String, List<Expense>>{};
    for (final e in expenses(from: from).where((e) => e.spent && e.merchant != null && e.category != Categories.own)) {
      groups.putIfAbsent(e.merchant!, () => []).add(e);
    }
    final out = <Recurring>[];
    for (final MapEntry(key: merchant, value: list) in groups.entries) {
      final byMonth = <String, int>{};
      for (final e in list) {
        byMonth.update(e.date.substring(0, 7), (v) => v + e.amount, ifAbsent: () => e.amount);
      }
      if (byMonth.length < 2) continue;
      final amounts = byMonth.values.toList()..sort();
      final typical = amounts[amounts.length ~/ 2];
      final steady = amounts.where((a) => (a - typical).abs() <= typical * 0.15).length;
      if (steady >= 2) out.add(Recurring(merchant, typical, byMonth.length, list.first.category));
    }
    return out..sort((a, b) => b.amount.compareTo(a.amount));
  }
}

/// A short stable hash (FNV-1a, 64-bit) for message ids.
String _hash(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
