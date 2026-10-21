import 'package:vault_core/vault_core.dart';

/// Things saved to look at later (a café from a reel, a recipe, a show to
/// watch), sorted into collections. Each saved item is a diary entry that
/// starts `Saved to <Collection>`, so it syncs like any entry and tonight's
/// agent files it into `Collections/<Collection>.md` in the notes.
enum Collection {
  places('Places'),
  recipes('Recipes'),
  watchlist('Watchlist'),
  wishlist('Wishlist'),
  learn('Learn'),
  saved('Saved');

  const Collection(this.label);

  final String label;

  static Collection? byLabel(String label) => values.where((c) => c.label == label).firstOrNull;
}

const _hints = <Collection, List<String>>{
  Collection.places: [
    'maps.google', 'goo.gl/maps', 'maps.app.goo.gl', 'cafe', 'café', 'restaurant', 'hotel', 'resort', 'homestay',
    'beach', 'trek', 'hike', 'travel', 'trip', 'itinerary', 'places to visit', 'must visit', 'hidden gem',
    'location', 'address', 'dhaba', 'bar ', 'pub', 'rooftop', 'waterfall', 'temple', 'fort',
  ],
  Collection.recipes: [
    'recipe', 'ingredients', 'tbsp', 'tsp', 'cup of', 'cups', 'bake', 'cook', 'marinate', 'fry', 'boil',
    'paneer', 'chicken', 'masala', 'dough', 'sauce', 'dessert', 'breakfast', 'high protein', 'meal prep',
  ],
  Collection.watchlist: [
    'netflix', 'prime video', 'primevideo', 'hotstar', 'jiocinema', 'sonyliv', 'zee5', 'imdb', 'movie', 'film',
    'series', 'season', 'episode', 'trailer', 'anime', 'documentary', 'watch this', 'youtube.com/watch', 'youtu.be',
  ],
  Collection.wishlist: [
    'amazon.', 'amzn.', 'flipkart', 'myntra', 'meesho', 'ajio', 'nykaa', 'buy', 'price', 'sale', '% off',
    'discount', 'order now', 'add to cart', 'mrp', 'deal',
  ],
  Collection.learn: [
    'how to', 'tips', 'tutorial', 'course', 'learn', 'guide', 'step', 'roadmap', 'interview', 'dsa', 'leetcode',
    'python', 'javascript', 'flutter', 'github.com', 'prompt', 'productivity', 'book', 'notes', 'cheat sheet',
  ],
};

final _price = RegExp(r'(₹|rs\.?\s?|\$|€|£)\s?\d', caseSensitive: false);

/// The collection [text] most likely belongs in; [app] is where it came
/// from, when known.
Collection guessCollection(String text, {String? app}) {
  final t = ' ${text.toLowerCase()} ';
  final scores = <Collection, int>{};
  for (final MapEntry(key: c, value: words) in _hints.entries) {
    scores[c] = words.where(t.contains).length;
  }
  if (_price.hasMatch(text)) scores.update(Collection.wishlist, (s) => s + 2);
  final a = app?.toLowerCase() ?? '';
  if (a.contains('maps')) scores.update(Collection.places, (s) => s + 3);
  if (a.contains('youtube') || a.contains('netflix') || a.contains('prime') || a.contains('hotstar')) {
    scores.update(Collection.watchlist, (s) => s + 1);
  }
  if (a.contains('amazon') || a.contains('flipkart') || a.contains('myntra')) {
    scores.update(Collection.wishlist, (s) => s + 3);
  }
  final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value > 0 ? best.key : Collection.saved;
}

/// The diary text for a saved item: "Saved to Places (from Instagram, 22
/// Oct 10:15):" then the content.
String savedBody(Collection c, String content, {String? source}) {
  final text = content.trim();
  final body = text.length > 1500 ? '${text.substring(0, 1500)}…' : text;
  return 'Saved to ${c.label}${source == null || source.isEmpty ? '' : ' ($source)'}:\n$body';
}

/// A saved item read back from its diary entry.
class SavedItem {
  SavedItem(this.entry, this.collection, this.source, this.content);

  final DiaryEntry entry;
  final Collection collection;
  final String? source;
  final String content;

  /// The first link in it, to open.
  String? get link => RegExp(r'https?://\S+').firstMatch(content)?.group(0);

  static final _head = RegExp(r'^Saved to (\w+)(?: \(([^)\n]*)\))?:\s*');

  static SavedItem? from(DiaryEntry e) {
    final m = _head.firstMatch(e.body);
    final c = m == null ? null : Collection.byLabel(m.group(1)!);
    if (c == null) return null;
    return SavedItem(e, c, m!.group(2), e.body.substring(m.end).trim());
  }
}

/// Everything saved, newest first.
List<SavedItem> savedItems(Store store) {
  final items = store.diary().map(SavedItem.from).whereType<SavedItem>().toList();
  items.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
  return items;
}
