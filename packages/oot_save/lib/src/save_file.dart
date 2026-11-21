import 'dart:convert';
import 'dart:typed_data';

import 'murmur3.dart';

/// Thrown when bytes are not a save file this parser understands.
class SaveFormatException implements Exception {
  SaveFormatException(this.message);
  final String message;
  @override
  String toString() => 'SaveFormatException: $message';
}

/// The type of a save field. The index is the section number in the file:
/// the field table is grouped into sections, each introduced by a marker
/// entry `{hash 0, section number}`; section 0 has no marker.
enum FieldType {
  bool_,
  boolArray,
  int_,
  intArray,
  float,
  floatArray,
  enum_,
  enumArray,
  vector2,
  vector2Array,
  vector3,
  vector3Array,
  string16,
  string16Array,
  string32,
  string32Array,
  string64,
  string64Array,
  binary,
  binaryArray,
  uint,
  uintArray,
  int64,
  int64Array,
  uint64,
  uint64Array,
  wstring16,
  wstring16Array,
  wstring32,
  wstring32Array,
  wstring64,
  wstring64Array,
  unknown;

  /// Whether the 4-byte table value is the value itself (not an offset).
  bool get isInline =>
      this == bool_ || this == int_ || this == float || this == enum_ || this == uint;
}

class SaveField {
  const SaveField(this.hash, this.type, this.raw);
  final int hash;
  final FieldType type;

  /// The 4-byte table value: the value itself for inline types, otherwise the
  /// absolute offset of the field's data block.
  final int raw;
}

/// A parsed, read-only `.sav` file (progress, caption, option or account).
///
/// Layout, all little-endian: u32 magic `0x01020304`, u32 version, u32
/// headerEnd, zero padding up to offset 40, then 8-byte entries
/// `{u32 hash, u32 value}` up to headerEnd, then the data blocks.
class SaveFile {
  SaveFile._(this._bytes, this._data, this.headerEnd, this.fields);

  static const int magic = 0x01020304;
  static const int version = 0x002D80EB;
  static const int _tableStart = 40;

  final Uint8List _bytes;
  final ByteData _data;
  final int headerEnd;
  final Map<int, SaveField> fields;

