import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:vault_core/vault_core.dart';

/// Screenshots on the phone: listing them, judging which are worth keeping,
/// reading the text out of them, and moving the rest to the trash.
const _channel = MethodChannel('todo/shots');

/// One screenshot in the phone's gallery.
class Shot {
  Shot.fromMap(Map<Object?, Object?> m)
      : id = (m['id'] as num).toInt(),
        path = m['path'] as String,
        name = m['name'] as String,
        takenAt = DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt());

  final int id;
  final String path;
  final String name;
  final DateTime takenAt;

  /// The app it was taken in, when the file name says (Samsung writes
  /// `Screenshot_20261022_101530_Instagram.jpg`).
  String? get app => appFromName(name);
}

String? appFromName(String name) {
  final m = RegExp(r'^Screenshot_\d{8}[-_]\d{6}(?:\d*)_(.+)\.\w+$').firstMatch(name);
  final app = m?.group(1)?.replaceAll('_', ' ').trim();
  return app == null || app.isEmpty ? null : app;
}

/// Whether the app may read the gallery's images.
Future<bool> hasShotAccess() async => await _channel.invokeMethod<bool>('hasAccess') ?? false;

/// Asks for it; true when given.
Future<bool> requestShotAccess() async => await _channel.invokeMethod<bool>('requestAccess') ?? false;

/// Whether the user let the app manage media, so trashing needs no system
/// dialog each time.
Future<bool> canManageMedia() async => await _channel.invokeMethod<bool>('canManage') ?? false;

Future<void> openManageMediaSettings() => _channel.invokeMethod('openManageSettings');

/// Every screenshot, newest first.
Future<List<Shot>> listShots() async {
  final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
  return rows.map(Shot.fromMap).toList();
}

/// Moves [ids] to the phone's trash (kept 30 days). True when done.
Future<bool> trashShots(List<int> ids) async =>
    ids.isEmpty || (await _channel.invokeMethod<bool>('trash', {'ids': ids}) ?? false);

/// Screenshots already swiped right, so the deck does not show them again.
const _keptKey = 'shots_kept';

Set<int> keptShots(Store store) {
  final raw = store.getMeta(_keptKey);
  if (raw == null) return {};
  return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toSet();
}

void markKept(Store store, Iterable<int> ids) =>
    store.setMeta(_keptKey, jsonEncode({...keptShots(store), ...ids}.toList()));

void unmarkKept(Store store, int id) => store.setMeta(_keptKey, jsonEncode((keptShots(store)..remove(id)).toList()));

enum Verdict { keep, unsure, junk }

/// A guess at whether a screenshot is worth keeping, and the information in
/// it. The swipe decides; this only suggests.
class Judgement {
  const Judgement(this.verdict, this.reason, this.info);

  final Verdict verdict;
  final String reason;

  /// The text worth keeping, without the app's buttons and the status bar.
  final String info;
}

/// Apps whose screenshots usually hold something to remember.
const _infoApps = {
  'instagram', 'youtube', 'x', 'twitter', 'chrome', 'samsung internet', 'internet', 'reddit', 'linkedin',
  'maps', 'google maps', 'gmail', 'telegram', 'notes', 'samsung notes', 'keep', 'amazon', 'flipkart', 'spotify',
  'threads', 'medium', 'pinterest', 'zomato', 'swiggy', 'myntra', 'quora', 'github', 'chatgpt', 'claude',
};

/// Apps whose screenshots are usually taken by accident or are stale fast.
const _junkApps = {'one ui home', 'launcher', 'home', 'camera', 'gallery', 'phone', 'clock', 'calculator'};

/// Words that are an app's chrome, not content.
const _chrome = {
  'like', 'likes', 'reply', 'replies', 'share', 'send', 'follow', 'following', 'followers', 'message', 'more',
  'save', 'saved', 'comment', 'comments', 'subscribe', 'subscribed', 'home', 'search', 'reels', 'profile',
  'shorts', 'library', 'you', 'view', 'views', 'see more', 'see translation', 'add comment', 'add a comment...',
  'original audio', 'sponsored', 'remix', 'download', 'clip', 'shop', 'explore', 'messages', 'notifications',
};

