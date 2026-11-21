import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'save_file.dart';
import 'slot.dart';

/// Title id of the Ocarina of Time remake.
const String titleId = '0400486024DEC000';

/// The user id the PC ports save under.
const String portUserId = '5a3c9e1f0b7d24680000000000000001';

final _slotName = RegExp(r'^slot_0[0-5]$', caseSensitive: false);
const int _maxFileSize = 2 * 1024 * 1024;

/// Finds the folder that holds the `slot_NN` folders, and reads slots from it.
class SaveLocator {
  /// Where known ports and emulators keep their data on this machine.
  static List<String> defaultRoots() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final support = Platform.isMacOS
        ? p.join(home, 'Library', 'Application Support')
        : Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? home)
        : p.join(home, '.local', 'share');
    return [
      p.join(support, 'nxnative', titleId, 'save'),
      for (final name in ['Longshot', 'longshot', 'ReLink', 'relink', 'lichii', 'eden'])
        p.join(support, name),
    ];
  }

  /// The first default root that resolves to a save folder.
  static String? findDefault() {
    for (final root in defaultRoots()) {
      final found = resolve(root);
      if (found != null) return found;
    }
    return null;
  }

  static bool _hasSlots(String dir) => slotIds(dir).isNotEmpty;

  static bool _isSave(String dir) =>
      File(p.join(dir, 'progress.sav')).existsSync() &&
      File(p.join(dir, 'caption.sav')).existsSync();

  /// Names of the slot folders in [saveDir] that hold a complete save, sorted.
  static List<String> slotIds(String saveDir) {
    final dir = Directory(saveDir);
    if (!dir.existsSync()) return const [];
    final ids = <String>[];
    try {
      for (final entry in dir.listSync(followLinks: true)) {
        final name = p.basename(entry.path);
        if (_slotName.hasMatch(name) && _isSave(entry.path)) ids.add(name);
      }
    } on FileSystemException {
      return const [];
    }
    return ids..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Resolves what the user pointed at to the folder with the `slot_NN`
  /// folders. Accepts that folder itself, a `slot_NN` folder inside it, a
  /// Switch backup (slots under `files/`), a folder of such backups (the
  /// newest is used), or the data folder of a port or emulator, or any folder
  /// on the way down to its save. Returns null if no save is found.
  static String? resolve(String path) {
    final dir = p.normalize(p.absolute(path));
    if (!Directory(dir).existsSync()) return null;
    if (_slotName.hasMatch(p.basename(dir)) && _isSave(dir)) return p.dirname(dir);
    if (_hasSlots(dir)) return dir;
    final files = p.join(dir, 'files');
    if (_hasSlots(files)) return files;
    return _portSave(dir) ?? _newestBackup(dir);
  }

  // Layouts below a port's or emulator's data folder; `*` is a profile folder.
  static const _layouts = [
    ['save', '*'],
    ['user', 'save', '*'],
    ['nand', 'user', 'save', '0000000000000000', '*', titleId],
    ['nand', 'user', 'save', 'account', '*', titleId, '0'],
    ['user', 'nand', 'user', 'save', '0000000000000000', '*', titleId],
    ['user', 'nand', 'user', 'save', 'account', '*', titleId, '0'],
  ];

  static String? _portSave(String dir) {
    final found = <String>{};
    for (final layout in _layouts) {
      // The folder may be any folder along the layout, so try every suffix.
      for (var start = 0; start < layout.length; start++) {
        found.addAll(_expand(dir, layout.sublist(start)).where(_hasSlots));
      }
    }
    if (found.isEmpty) return null;
    return found.firstWhere(
      (f) => p.split(f).contains(portUserId),
      orElse: () => (found.toList()..sort()).first,
    );
  }

  static Iterable<String> _expand(String dir, List<String> parts) sync* {
    if (parts.isEmpty) {
      yield dir;
      return;
    }
    if (parts.first != '*') {
      final next = p.join(dir, parts.first);
      if (Directory(next).existsSync()) yield* _expand(next, parts.sublist(1));
      return;
    }
    try {
      for (final entry in Directory(dir).listSync().whereType<Directory>()) {
        yield* _expand(entry.path, parts.sublist(1));
      }
    } on FileSystemException {
      // Unreadable folder: nothing to find there.
    }
  }

  /// In a folder of Switch backups, the backup whose saves were written last.
  static String? _newestBackup(String dir) {
    String? best;
    var bestTime = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      for (final entry in Directory(dir).listSync().whereType<Directory>()) {
        for (final candidate in [entry.path, p.join(entry.path, 'files')]) {
          for (final id in slotIds(candidate)) {
            final time = File(p.join(candidate, id, 'progress.sav')).lastModifiedSync();
            if (time.isAfter(bestTime)) {
              bestTime = time;
              best = candidate;
            }
          }
        }
      }
    } on FileSystemException {
      return null;
    }
    return best;
  }

  /// Reads a file that the game may be rewriting: retries until two
  /// consecutive looks at it agree, and never opens it for writing.
  static Uint8List readStable(String path, {int attempts = 5}) {
    final file = File(path);
    for (var i = 0; ; i++) {
      final before = file.statSync();
      if (before.size > _maxFileSize) throw SaveFormatException('$path is too large');
      final bytes = file.readAsBytesSync();
      final after = file.statSync();
      if (before.size == after.size &&
          before.modified == after.modified &&
          bytes.length == after.size) {
        return bytes;
      }
      if (i + 1 >= attempts) throw FileSystemException('File keeps changing', path);
      sleep(const Duration(milliseconds: 50));
    }
  }

  /// Reads and parses one slot of [saveDir].
  static SaveSlot readSlot(String saveDir, String slotId) => SaveSlot(
    id: slotId.toLowerCase(),
    progress: SaveFile.parse(readStable(p.join(saveDir, slotId, 'progress.sav'))),
    caption: SaveFile.parse(readStable(p.join(saveDir, slotId, 'caption.sav'))),
  );

  /// Reads every readable slot of [saveDir]; slots that fail to parse (for
  /// example while the game is writing them) are skipped.
  static List<SaveSlot> readSlots(String saveDir) {
    final slots = <SaveSlot>[];
    for (final id in slotIds(saveDir)) {
      try {
        slots.add(readSlot(saveDir, id));
      } on SaveFormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return slots;
  }
}
