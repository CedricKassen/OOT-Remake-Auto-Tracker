import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:oot_save/oot_save.dart';
import 'package:oot_tracker/oot_tracker.dart';
import 'package:path/path.dart' as p;

/// Loads `areas.json`, `checks.json` and the optional `flag_map.json`
/// (check id -> "0x…" Bool field hash) from [dataDir].
(GameData, Map<String, int>) loadGameData(String dataDir) {
  Object? read(String name) {
    final file = File(p.join(dataDir, name));
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) : null;
  }

  final data = GameData.fromJson(
    read('areas.json') as List? ?? const [],
    read('checks.json') as List? ?? const [],
    read('collectibles.json') as List? ?? const [],
    read('check_links.json') as Map? ?? const {},
  );
  final flagMap = <String, int>{};
  ((read('flag_map.json') as Map?) ?? const {}).forEach((id, hash) {
    final parsed = int.tryParse('$hash'.replaceFirst(RegExp('^0[xX]'), ''), radix: 16);
    if (parsed != null) flagMap['$id'] = parsed;
  });
  return (data, flagMap);
}

/// Manual ticks, kept in a JSON file outside the save.
class ManualStore {
  ManualStore(this.path) {
    final file = File(path);
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as Map;
        ticks.addAll((json['ticks'] as List? ?? const []).cast<String>());
        anonymous.addAll(((json['anonymous'] as Map?) ?? const {}).cast<String, int>());
      } on FormatException {
        stderr.writeln('Ignoring unreadable $path');
      }
    }
  }

  final String path;
  final Set<String> ticks = {};

  /// Finds marked without naming the check, keyed by `<area id>/<category>`.
  final Map<String, int> anonymous = {};

  void _save() {
    final file = File(path)..parent.createSync(recursive: true);
    final tmp = File('$path.tmp')
      ..writeAsStringSync(jsonEncode({'ticks': ticks.toList()..sort(), 'anonymous': anonymous}));
    tmp.renameSync(file.path);
  }

  /// Sets or clears a tick; returns whether anything changed.
  bool set(String id, bool done) {
    final changed = done ? ticks.add(id) : ticks.remove(id);
    if (changed) _save();
    return changed;
  }

  /// Changes the anonymous count of [key] by [delta], not below zero.
  void addAnonymous(String key, int delta) {
    final count = ((anonymous[key] ?? 0) + delta).clamp(0, 999);
    count == 0 ? anonymous.remove(key) : anonymous[key] = count;
    _save();
  }
}

/// Watches the save, derives the tracker state and tells listeners about changes.
class TrackerService {
  TrackerService({
    required this.dataDir,
    required this.manual,
    this.saveDirArg,
    this.pinnedSlot,
    this.journalPath,
    String? mapsDir,
  }) : mapsDir = mapsDir ?? p.join(dataDir, 'local', 'maps') {
    final (data, flagMap) = loadGameData(dataDir);
    _data = data;
    _flagMap = flagMap;
  }

  final String dataDir;
  final ManualStore manual;

  /// Folder with the map pictures extracted from the user's own game.
  final String mapsDir;

  /// The index of the game maps (`maps.json`), reduced to the maps whose
  /// picture is actually in [mapsDir]. Without pictures it is empty and the
  /// apps draw their own diagram instead of showing maps that cannot load.
  String mapsJson() {
    final file = File(p.join(dataDir, 'maps.json'));
    if (!file.existsSync()) return '{"maps":[]}';
    try {
      final index = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
      index['maps'] = [
        for (final map in index['maps'] as List? ?? const [])
          if (map is Map && File(p.join(mapsDir, '${map['file']}')).existsSync()) map,
      ];
      return jsonEncode(index);
    } on FormatException {
      return '{"maps":[]}';
    }
  }

  /// How many map pictures are available.
  int get mapCount {
    final dir = Directory(mapsDir);
    if (!dir.existsSync()) return 0;
    try {
      return dir.listSync().where((e) => e.path.toLowerCase().endsWith('.png')).length;
    } on FileSystemException {
      return 0;
    }
  }

  /// What the user pointed at; null means the default locations.
  final String? saveDirArg;
  final String? pinnedSlot;
  final String? journalPath;

  late GameData _data;
  late Map<String, int> _flagMap;

  String? saveDir;
  SaveSlot? _slot;
  String? _error;
  String _signature = '';
  String stateJson = '{}';
  Map<int, String> _lastValues = {};
  Set<int> _lastKeys = {};

  final _changes = StreamController<String>.broadcast();

  /// Emits the new state JSON whenever it changes.
  Stream<String> get changes => _changes.stream;

  Uint8List? get screenshot => _slot?.screenshot;
  SaveSlot? get slot => _slot;

  StreamSubscription<FileSystemEvent>? _watch;
  String? _watched;
  Timer? _debounce;
  Timer? _poll;

  void start() {
    refresh(force: true);
    // Polling is the safety net (and finds a save folder that appears later);
    // the file watcher makes updates arrive right after the game saves.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> stop() async {
    _poll?.cancel();
    _debounce?.cancel();
    await _watch?.cancel();
    await _changes.close();
  }

