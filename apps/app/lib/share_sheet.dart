import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

import 'collections.dart';
import 'state.dart';
import 'theme.dart';

/// Something another app shared to G.ONE: text (often just a link) and/or
/// images, copied into the app's cache by the activity.
class Shared {
  Shared.fromMap(Map<Object?, Object?> m)
      : text = [m['subject'], m['text']].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n'),
        images = (m['images'] as List?)?.cast<String>() ?? const [];

  final String text;
  final List<String> images;

  bool get isEmpty => text.trim().isEmpty && images.isEmpty;
}

const _share = MethodChannel('todo/share');
const _device = MethodChannel('todo/device');

/// Calls [onShared] for whatever started the app and for every share after.
Future<void> watchShares(void Function(Shared) onShared) async {
  _share.setMethodCallHandler((call) async {
    if (call.method == 'shared') onShared(Shared.fromMap(call.arguments as Map<Object?, Object?>));
  });
  final first = await _share.invokeMapMethod<Object?, Object?>('initial');
  if (first != null) onShared(Shared.fromMap(first));
}

/// The title and description a page gives for sharing (og: tags or <title>),
/// so a bare link says what it is. Null when it cannot be read quickly.
Future<String?> describeLink(String url) async {
  try {
    final res = await http
        .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 15) G.ONE', 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final html = res.body;
    String? meta(String name) => RegExp(
          '<meta[^>]+(?:property|name)=["\']$name["\'][^>]+content=["\']([^"\']*)["\']',
          caseSensitive: false,
        ).firstMatch(html)?.group(1);
    final title = meta('og:title') ?? RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    final desc = meta('og:description') ?? meta('description');
    final parts = [title, desc].whereType<String>().map(_unescape).map((s) => s.trim()).where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : parts.toSet().join('\n');
  } catch (_) {
    return null;
  }
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// Asks where to save [shared], then saves it as a diary entry and returns to
/// the app it came from.
Future<void> showShareSheet(BuildContext context, Shared shared) async {
  if (shared.isEmpty) return;
  final saved = await showModalBottomSheet<Collection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(shared),
  );
  for (final path in shared.images) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
  if (saved == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${saved.label}')));
  // Back to Instagram, or wherever it was shared from.
  await _device.invokeMethod('leave');
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet(this.shared);

  final Shared shared;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _note = TextEditingController();
  String? _found;
  bool _reading = true;
  Collection _collection = Collection.saved;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    _collection = guessCollection(widget.shared.text);
    _read();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Reads the images' text and what the link is about.
  Future<void> _read() async {
    final found = <String>[];
    if (widget.shared.images.isNotEmpty) {
      final ocr = TextRecognizer();
      try {
        for (final path in widget.shared.images) {
          final text = (await ocr.processImage(InputImage.fromFilePath(path))).text.trim();
          if (text.isNotEmpty) found.add(text);
        }
      } catch (_) {
      } finally {
        await ocr.close();
      }
    }
    final link = RegExp(r'https?://\S+').firstMatch(widget.shared.text)?.group(0);
    if (link != null) {
      final about = await describeLink(link);
      if (about != null) found.add(about);
    }
    if (!mounted) return;
    setState(() {
      _found = found.join('\n\n');
      _reading = false;
      if (!_picked) _collection = guessCollection('${widget.shared.text}\n$_found');
    });
  }

  void _save() {
    final content = [
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
      widget.shared.text.trim(),
      if ((_found ?? '').isNotEmpty) _found!,
    ].where((s) => s.isNotEmpty).join('\n');
    if (content.isEmpty) return Navigator.pop(context);
    AppScope.of(context).change((s) => s.addDiary(savedBody(_collection, content, source: 'shared')));
    Navigator.pop(context, _collection);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shared = widget.shared;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text('Save to G.ONE', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (shared.images.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shared.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(shared.images[i]), height: 120, cacheHeight: 360),
                  ),
                ),
              ),
            if (shared.text.isNotEmpty)
              Text(shared.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
            if (_reading)
              Row(
                spacing: 8,
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  Text('Reading it…', style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              )
            else if ((_found ?? '').isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  child: Text(_found!, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Collection.values)
                  ChoiceChip(
                    key: ValueKey('collection-${c.label}'),
                    label: Text(c.label),
                    selected: c == _collection,
                    onSelected: (_) => setState(() {
                      _collection = c;
                      _picked = true;
                    }),
                  ),
              ],
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'A note (optional): why you saved it'),
              minLines: 1,
              maxLines: 3,
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: Text('Save to ${_collection.label}')),
            ),
          ],
        ),
      ),
    );
  }
}
