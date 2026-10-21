import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:vault_core/vault_core.dart';

import 'background.dart';
import 'collect.dart';
import 'outputs.dart';
import 'usage_sync.dart';

/// Holds the store and tells the UI when anything changed, whether from this
/// app, from sync, or (on the laptop) from the CLI or top-bar widget.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.store) : remote = SupabaseRemote(store);

  final Store store;
  final SupabaseRemote remote;

  bool syncing = false;
  String? syncError;
  DateTime? lastSync;

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _periodic, _afterEdit, _afterOutside;
  ReceivePort? _background;

  void start({String? watchDir}) {
    if (watchDir != null) {
      _watch = Directory(watchDir).watch().listen((_) {
        _afterOutside ??= Timer(const Duration(milliseconds: 250), () {
          _afterOutside = null;
          notifyListeners();
        });
      });
    }
    if (Platform.isAndroid) {
      // A widget tap or a reminder button changed the database from another
      // isolate while this screen was open.
      _background = ReceivePort()..listen((_) => notifyListeners());
      IsolateNameServer.removePortNameMapping(appChangedPort);
      IsolateNameServer.registerPortWithName(_background!.sendPort, appChangedPort);
    }
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => _collectThenSync());
    WidgetsBinding.instance.addObserver(this);
    refreshOutputs(store);
    _collectThenSync();
  }

  /// Phone: pull in screen time first so it goes up with the next sync.
  Future<void> _collectThenSync() async {
    try {
      await collectPhoneUsage(store);
      notifyListeners();
    } catch (_) {
      // Screen time is optional; never block syncing on it.
    }
    if (Platform.isAndroid) {
      // Money and health are optional too.
      try {
        await collectSms(store);
        await collectHealth(store);
        notifyListeners();
      } catch (_) {}
    }
    await sync();
  }

  /// Widgets may have changed the database while the app was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    notifyListeners();
    _collectThenSync();
  }

  /// Whether a sync would do anything: signed in, or (phone) a calendar chosen.
  bool get _syncs => remote.signedIn || store.getMeta('calendar_id') != null;

  /// Runs a store write, refreshes the UI and queues a sync.
  T change<T>(T Function(Store store) write) {
    final result = write(store);
    notifyListeners();
    refreshOutputs(store);
    if (_syncs) {
      _afterEdit?.cancel();
      _afterEdit = Timer(const Duration(seconds: 3), sync);
    }
    return result;
  }

  Future<void> sync() async {
    if (syncing || !_syncs) return;
    syncing = true;
    notifyListeners();
    try {
      await fullSync(store);
      syncError = null;
      lastSync = DateTime.now();
    } on SyncException catch (e) {
      syncError = e.message;
    } catch (_) {
      syncError = 'Offline. Changes are saved here and will sync later.';
    } finally {
      syncing = false;
      notifyListeners();
      refreshOutputs(store);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await remote.signIn(email, password);
    notifyListeners();
    await sync();
  }

  void signOut() {
    remote.signOut();
    syncError = null;
    lastSync = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    if (_background != null) {
      IsolateNameServer.removePortNameMapping(appChangedPort);
      _background!.close();
    }
    _periodic?.cancel();
    _afterEdit?.cancel();
    _afterOutside?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
