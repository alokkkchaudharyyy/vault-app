import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:vault_core/vault_core.dart';

import 'collections.dart';
import 'screenshots.dart';
import 'state.dart';
import 'theme.dart';

/// Sort the day's screenshots: swipe right to keep (its text goes into the
/// diary, for tonight's agent to file), left to send it to the trash.
class ScreenshotsPage extends StatefulWidget {
  const ScreenshotsPage({super.key});

  @override
  State<ScreenshotsPage> createState() => _ScreenshotsPageState();
}

enum _Done { kept, trashed }

class _ScreenshotsPageState extends State<ScreenshotsPage> with WidgetsBindingObserver {
  final _ocr = TextRecognizer();
  final _judged = <int, Judgement>{};
  final _reading = <int>{};

  bool? _access;
  bool _manage = true;
  List<Shot>? _deck;
  int _kept = 0, _trashed = 0;

  /// Swiped left, not yet trashed: sent in batches so the system asks at
  /// most once per batch when media management is off.
  final _pendingTrash = <int>[];

  /// The last swipe, for undo.
  ({Shot shot, _Done done, String? diaryId})? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTrash();
    _ocr.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from system settings.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final access = await hasShotAccess();
    final manage = await canManageMedia();
    if (!mounted) return;
    if (!access) {
      return setState(() {
        _access = false;
        _manage = manage;
      });
    }
    final store = AppScope.of(context).store;
    final kept = keptShots(store);
    final shots = (await listShots()).where((s) => !kept.contains(s.id) && !_pendingTrash.contains(s.id)).toList();
    if (!mounted) return;
    setState(() {
      _access = true;
      _manage = manage;
      _deck = shots;
    });
    _readAhead();
  }

  /// Reads the text of the next few cards before they come up.
  void _readAhead() {
    for (final shot in (_deck ?? const <Shot>[]).take(3)) {
      if (_judged.containsKey(shot.id) || !_reading.add(shot.id)) continue;
      _ocr.processImage(InputImage.fromFilePath(shot.path)).then(
        (r) => r.text,
        onError: (Object _) => '',
      ).then((text) {
        _reading.remove(shot.id);
        if (mounted) setState(() => _judged[shot.id] = judge(text, app: shot.app));
      });
    }
  }

  void _swiped(Shot shot, _Done done) {
    final app = AppScope.of(context);
    String? diaryId;
    if (done == _Done.kept) {
      final info = _judged[shot.id]?.info ?? '';
      markKept(app.store, [shot.id]);
      if (info.trim().isNotEmpty) {
        final body = savedBody(guessCollection(info, app: shot.app), info, source: shotSource(shot));
        diaryId = app.change((s) => s.addDiary(body, date: ymd(shot.takenAt))).id;
      }
      _kept++;
    } else {
      _pendingTrash.add(shot.id);
      _trashed++;
      if (_pendingTrash.length >= 25) _flushTrash();
    }
    setState(() {
      _deck!.remove(shot);
      _last = (shot: shot, done: done, diaryId: diaryId);
    });
    if (_deck!.isEmpty) _flushTrash();
    _readAhead();
  }

  void _undo() {
    final last = _last;
    if (last == null) return;
    final app = AppScope.of(context);
    if (last.done == _Done.kept) {
      unmarkKept(app.store, last.shot.id);
      if (last.diaryId != null) app.change((s) => s.deleteDiary(last.diaryId!));
      _kept--;
    } else {
      // Already sent to the trash: the phone's Gallery can restore it.
      if (!_pendingTrash.remove(last.shot.id)) return _snack('Already in the trash; restore it from Gallery');
      _trashed--;
    }
    setState(() {
      _deck!.insert(0, last.shot);
      _last = null;
    });
  }

  Future<void> _flushTrash() async {
    if (_pendingTrash.isEmpty) return;
    final ids = List.of(_pendingTrash);
    _pendingTrash.clear();
    final ok = await trashShots(ids);
    if (!ok && mounted) {
      _pendingTrash.addAll(ids);
      _snack('Not deleted: the phone did not allow it');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_access == null) return const Center(child: CircularProgressIndicator());
    if (_access == false) {
      return _Message(
        icon: Icons.photo_library_rounded,
        title: 'Let G.ONE see your screenshots',
        body: 'Photos are read on this phone only. Kept screenshots become diary text; nothing else leaves the phone.',
        action: 'Allow',
        onAction: () async {
          await requestShotAccess();
          _load();
        },
      );
    }
    final deck = _deck!;
    return Column(
      children: [
        if (!_manage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              color: AppColors.raised,
              child: ListTile(
                leading: const Icon(Icons.bolt_rounded, color: AppColors.orange),
                title: const Text('Delete without the system asking'),
                subtitle: const Text('Turn on "Media management" for G.ONE'),
                onTap: openManageMediaSettings,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text('${deck.length} to sort', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$_kept kept · $_trashed deleted', style: t.labelMedium?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: deck.isEmpty
              ? _Message(
                  icon: Icons.done_all_rounded,
                  title: 'All sorted',
                  body: _kept > 0
                      ? 'What you kept is in your diary; tonight it is filed into your notes.'
                      : 'No screenshots waiting.',
                )
              : Stack(
                  children: [
                    if (deck.length > 1)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                          child: _ShotCard(shot: deck[1], judgement: _judged[deck[1].id], dim: true),
                        ),
                      ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _Swipeable(
                          key: ValueKey(deck.first.id),
                          onKeep: () => _swiped(deck.first, _Done.kept),
                          onTrash: () => _swiped(deck.first, _Done.trashed),
                          child: _ShotCard(shot: deck.first, judgement: _judged[deck.first.id]),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                icon: Icons.close_rounded,
                color: AppColors.red,
                label: 'Delete',
                onTap: deck.isEmpty ? null : () => _swiped(deck.first, _Done.trashed),
              ),
              _RoundButton(icon: Icons.undo_rounded, color: AppColors.muted, label: 'Undo', onTap: _last == null ? null : _undo),
              _RoundButton(
                icon: Icons.favorite_rounded,
                color: AppColors.green,
                label: 'Keep',
                onTap: deck.isEmpty ? null : () => _swiped(deck.first, _Done.kept),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A card that follows the finger and, past a third of the width, flies off:
/// right keeps, left deletes.
class _Swipeable extends StatefulWidget {
  const _Swipeable({super.key, required this.child, required this.onKeep, required this.onTrash});

  final Widget child;
  final VoidCallback onKeep, onTrash;

  @override
  State<_Swipeable> createState() => _SwipeableState();
}

class _SwipeableState extends State<_Swipeable> with SingleTickerProviderStateMixin {
  late final _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero, _to = Offset.zero;

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  Future<void> _animate(Offset to) async {
    _from = _drag;
    _to = to;
    await _fly.forward(from: 0);
  }

  Future<void> _release(double width, double velocity) async {
    final dx = _drag.dx;
    final keep = dx > width / 3 || velocity > 900;
    final trash = dx < -width / 3 || velocity < -900;
    if (keep || trash) {
      await _animate(Offset(keep ? width * 1.5 : -width * 1.5, _drag.dy));
      keep ? widget.onKeep() : widget.onTrash();
    } else {
      await _animate(Offset.zero);
      setState(() => _drag = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      onPanUpdate: (d) => setState(() => _drag += d.delta),
      onPanEnd: (d) => _release(box.maxWidth, d.velocity.pixelsPerSecond.dx),
      child: AnimatedBuilder(
        animation: _fly,
        builder: (context, child) {
          final offset = _fly.isAnimating ? Offset.lerp(_from, _to, Curves.easeOut.transform(_fly.value))! : _drag;
          final lean = (offset.dx / box.maxWidth).clamp(-1.0, 1.0);
          return Transform.translate(
            offset: offset,
            child: Transform.rotate(
              angle: lean * pi / 14,
              child: Stack(
                children: [
                  child!,
                  if (lean.abs() > 0.08)
                    Positioned(
                      top: 24,
                      left: lean > 0 ? 24 : null,
                      right: lean < 0 ? 24 : null,
                      child: Opacity(
                        opacity: (lean.abs() * 3).clamp(0.0, 1.0),
                        child: _Stamp(keep: lean > 0),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        child: widget.child,
      ),
    ),
  );
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.keep});

  final bool keep;

  @override
  Widget build(BuildContext context) {
    final color = keep ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
        color: AppColors.bg.withValues(alpha: 0.6),
      ),
      child: Text(
        keep ? 'KEEP' : 'DELETE',
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 2),
      ),
    );
  }
}

/// The screenshot, what G.ONE thinks of it and the text it found.
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.shot, required this.judgement, this.dim = false});

  final Shot shot;
  final Judgement? judgement;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final j = judgement;
    final (color, label) = switch (j?.verdict) {
      null => (AppColors.muted, 'Reading…'),
      Verdict.keep => (AppColors.green, 'Looks useful'),
      Verdict.unsure => (AppColors.cream, 'Your call'),
      Verdict.junk => (AppColors.red, 'Looks like junk'),
    };
    final d = shot.takenAt;
    final when = '${d.day} ${monthNames[d.month - 1]} · ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: Image.file(
                  File(shot.path),
                  fit: BoxFit.contain,
                  cacheWidth: 720,
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.muted)),
                ),
              ),
            ),
            if (!dim)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: ShapeDecoration(color: color.withValues(alpha: 0.18), shape: const StadiumBorder()),
                          child: Text(label, style: t.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Text(
                            [if (shot.app != null) shot.app!, when].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: t.labelMedium?.copyWith(color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                    if (j != null)
                      Text(
                        '${j.reason} · keep → ${guessCollection(j.info, app: shot.app).label}',
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    if (j != null && j.info.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 96),
                        child: SingleChildScrollView(child: Text(j.info, style: t.bodySmall)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: IconButton.filled(
      iconSize: 30,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: color,
        disabledBackgroundColor: AppColors.card,
        padding: const EdgeInsets.all(16),
      ),
      icon: Icon(icon),
      onPressed: onTap,
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action, this.onAction});

  final IconData icon;
  final String title, body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Icon(icon, size: 48, color: AppColors.orange),
            Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            Text(body, style: t.bodyMedium?.copyWith(color: AppColors.muted), textAlign: TextAlign.center),
            if (action != null) FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}
