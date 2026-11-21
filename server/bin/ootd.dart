import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ootd/extract/maps.dart';
import 'package:ootd/runner.dart';
import 'package:path/path.dart' as p;

/// The `data` folder: next to the executable, or in a parent of it or of the
/// working directory (running from the repository).
String? _findDataDir() {
  for (var dir in [Directory.current.path, p.dirname(Platform.resolvedExecutable), p.dirname(Platform.script.toFilePath())]) {
    for (var i = 0; i < 4; i++) {
      final candidate = p.join(dir, 'data');
      if (File(p.join(candidate, 'checks.json')).existsSync()) return candidate;
      dir = p.dirname(dir);
    }
  }
  return null;
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('save-dir', help: 'Save folder, backup folder, or data folder of a port/emulator.\n(default: look in the usual places, nxnative first)')
    ..addOption('slot', help: 'Always track this slot, e.g. slot_02. (default: the newest)')
    ..addOption('port', defaultsTo: '7437', help: 'Port to listen on.')
    ..addOption('bind', defaultsTo: '0.0.0.0', help: 'Address to listen on; 127.0.0.1 keeps it on this computer.')
    ..addOption('token', help: 'Require this token from clients.')
    ..addOption('data-dir', help: 'Folder with areas.json and checks.json.')
    ..addOption('maps-dir', help: 'Folder with the extracted map pictures. (default: local/maps in the data folder)')
    ..addOption(
      'extract-maps',
      valueHelp: 'game files',
      help:
          'Extract the map pictures from your copy of the game (RomFS.img of the PC port,\n'
          'or a folder with the unpacked game files) into the maps folder, then exit.',
    )
    ..addOption('state-dir', help: 'Folder for manual ticks and the change journal.')
    ..addFlag('advertise', defaultsTo: true, help: 'Announce the server on the local network (Bonjour).')
    ..addFlag('builtin-mdns', hide: true, help: 'Announce with the built-in responder even on macOS.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }
  if (args.flag('help')) {
    print('ootd - live progress tracker server for the Ocarina of Time remake\n\n${parser.usage}');
    return;
  }

  final dataDir = args.option('data-dir') ?? _findDataDir();
  if (dataDir == null) {
    stderr.writeln('Game data not found. Pass --data-dir <folder with checks.json>.');
    exit(66);
  }
  final extractFrom = args.option('extract-maps');
  if (extractFrom != null) {
    final outDir = args.option('maps-dir') ?? p.join(dataDir, 'local', 'maps');
    try {
      final result = extractMaps(
        source: extractFrom,
        dataDir: dataDir,
        outDir: outDir,
        onProgress: (done, total, title) {
          if (title.isNotEmpty) stdout.writeln('${done + 1}/$total  $title');
        },
      );
      print('Wrote ${result.written} map pictures to $outDir');
      if (result.missing.isNotEmpty) print('Not in the game files: ${result.missing.join(', ')}');
      if (result.resized.isNotEmpty) print('Other size than expected (pins may be off): ${result.resized.join(', ')}');
      exit(0);
    } on ExtractException catch (e) {
      stderr.writeln(e.message);
      exit(65);
    }
  }
  final stateDir = args.option('state-dir') ?? defaultStateDir();
  final port = int.tryParse(args.option('port')!);
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('--port expects a number between 1 and 65535.');
    exit(64);
  }
  final runner = ServerRunner(dataDir: dataDir, stateDir: stateDir, builtinMdns: args.flag('builtin-mdns'));
  await runner.start(
    ServerConfig(
      saveDir: args.option('save-dir'),
      slot: args.option('slot'),
      port: port,
      bind: args.option('bind')!,
      token: args.option('token'),
      advertise: args.flag('advertise'),
      mapsDir: args.option('maps-dir'),
    ),
  );
  if (!runner.running) {
    stderr.writeln(runner.error);
    exit(69);
  }
  if (runner.advertiseError != null) stderr.writeln(runner.advertiseError);
  final service = runner.service!;

  print('Save:   ${service.saveDir ?? 'not found yet, still looking'}');
  print('Data:   $dataDir');
  print('State:  $stateDir');
  print('API:    http://${Platform.localHostname}:$port/api/v1/state');
  service.changes.listen((_) {
    final slot = service.slot;
    if (slot != null) print('${DateTime.now().toIso8601String().substring(11, 19)}  ${slot.id} saved ${slot.time}');
  });

  Future<void> shutdown() async {
    await runner.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  // Windows has no SIGTERM to listen for.
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen((_) => shutdown());
}
