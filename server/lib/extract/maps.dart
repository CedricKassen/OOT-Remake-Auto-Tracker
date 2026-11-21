/// Extracts the game's own map pictures from the user's copy of the game
/// into PNG files, for the maps listed in `maps.json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'bntx.dart';
import 'zstd.dart';

class ExtractException implements Exception {
  ExtractException(this.message);

  /// Meant to be shown to the user as it is.
  final String message;
  @override
  String toString() => message;
}

/// Read access to the game's files: an `RomFS.img` of the PC port, or a
/// folder with the unpacked files (a "romfs" dump). Never writes.
class GameFiles {
  GameFiles._(this.root, this._image, this._index);

  /// The image file or the folder the files are read from.
  final String root;
  final RandomAccessFile? _image;
  final Map<String, (int, int)>? _index;

  static const _probe = 'UI/CustomTex/Map';

  /// Opens what the user pointed at: the image file, the unpacked folder, or
  /// a folder somewhere above either of them (the game's or port's folder).
  static GameFiles open(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) return _openImage(path);
    if (type != FileSystemEntityType.directory) throw ExtractException('"$path" does not exist.');
    final found = _search(Directory(path), 4);
    if (found == null) {
      throw ExtractException(
        'No game files were found in "$path". Choose the RomFS.img of the PC port, '
        'or a folder with the unpacked game files (the one that contains "UI" and "Pack").',
      );
    }
    return found;
  }

  static GameFiles? _search(Directory dir, int depth) {
    if (Directory(p.join(dir.path, _probe)).existsSync()) return GameFiles._(dir.path, null, null);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return null;
    }
    for (final file in entries.whereType<File>()) {
      if (p.basename(file.path).toLowerCase() == 'romfs.img') {
        try {
          return _openImage(file.path);
        } on ExtractException {
          // Not the image we are looking for; keep searching.
        }
      }
    }
    if (depth == 0) return null;
    for (final sub in entries.whereType<Directory>()) {
      final found = _search(sub, depth - 1);
      if (found != null) return found;
    }
    return null;
  }

  // "DMROMFS1", u64 index offset, u64 index size, u64 entry count; the index
  // is count * {u64 a, u64 b, u32 name, u16 name length, u8 type, u8 flags}
  // followed by the names. Folder: a = first child, b = child count.
  // File: a = offset, b = size.
  static GameFiles _openImage(String path) {
    final file = File(path).openSync();
    try {
      final header = file.readSync(32);
      if (header.length < 32 || ascii.decode(header.sublist(0, 8), allowInvalid: true) != 'DMROMFS1') {
        throw ExtractException('"${p.basename(path)}" is not a game image this app can read (RomFS.img of the PC port).');
      }
      final h = ByteData.sublistView(header);
      final indexAt = h.getUint64(8, Endian.little), indexSize = h.getUint64(16, Endian.little);
      final count = h.getUint64(24, Endian.little);
      if (indexSize > 1 << 28 || count * 24 > indexSize) throw ExtractException('The game image looks damaged.');
      file.setPositionSync(indexAt);
      final index = file.readSync(indexSize);
      final view = ByteData.sublistView(index);
      final names = count * 24;
      final files = <String, (int, int)>{};
      final stack = <(int, String)>[(0, '')];
      while (stack.isNotEmpty) {
        final (k, prefix) = stack.removeLast();
        if (k >= count) continue;
        final o = k * 24;
        final a = view.getUint64(o, Endian.little), b = view.getUint64(o + 8, Endian.little);
        final nameAt = names + view.getUint32(o + 16, Endian.little), nameLength = view.getUint16(o + 20, Endian.little);
        final name = prefix + utf8.decode(index.sublist(nameAt, nameAt + nameLength), allowMalformed: true);
        if (index[o + 22] != 0) {
          files[name] = (a, b);
        } else {
          for (var j = a; j < a + b; j++) {
            stack.add((j, k == 0 ? '' : '$name/'));
          }
        }
      }
      if (!files.keys.any((f) => f.startsWith('$_probe/'))) {
        throw ExtractException('The game image holds no map pictures. Is it the right game?');
      }
      return GameFiles._(path, file, files);
    } on RangeError {
      file.closeSync();
      throw ExtractException('The game image looks damaged.');
    } on ExtractException {
      file.closeSync();
      rethrow;
    }
  }

  /// The contents of [path] (forward slashes); null if there is no such file.
  Uint8List? read(String path) {
    final index = _index;
    if (index == null) {
      final file = File(p.joinAll([root, ...path.split('/')]));
      return file.existsSync() ? file.readAsBytesSync() : null;
    }
    final entry = index[path];
    if (entry == null) return null;
    _image!.setPositionSync(entry.$1);
    return _image.readSync(entry.$2);
  }

  void close() => _image?.closeSync();
}

