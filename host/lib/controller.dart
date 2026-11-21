import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:oot_save/oot_save.dart';
import 'package:oot_tracker/mdns.dart';
import 'package:ootd/runner.dart';
import 'package:path/path.dart' as p;

import 'autostart.dart';

/// The checklist data bundled with the app.
const dataFiles = ['areas.json', 'checks.json', 'collectibles.json', 'check_links.json', 'maps.json'];

/// Copies the bundled checklist data to [dir], where the server reads it.
/// Map pictures a user put in `local/maps` there are left alone.
Future<void> unpackData(String dir) async {
  Directory(dir).createSync(recursive: true);
  for (final name in dataFiles) {
    final bytes = await rootBundle.load('assets/data/$name');
    File(p.join(dir, name)).writeAsBytesSync(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  }
}

/// Asks a server app already running on [port] to show its window.
/// Returns whether one answered.
Future<bool> showRunningInstance(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
  try {
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/show'));
    final response = await request.close().timeout(const Duration(seconds: 1));
    await response.drain<void>();
    return response.statusCode == 200;
  } on Exception {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Runs the server for the app and holds what the window shows about it.
class HostController extends ChangeNotifier {
  HostController({required this.stateDir, required this.autostart, required void Function() onShow})
    : config = ServerConfig.load(p.join(stateDir, 'server.json')) {
    runner = ServerRunner(dataDir: p.join(stateDir, 'data'), stateDir: stateDir, onShow: onShow);
  }

  final String stateDir;
  final Autostart autostart;
  late final ServerRunner runner;

  /// The settings the server runs with.
  ServerConfig config;

  bool starting = true;
  bool autostartEnabled = false;
  String? autostartError;
  List<String> addresses = const [];
  Timer? _tick;
  String _shown = '';

  String get _configPath => p.join(stateDir, 'server.json');

  /// Whether this is the first launch (nothing configured yet).
  bool get firstRun => !File(_configPath).existsSync();

  bool get running => runner.running;
  int get clients => runner.clients;
  String? get saveDir => runner.service?.saveDir;
  SaveSlot? get slot => runner.service?.slot;

  /// The slots of the save being tracked, for the slot picker.
  List<String> get slotIds => saveDir == null ? const [] : SaveLocator.slotIds(saveDir!);

  /// One line that says how things are, for the tray and the window.
  String get summary {
    if (starting) return 'Starting…';
    if (!running) return runner.error ?? 'Stopped';
    if (saveDir == null) return 'Running · no save found yet';
    return clients == 0 ? 'Running · no app connected' : 'Running · $clients ${clients == 1 ? 'app' : 'apps'} connected';
  }

  Future<void> start() async {
    await runner.start(config);
    starting = false;
    autostartEnabled = await autostart.isEnabled();
    addresses = [for (final a in await localAddresses()) a.address];
    notifyListeners();
    // The save, the connected apps and the network change on their own.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) async {
      addresses = [for (final a in await localAddresses()) a.address];
      final shown = '$summary|$saveDir|${slot?.id}|${slot?.time}|$addresses';
      if (shown != _shown) {
        _shown = shown;
        notifyListeners();
      }
    });
  }

  /// Saves [next] and restarts the server with it.
  Future<void> apply(ServerConfig next) async {
    config = next;
    try {
      next.save(_configPath);
    } on FileSystemException {
      // Still usable for this session.
    }
    starting = true;
    notifyListeners();
    await runner.start(next);
    starting = false;
    notifyListeners();
  }

  Future<void> setAutostart(bool enabled) async {
    autostartError = null;
    try {
      await autostart.set(enabled);
    } on Exception catch (e) {
      autostartError = 'Could not change this: $e';
    }
    autostartEnabled = await autostart.isEnabled();
    notifyListeners();
  }

  Future<void> shutdown() async {
    _tick?.cancel();
    await runner.stop();
  }
}