  void _watchFolder(String? dir) {
    // Watch the parent as well: ports replace the whole save folder on save.
    final target = dir == null ? null : p.dirname(dir);
    if (target == _watched) return;
    _watch?.cancel();
    _watch = null;
    _watched = target;
    if (target == null) return;
    try {
      _watch = Directory(target).watch(recursive: true).listen(
        (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), refresh);
        },
        onError: (_) => _watched = null,
      );
    } on FileSystemException {
      _watched = null;
    }
  }

  /// Size and time of every slot file: cheap to compute, changes on any save.
  String _statSignature(String dir) {
    final parts = <String>[dir];
    for (final id in SaveLocator.slotIds(dir)) {
      for (final name in ['progress.sav', 'caption.sav']) {
        final stat = File(p.join(dir, id, name)).statSync();
        parts.add('$id/$name:${stat.size}:${stat.modified.microsecondsSinceEpoch}');
      }
    }
    return parts.join('|');
  }

  /// Ticks or unticks a manual check. Naming a find that was so far counted
  /// anonymously uses up one of the anonymous finds of its area and category.
  void tick(String id, bool done) {
    final def = _data.checks.where((c) => c.id == id).firstOrNull;
    if (!manual.set(id, done)) return;
    if (done && def != null) {
      final key = '${def.area}/${def.category}';
      if ((manual.anonymous[key] ?? 0) > 0) manual.addAnonymous(key, -1);
    }
    publish();
  }

  /// Adds or removes anonymous finds for an area and category.
  void addAnonymous(String area, String category, int delta) {
    manual.addAnonymous('$area/$category', delta);
    publish();
  }

  /// Reloads game data from disk (after editing the JSON files).
  void reloadData() {
    final (data, flagMap) = loadGameData(dataDir);
    _data = data;
    _flagMap = flagMap;
    publish();
  }

  /// Re-reads the save if it changed on disk.
  void refresh({bool force = false}) {
    try {
      final dir = saveDirArg != null ? SaveLocator.resolve(saveDirArg!) : SaveLocator.findDefault();
      _watchFolder(dir ?? saveDir);
      if (dir == null) {
        _set(null, saveDirArg == null ? 'No save found' : 'No save found in $saveDirArg', '');
        return;
      }
      saveDir = dir;
      final signature = _statSignature(dir);
      if (!force && signature == _signature) return;
      final slots = SaveLocator.readSlots(dir);
      final chosen = pinnedSlot == null
          ? newestSlot(slots)
          : slots.where((s) => s.id == pinnedSlot).firstOrNull;
      if (chosen == null) {
        // Possibly caught mid-write: keep the old state and look again soon.
        if (_slot == null) _set(null, 'No readable slot in $dir', '');
        return;
      }
      _set(chosen, null, signature);
    } on FileSystemException catch (e) {
      // Files vanish briefly while the game swaps the save folder.
      stderr.writeln('Save not readable right now: ${e.message}');
    }
  }

  void _set(SaveSlot? slot, String? error, String signature) {
    _signature = signature;
    _error = error;
    if (slot != null) _journal(slot);
    _slot = slot;
    publish();
  }

  /// Recomputes the state and notifies listeners if it differs.
  void publish() {
    final state = deriveState(
      _data,
      _slot,
      manualTicks: manual.ticks,
      anonymous: manual.anonymous,
      flagMap: _flagMap,
      error: _error,
    );
    final json = jsonEncode(state.toJson());
    if (json == stateJson) return;
    stateJson = json;
    _changes.add(json);
  }

  static String _label(int hash) =>
      fieldNames[hash] ?? fieldLabels[hash] ?? '0x${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  /// Every decodable field of the current slot, named ones only unless [all].
  Map<String, Object?> fields({bool all = false}) {
    final save = _slot?.progress;
    if (save == null) return const {};
    return {
      for (final f in save.fields.values)
        if (all || fieldNames.containsKey(f.hash) || fieldLabels.containsKey(f.hash))
          _label(f.hash): save.value(f.hash),
    };
  }

  /// Appends the fields that changed since the previous save to the journal.
  /// The research tools use it to find which flag belongs to which collectible.
  void _journal(SaveSlot slot) {
    final save = slot.progress;
    final values = <int, String>{
      for (final f in save.fields.values)
        if (f.type != FieldType.binary && f.type != FieldType.unknown && f.type != FieldType.binaryArray)
          f.hash: jsonEncode(save.value(f.hash)),
    };
    final previous = _lastValues;
    final previousKeys = _lastKeys;
    _lastValues = values;
    _lastKeys = save.keys64;
    if (journalPath == null || previous.isEmpty) return;
    String hex(int key) => '0x${BigInt.from(key).toUnsigned(64).toRadixString(16).padLeft(16, '0').toUpperCase()}';
    final changes = [
      for (final e in values.entries)
        if (previous[e.key] != e.value)
          {
            'hash': '0x${e.key.toRadixString(16).padLeft(8, '0').toUpperCase()}',
            if (fieldNames[e.key] != null) 'name': fieldNames[e.key],
            'type': save.fields[e.key]!.type.name,
            'from': previous[e.key] == null ? null : jsonDecode(previous[e.key]!),
            'to': jsonDecode(e.value),
          },
    ];
    final keysSet = save.keys64.difference(previousKeys).map(hex).toList();
    final keysCleared = previousKeys.difference(save.keys64).map(hex).toList();
    if (changes.isEmpty && keysSet.isEmpty && keysCleared.isEmpty) return;
    final entry = {
      'at': DateTime.now().toIso8601String(),
      'slot': slot.id,
      'savedAt': slot.time?.toString(),
      'banc': save.stringNamed('Sequence_CurrentBanc'),
      'changes': changes,
      if (keysSet.isNotEmpty) 'keys64Set': keysSet,
      if (keysCleared.isNotEmpty) 'keys64Cleared': keysCleared,
    };
    File(journalPath!)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }
}
