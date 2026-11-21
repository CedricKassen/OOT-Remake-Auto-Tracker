import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ootd/http.dart';
import 'package:ootd/service.dart';
import 'package:path/path.dart' as p;

String _defaultStateDir() {
  final home = Platform.environment['HOME'] ?? '.';
  return Platform.isMacOS
      ? p.join(home, 'Library', 'Application Support', 'oot-tracker')
      : p.join(home, '.local', 'share', 'oot-tracker');
}

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
    ..addOption('bind', defaultsTo: '0.0.0.0', help: 'Address to listen on; 127.0.0.1 keeps it on this Mac.')
    ..addOption('token', help: 'Require this token from clients.')
    ..addOption('data-dir', help: 'Folder with areas.json and checks.json.')
    ..addOption('state-dir', help: 'Folder for manual ticks and the change journal.')
    ..addFlag('advertise', defaultsTo: true, help: 'Announce the server on the local network (Bonjour).')
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
  final stateDir = args.option('state-dir') ?? _defaultStateDir();
  final service = TrackerService(
    dataDir: dataDir,
    manual: ManualStore(p.join(stateDir, 'manual.json')),
    saveDirArg: args.option('save-dir'),
    pinnedSlot: args.option('slot'),
    journalPath: p.join(stateDir, 'journal.jsonl'),
  )..start();

  final api = ApiServer(service, token: args.option('token'));
  final port = int.parse(args.option('port')!);
  await api.start(InternetAddress(args.option('bind')!), port);

  print('Save:   ${service.saveDir ?? 'not found yet, still looking'}');
  print('Data:   $dataDir');
  print('State:  $stateDir');
  print('API:    http://${Platform.localHostname}:$port/api/v1/state');
  service.changes.listen((_) {
    final slot = service.slot;
    if (slot != null) print('${DateTime.now().toIso8601String().substring(11, 19)}  ${slot.id} saved ${slot.time}');
  });

  Process? advert;
  if (args.flag('advertise') && Platform.isMacOS) {
    try {
      advert = await Process.start('dns-sd', ['-R', 'OoT Tracker', '_oottracker._tcp', 'local', '$port']);
    } on ProcessException catch (e) {
      stderr.writeln('Could not announce on the network: ${e.message}');
    }
  }

  Future<void> shutdown() async {
    advert?.kill();
    await api.stop();
    await service.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());
}