  factory SaveFile.parse(Uint8List bytes) {
    if (bytes.length < _tableStart) throw SaveFormatException('File too short');
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != magic) {
      throw SaveFormatException('Not a save file (wrong magic)');
    }
    final ver = data.getUint32(4, Endian.little);
    if (ver != version) {
      throw SaveFormatException('Unsupported save version 0x${ver.toRadixString(16)}');
    }
    final headerEnd = data.getUint32(8, Endian.little);
    if (headerEnd < _tableStart || headerEnd > bytes.length || (headerEnd - _tableStart) % 8 != 0) {
      throw SaveFormatException('Invalid header size');
    }
    final fields = <int, SaveField>{};
    var section = 0;
    for (var o = _tableStart; o < headerEnd; o += 8) {
      final hash = data.getUint32(o, Endian.little);
      final value = data.getUint32(o + 4, Endian.little);
      if (hash == 0) {
        if (value >= FieldType.values.length) {
          throw SaveFormatException('Unknown section $value');
        }
        section = value;
        continue;
      }
      if (fields.containsKey(hash)) throw SaveFormatException('Duplicate field hash');
      fields[hash] = SaveField(hash, FieldType.values[section], value);
    }
    return SaveFile._(bytes, data, headerEnd, fields);
  }

  bool has(int hash) => fields.containsKey(hash);

  /// The 64-bit key store ("Bool64bitKey"): a flag is true when its key is
  /// present. The game keeps per-actor state here, keyed by the actor's
  /// instance id, for example which Gold Skulltulas and free-standing Heart
  /// Pieces were collected. Keys are the 64 bits as a signed Dart int.
  ///
  /// The single entry of section 32 points at the sorted list of
  /// little-endian u64 keys, which ends with a zero or the end of the file.
  late final Set<int> keys64 = () {
    final keys = <int>{};
    for (final f in fields.values) {
      if (f.type != FieldType.unknown || f.raw < headerEnd) continue;
      for (var o = f.raw; o + 8 <= _bytes.length; o += 8) {
        final key = _data.getInt64(o, Endian.little);
        if (key == 0) break;
        keys.add(key);
      }
    }
    return keys;
  }();

  bool hasKey64(int key) => keys64.contains(key);

  SaveField? _field(int hash, List<FieldType> types) {
    final f = fields[hash];
    return f != null && types.contains(f.type) ? f : null;
  }

  /// Offset of the data block of [f], checked to hold [length] bytes.
  int _block(SaveField f, int length) {
    final o = f.raw;
    if (o < headerEnd || o > _bytes.length - length) {
      throw SaveFormatException('Field 0x${f.hash.toRadixString(16)} points outside the file');
    }
    return o;
  }

  bool? boolean(int hash) {
    final f = _field(hash, const [FieldType.bool_]);
    return f == null ? null : f.raw != 0;
  }

  /// Signed value of an Int field, or the value of a UInt field.
  int? integer(int hash) {
    final f = _field(hash, const [FieldType.int_, FieldType.uint]);
    if (f == null) return null;
    return f.type == FieldType.int_ ? f.raw.toSigned(32) : f.raw;
  }

  double? float(int hash) {
    final f = _field(hash, const [FieldType.float]);
    if (f == null) return null;
    return (ByteData(4)..setUint32(0, f.raw)).getFloat32(0);
  }

  /// The murmur3 hash of the enum value's name.
  int? enumHash(int hash) => _field(hash, const [FieldType.enum_])?.raw;

  String? string(int hash) {
    final f = _field(hash, const [FieldType.string32, FieldType.string64]);
    if (f == null) return null;
    final size = f.type == FieldType.string32 ? 32 : 64;
    return _text(_block(f, size), size);
  }

  String _text(int offset, int size) {
    var end = offset;
    while (end < offset + size && _bytes[end] != 0) {
      end++;
    }
    return utf8.decode(Uint8List.sublistView(_bytes, offset, end), allowMalformed: true);
  }

  List<double>? vector3(int hash) {
    final f = _field(hash, const [FieldType.vector3]);
    if (f == null) return null;
    final o = _block(f, 12);
    return [for (var i = 0; i < 3; i++) _data.getFloat32(o + i * 4, Endian.little)];
  }

  Uint8List? binary(int hash) {
    final f = _field(hash, const [FieldType.binary]);
    if (f == null) return null;
    final o = _block(f, 4);
    final size = _data.getUint32(o, Endian.little);
    _block(SaveField(f.hash, f.type, o + 4), size);
    return Uint8List.sublistView(_bytes, o + 4, o + 4 + size);
  }

  int? int64(int hash) {
    final f = _field(hash, const [FieldType.int64, FieldType.uint64]);
    if (f == null) return null;
    return _data.getInt64(_block(f, 8), Endian.little);
  }

  /// Elements of an array field: bools for BoolArray, doubles for
  /// FloatArray, strings for string arrays, ints otherwise (enum arrays give
  /// the value hashes). Null when the field is missing or not a decodable array.
  List<Object>? array(int hash) {
    final f = fields[hash];
    if (f == null) return null;
    int count(int elementSize, {int Function(int n)? bytes}) {
      final o = _block(f, 4);
      final n = _data.getUint32(o, Endian.little);
      _block(SaveField(f.hash, f.type, o + 4), bytes != null ? bytes(n) : n * elementSize);
      return n;
    }

    final o = f.raw + 4;
    switch (f.type) {
      case FieldType.boolArray:
        final n = count(0, bytes: (n) => ((n + 31) >> 5) * 4);
        return [
          for (var i = 0; i < n; i++)
            (_data.getUint32(o + (i >> 5) * 4, Endian.little) >> (i & 31)) & 1 == 1,
        ];
      case FieldType.intArray:
        final n = count(4);
        return [for (var i = 0; i < n; i++) _data.getInt32(o + i * 4, Endian.little)];
      case FieldType.uintArray || FieldType.enumArray:
        final n = count(4);
        return [for (var i = 0; i < n; i++) _data.getUint32(o + i * 4, Endian.little)];
      case FieldType.floatArray:
        final n = count(4);
        return [for (var i = 0; i < n; i++) _data.getFloat32(o + i * 4, Endian.little)];
      case FieldType.int64Array || FieldType.uint64Array:
        final n = count(8);
        return [for (var i = 0; i < n; i++) _data.getInt64(o + i * 8, Endian.little)];
      case FieldType.string64Array:
        final n = count(64);
        return [for (var i = 0; i < n; i++) _text(o + i * 64, 64)];
      default:
        return null;
    }
  }

  /// A JSON-friendly value for any field: bool, int, double, String, list,
  /// or null for types that are not decoded (binary, unknown).
  Object? value(int hash) {
    final f = fields[hash];
    if (f == null) return null;
    return switch (f.type) {
      FieldType.bool_ => f.raw != 0,
      FieldType.int_ || FieldType.uint => integer(hash),
      FieldType.float => float(hash),
      FieldType.enum_ => f.raw,
      FieldType.string32 || FieldType.string64 => string(hash),
      FieldType.vector3 => vector3(hash),
      FieldType.int64 || FieldType.uint64 => int64(hash),
      FieldType.binary || FieldType.binaryArray || FieldType.unknown => null,
      _ => array(hash),
    };
  }
}

/// Parses a 64-bit key written as hex (`0xA8D6182A5C956E16`) or decimal.
int parseKey64(String text) {
  final hex = text.startsWith('0x') || text.startsWith('0X');
  return BigInt.parse(hex ? text.substring(2) : text, radix: hex ? 16 : 10).toSigned(64).toInt();
}

/// Reads fields of a [SaveFile] by game field name.
extension NamedFields on SaveFile {
  bool? booleanNamed(String name) => boolean(murmur3(name));
  int? integerNamed(String name) => integer(murmur3(name));
  double? floatNamed(String name) => float(murmur3(name));
  String? stringNamed(String name) => string(murmur3(name));
}