/// What an extraction did.
class ExtractResult {
  ExtractResult(this.written, this.missing, this.resized);

  /// Pictures written.
  final int written;

  /// Maps whose picture the game files did not have.
  final List<String> missing;

  /// Maps whose picture has another size than `maps.json` expects (another
  /// version of the game); pins on these may be slightly off.
  final List<String> resized;

  Map<String, Object?> toJson() => {'written': written, 'missing': missing, 'resized': resized};
  factory ExtractResult.fromJson(Map<String, Object?> j) =>
      ExtractResult(j['written'] as int, (j['missing'] as List).cast(), (j['resized'] as List).cast());
}

/// Crops transparent borders, leaving 8 pixels around what is drawn. A
/// picture that is (almost) filled is kept whole.
img.Image _trim(img.Image image) {
  final w = image.width, h = image.height;
  final bytes = image.buffer.asUint8List();
  final columns = Uint8List(w), rows = Uint8List(h);
  for (var y = 0; y < h; y++) {
    var at = y * w * 4 + 3;
    for (var x = 0; x < w; x++, at += 4) {
      if (bytes[at] > 8) {
        columns[x] = 1;
        rows[y] = 1;
      }
    }
  }
  final usedColumns = columns.where((c) => c != 0).length, usedRows = rows.where((r) => r != 0).length;
  if (usedColumns == 0 || (usedColumns > 0.98 * w && usedRows > 0.98 * h)) return image;
  final x0 = columns.indexOf(1) - 8, x1 = columns.lastIndexOf(1) + 9;
  final y0 = rows.indexOf(1) - 8, y1 = rows.lastIndexOf(1) + 9;
  final left = x0 < 0 ? 0 : x0, top = y0 < 0 ? 0 : y0;
  return img.copyCrop(
    image,
    x: left,
    y: top,
    width: (x1 > w ? w : x1) - left,
    height: (y1 > h ? h : y1) - top,
  );
}

