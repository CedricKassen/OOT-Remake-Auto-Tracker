import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:oot_save/oot_save.dart';
import 'package:oot_tracker/mdns.dart';
import 'package:ootd/extract/maps.dart';
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

  /// Where the server looks for map pictures, and how many it found.
  String get mapsDir => runner.service?.mapsDir ?? config.mapsDir ?? p.join(stateDir, 'data', 'local', 'maps');
  int mapCount = 0;

  /// Reading the map pictures from the game: whether it is running, how
  /// far it is, and how the last run ended.
  bool extracting = false;
  String extractProgress = '';
  String? extractResult;
  bool extractFailed = false;

  /// Reads the map pictures from the game files at [source] (the PC port's
  /// RomFS.img, or a folder with the unpacked game) into the maps folder.
  Future<void> extractMaps(String source) async {
    if (extracting) return;
    extracting = true;
    extractFailed = false;
    extractResult = null;
    extractProgress = 'Looking at the game files…';
    notifyListeners();
    try {
      final result = await extractMapsInBackground(
        source: source,
        dataDir: runner.dataDir,
        outDir: mapsDir,
        onProgress: (done, total, title) {
          if (title.isEmpty) return;
          extractProgress = 'Reading map ${done + 1} of $total: $title';
          notifyListeners();
        },
      );
      extractResult = [
        'Saved ${result.written} map pictures.',
        if (result.missing.isNotEmpty) '${result.missing.length} were not in the game files.',
        if (result.resized.isNotEmpty)
          'This looks like another version of the game: markers on ${result.resized.length} maps may be slightly off.',
      ].join(' ');
    } on ExtractException catch (e) {
      extractFailed = true;
      extractResult = e.message;
    } catch (e) {
      extractFailed = true;
      extractResult = 'Something went wrong: $e';
    }
    extracting = false;
    // A restart makes the connected apps fetch the new list of maps.
    if (!extractFailed) {
      await apply(config);
    } else {
      notifyListeners();
    }
  }

  /// The slots of the save being tracked, for the slot picker.
  List<String> get slotIds => saveDir == null ? const [] : SaveLocator.slotIds(saveDir!);

  /// One line that says how things are, for the tray and the window.
  String get summary {
    if (starting) return 'Starting…';
    if (!running) return runner.error ?? 'Stopped';
    if (saveDir == null) return 'Running · no save found yet';
    return clients == 0
        ? 'Running · no app connected'
        : 'Running · $clients ${clients == 1 ? 'app' : 'apps'} connected';
  }

  Future<void> start() async {
    await runner.start(config);
    mapCount = runner.service?.mapCount ?? 0;
    starting = false;
    autostartEnabled = await autostart.isEnabled();
    addresses = [for (final a in await localAddresses()) a.address];
    notifyListeners();
    // The save, the connected apps and the network change on their own.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) async {
      addresses = [for (final a in await localAddresses()) a.address];
      mapCount = runner.service?.mapCount ?? 0;
      final shown = '$summary|$saveDir|${slot?.id}|${slot?.time}|$addresses|$mapCount';
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
    mapCount = runner.service?.mapCount ?? 0;
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