final _url = RegExp(r'https?://\S+|\b[\w-]+\.(com|in|io|org|net|app|dev|co|me|ai)\b', caseSensitive: false);
final _handle = RegExp(r'(^|\s)@[\w.]{2,}');
final _hashtag = RegExp(r'(^|\s)#\w{2,}');
final _price = RegExp(r'(₹|rs\.?|\$|€|£)\s?\d', caseSensitive: false);
final _date = RegExp(
  r'\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b|\b\d{1,2}\s?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\b',
  caseSensitive: false,
);
final _email = RegExp(r'\b[\w.+-]+@[\w-]+\.\w{2,}\b');
final _phone = RegExp(r'(\+91[\s-]?)?\b[6-9]\d{9}\b');
final _otp = RegExp(r'\b(otp|one[- ]time|verification code|is your code)\b', caseSensitive: false);

/// Status-bar lines and counts: "10:15", "87%", "1.2K", "3d".
final _noise = RegExp(r'^[\d\s:.,%kmKM+·•|/\\-]*[dhwmy]?$');

/// The lines of [text] that carry content.
String extractInfo(String text) {
  final out = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.length < 3) continue;
    if (_noise.hasMatch(line)) continue;
    if (_chrome.contains(line.toLowerCase())) continue;
    if (out.isNotEmpty && out.last == line) continue;
    out.add(line);
  }
  return out.join('\n');
}

Judgement judge(String text, {String? app}) {
  final info = extractInfo(text);
  final words = info.split(RegExp(r'\s+')).where((w) => w.length > 1).length;
  final a = app?.toLowerCase();
  if (_otp.hasMatch(text)) return Judgement(Verdict.junk, 'A one-time code: stale already', info);

  var score = 0;
  final signs = <String>[];
  void sign(RegExp r, String what) {
    if (r.hasMatch(info)) {
      score++;
      signs.add(what);
    }
  }

  sign(_url, 'a link');
  sign(_handle, 'a handle');
  sign(_hashtag, 'hashtags');
  sign(_price, 'a price');
  sign(_date, 'a date');
  sign(_email, 'an email');
  sign(_phone, 'a phone number');
  if (words >= 25) {
    score += 2;
    signs.add('plenty of text');
  } else if (words >= 10) {
    score++;
  }
  if (a != null && _infoApps.contains(a)) {
    score++;
    signs.add('from $app');
  }
  if (a != null && _junkApps.contains(a)) score -= 2;
  if (words < 5) score -= 2;

  final verdict = score >= 3 ? Verdict.keep : (score <= 0 ? Verdict.junk : Verdict.unsure);
  final reason = switch (verdict) {
    Verdict.keep => 'Has ${signs.take(3).join(', ')}',
    Verdict.unsure => signs.isEmpty ? 'Some text, nothing stands out' : 'Has ${signs.take(2).join(', ')}',
    Verdict.junk => words < 5 ? 'Hardly any text' : 'Nothing worth keeping found',
  };
  return Judgement(verdict, reason, info);
}

/// The diary entry a kept screenshot becomes, for the nightly agent to file.
String diaryBodyFor(Shot shot, String info) {
  final when = '${shot.takenAt.day} ${monthNames[shot.takenAt.month - 1]}, '
      '${shot.takenAt.hour.toString().padLeft(2, '0')}:${shot.takenAt.minute.toString().padLeft(2, '0')}';
  final from = shot.app == null ? '' : ' from ${shot.app}';
  final text = info.length > 1500 ? '${info.substring(0, 1500)}…' : info;
  return 'Screenshot$from ($when), kept to remember:\n$text';
}

const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
