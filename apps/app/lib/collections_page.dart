import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'collections.dart';
import 'screenshots.dart' show monthNames;
import 'state.dart';
import 'theme.dart';

/// Everything saved from shares and kept screenshots, by collection.
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  Collection? _filter;

  static const _icons = {
    Collection.places: Icons.place_rounded,
    Collection.recipes: Icons.restaurant_rounded,
    Collection.watchlist: Icons.movie_rounded,
    Collection.wishlist: Icons.shopping_bag_rounded,
    Collection.learn: Icons.school_rounded,
    Collection.saved: Icons.bookmark_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final all = savedItems(app.store);
    final items = _filter == null ? all : all.where((i) => i.collection == _filter).toList();
    final counts = <Collection, int>{for (final i in all) i.collection: 0};
    for (final i in all) {
      counts.update(i.collection, (n) => n + 1);
    }

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final c in [null, ...Collection.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c == null ? 'All ${all.length}' : '${c.label} ${counts[c] ?? 0}'),
                    selected: _filter == c,
                    onSelected: (_) => setState(() => _filter = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nothing saved yet. Share a reel, post or link to G.ONE, or keep a screenshot.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final d = item.entry.createdAt;
                    final link = item.link;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.orange.withValues(alpha: 0.16),
                          child: Icon(_icons[item.collection], color: AppColors.orange),
                        ),
                        title: Text(
                          item.content.split('\n').firstWhere((l) => !l.startsWith('http'), orElse: () => item.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.collection.label} · ${d.day} ${monthNames[d.month - 1]}'
                          '${item.source == null ? '' : ' · ${item.source}'}',
                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                        trailing: link == null
                            ? null
                            : IconButton(
                                tooltip: 'Open',
                                icon: const Icon(Icons.open_in_new_rounded),
                                onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                              ),
                        onTap: () => _details(context, item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _details(BuildContext context, SavedItem item) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(item.collection.label, style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            SelectableText(item.content),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () {
                    AppScope.of(context).change((s) => s.deleteDiary(item.entry.id));
                    Navigator.pop(sheet);
                  },
                ),
                const Spacer(),
                if (item.link != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open'),
                    onPressed: () => launchUrl(Uri.parse(item.link!), mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
