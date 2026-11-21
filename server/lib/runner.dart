import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oot_tracker/mdns.dart';
import 'package:path/path.dart' as p;

import 'http.dart';
import 'service.dart';

/// Where manual ticks, the journal and the settings are kept; the
/// environment variable `OOT_TRACKER_STATE_DIR` overrides it.
String defaultStateDir() {
  final env = Platform.environment;
  // For tests and for running two servers side by side.
  final override = env['OOT_TRACKER_STATE_DIR'];
  if (override != null && override.isNotEmpty) return override;
  if (Platform.isWindows) {
    return p.join(env['APPDATA'] ?? env['USERPROFILE'] ?? '.', 'oot-tracker');
  }
  final home = env['HOME'] ?? '.';
  return Platform.isMacOS
      ? p.join(home, 'Library', 'Application Support', 'oot-tracker')
      : p.join(env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'), 'oot-tracker');
}

/// What a user can configure about the server.
class ServerConfig {
  ServerConfig({this.saveDir, this.slot, this.port = 7437, this.bind = '0.0.0.0', this.token, this.advertise = true});

  /// Save folder to track; null looks in the usual places.
  String? saveDir;

  /// Slot folder to track, e.g. `slot_02`; null follows the newest save.
  String? slot;
  int port;
  String bind;

  /// When set, clients must send this token.
  String? token;

  /// Announce the server on the local network.
  bool advertise;

  static String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

  factory ServerConfig.fromJson(Map<String, Object?> json) => ServerConfig(
    saveDir: _text(json['saveDir']),
    slot: _text(json['slot']),
    port: json['port'] is int ? json['port'] as int : 7437,
    bind: _text(json['bind']) ?? '0.0.0.0',
    token: _text(json['token']),
    advertise: json['advertise'] != false,
  );

  Map<String, Object?> toJson() => {
    'saveDir': saveDir,
    'slot': slot,
    'port': port,
    'bind': bind,
    'token': token,
    'advertise': advertise,
  };

  ServerConfig copy() => ServerConfig.fromJson(toJson());

  /// Reads the settings file at [path]; defaults if it is missing or broken.
  static ServerConfig load(String path) {
    try {
      return ServerConfig.fromJson((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>());
    } on FileSystemException {
      return ServerConfig();
    } on FormatException {
      return ServerConfig();
    } on TypeError {
      return ServerConfig();
    }
  }

  void save(String path) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}

/// Announces the server on the local network: through the system's Bonjour
/// on macOS, with the built-in responder everywhere else.
class Advertiser {
  Process? _process;
  MdnsResponder? _responder;

  Future<void> start(int port, {bool builtin = false, String name = 'OoT Tracker'}) async {
    if (Platform.isMacOS && !builtin) {
      _process = await Process.start('dns-sd', ['-R', name, trackerServiceType, 'local', '$port']);
    } else {
      _responder = MdnsResponder(name: name, port: port);
      await _responder!.start();
    }
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    await _responder?.stop();
    _responder = null;
  }
}

/// Runs the whole server (save watcher, API, network announcement) from a
/// [ServerConfig], and can restart it with another one.
class ServerRunner {
  ServerRunner({required this.dataDir, required this.stateDir, this.builtinMdns = false, this.onShow});

  final String dataDir;
  final String stateDir;
  final bool builtinMdns;

  /// See [ApiServer.onShow].
  final void Function()? onShow;

  TrackerService? service;
  ApiServer? _api;
  final Advertiser _advertiser = Advertiser();

  /// Why the server is not running, or why it is not announced.
  String? error;
  String? advertiseError;

  bool get running => _api != null;
  int get clients => _api?.clients ?? 0;

  /// Starts the server. On failure [error] says why and [running] is false.
  Future<void> start(ServerConfig config) async {
    await stop();
    error = advertiseError = null;
    final service = TrackerService(
      dataDir: dataDir,
      manual: ManualStore(p.join(stateDir, 'manual.json')),
      saveDirArg: config.saveDir,
      pinnedSlot: config.slot,
      journalPath: p.join(stateDir, 'journal.jsonl'),
    );
    final api = ApiServer(service, token: config.token, onShow: onShow);
    try {
      await api.start(InternetAddress(config.bind), config.port);
    } on SocketException catch (e) {
      error = e.osError?.errorCode == 48 || e.osError?.errorCode == 98 || e.osError?.errorCode == 10048
          ? 'Port ${config.port} is already in use. Is another tracker server running?'
          : 'Could not listen on port ${config.port}: ${e.osError?.message ?? e.message}';
      await service.stop();
      return;
    } on ArgumentError {
      error = '"${config.bind}" is not an address of this computer.';
      await service.stop();
      return;
    }
    service.start();
    this.service = service;
    _api = api;
    if (config.advertise) {
      try {
        await _advertiser.start(api.port, builtin: builtinMdns);
      } on Exception catch (e) {
        advertiseError = 'Could not announce on the network: $e';
      }
    }
  }

  Future<void> stop() async {
    await _advertiser.stop();
    await _api?.stop();
    await service?.stop();
    _api = null;
    service = null;
  }
}