/// Extracts the pictures of the maps in `<dataDir>/maps.json` from the game
/// files at [source] into [outDir]. [onProgress] is called before each map
/// with how many are done, how many there are, and the map's title.
///
/// Slow (decoding takes a while); see [extractMapsInBackground].
ExtractResult extractMaps({
  required String source,
  required String dataDir,
  required String outDir,
  void Function(int done, int total, String title)? onProgress,
}) {
  final List maps;
  try {
    maps = (jsonDecode(File(p.join(dataDir, 'maps.json')).readAsStringSync()) as Map)['maps'] as List;
  } on Exception {
    throw ExtractException('The list of maps (maps.json) is missing or unreadable.');
  }
  final game = GameFiles.open(source);
  try {
    // Never write into the game's own folders.
    final target = p.canonicalize(outDir);
    final gameDir = p.canonicalize(game._index == null ? game.root : p.dirname(game.root));
    if (target == gameDir || p.isWithin(gameDir, target)) {
      throw ExtractException('The pictures cannot be saved inside the game folder. Choose another maps folder.');
    }
    Directory(outDir).createSync(recursive: true);

    var written = 0;
    final missing = <String>[], resized = <String>[];
    final decompressed = <String, Uint8List>{};
    for (var i = 0; i < maps.length; i++) {
      final map = (maps[i] as Map).cast<String, Object?>();
      final id = '${map['id']}', fileName = '${map['file']}';
      onProgress?.call(i, maps.length, '${map['title'] ?? id}');
      // "path" or "path:texture name" for a texture inside a larger file.
      final parts = '${map['source']}'.split(':');
      final path = parts[0];
      if (!RegExp(r'^[A-Za-z0-9_.-]+\.png$').hasMatch(fileName)) continue;

      Uint8List? data = decompressed[path];
      if (data == null) {
        final raw = game.read(path);
        if (raw == null) {
          missing.add(id);
          continue;
        }
        try {
          data = path.endsWith('.zs') ? zstdDecompress(raw) : raw;
        } on ZstdException catch (e) {
          throw ExtractException('Could not unpack $path: ${e.message}');
        }
        // Only the big shared file is worth keeping for a second use.
        if (parts.length > 1) decompressed[path] = data;
      }
      final img.Image picture;
      try {
        final textures = bntxTextures(data);
        final texture = parts.length > 1
            ? textures.where((t) => t.name == parts[1]).firstOrNull
            : textures.firstOrNull;
        if (texture == null) {
          missing.add(id);
          continue;
        }
        final rgba = bntxDecode(data, texture);
        picture = img.Image.fromBytes(
          width: texture.width,
          height: texture.height,
          bytes: rgba.buffer,
          numChannels: 4,
        );
      } on FormatException catch (e) {
        throw ExtractException('Could not read $path: ${e.message}');
      } on RangeError {
        throw ExtractException('Could not read $path: the file looks damaged.');
      }

      final width = map['width'] as int, height = map['height'] as int;
      var result = map['kind'] == 'world' ? picture : _trim(picture);
      if (result.width != width || result.height != height) {
        // The world picture is stored larger than needed; anything else of
        // another size comes from a game version maps.json was not made for.
        if (map['kind'] != 'world') resized.add(id);
        result = img.copyResize(result, width: width, height: height, interpolation: img.Interpolation.average);
      }
      final out = File(p.join(outDir, fileName));
      final part = File('${out.path}.part')..writeAsBytesSync(img.encodePng(result, level: 6));
      part.renameSync(out.path);
      written++;
    }
    onProgress?.call(maps.length, maps.length, '');
    if (written == 0) throw ExtractException('The game files did not contain any of the map pictures.');
    return ExtractResult(written, missing, resized);
  } finally {
    game.close();
  }
}

/// [extractMaps] on another isolate, so that an app stays responsive.
Future<ExtractResult> extractMapsInBackground({
  required String source,
  required String dataDir,
  required String outDir,
  void Function(int done, int total, String title)? onProgress,
}) async {
  final port = ReceivePort();
  final done = Completer<ExtractResult>();
  port.listen((message) {
    if (message is List && message.length == 3) {
      onProgress?.call(message[0] as int, message[1] as int, message[2] as String);
    } else if (message is Map) {
      done.complete(ExtractResult.fromJson(message.cast()));
    } else {
      done.completeError(ExtractException('$message'));
    }
  });
  try {
    await Isolate.spawn(_run, (port.sendPort, source, dataDir, outDir));
    return await done.future;
  } finally {
    port.close();
  }
}

void _run((SendPort, String, String, String) args) {
  final (port, source, dataDir, outDir) = args;
  try {
    final result = extractMaps(
      source: source,
      dataDir: dataDir,
      outDir: outDir,
      onProgress: (done, total, title) => port.send([done, total, title]),
    );
    port.send(result.toJson());
  } on ExtractException catch (e) {
    port.send(e.message);
  } catch (e) {
    port.send('Something went wrong while reading the game files: $e');
  }
}
