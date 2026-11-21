/// Reads BNTX texture containers (the game's `.bntx` files): the first mip
/// level of the ASTC textures the maps use, as RGBA.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'astc.dart';

class BntxTexture {
  BntxTexture(this.name, this.format, this.width, this.height, this.blockHeightLog2, this.offset, this.size, this.tile);
  final String name;
  final int format, width, height, blockHeightLog2, offset, size, tile;
}

// Format type (high byte of the format) -> ASTC block size.
const _astc = {
  0x2d: (4, 4), 0x2e: (5, 4), 0x2f: (5, 5), 0x30: (6, 5), 0x31: (6, 6), 0x32: (8, 5), 0x33: (8, 6), //
  0x34: (8, 8), 0x35: (10, 5), 0x36: (10, 6), 0x37: (10, 8), 0x38: (10, 10), 0x39: (12, 10), 0x3a: (12, 12),
};

/// Every texture in a BNTX file.
List<BntxTexture> bntxTextures(Uint8List d) {
  if (d.length < 4 || ascii.decode(d.sublist(0, 4), allowInvalid: true) != 'BNTX') {
    throw const FormatException('Not a BNTX file');
  }
  final view = ByteData.sublistView(d);
  final found = <BntxTexture>[];
  // Texture headers start with "BRTI".
  for (var i = 0; i + 0x80 <= d.length; i++) {
    if (d[i] != 0x42 || d[i + 1] != 0x52 || d[i + 2] != 0x54 || d[i + 3] != 0x49) continue;
    final nameAt = view.getUint64(i + 0x60, Endian.little), pointers = view.getUint64(i + 0x70, Endian.little);
    if (nameAt + 2 > d.length || pointers + 8 > d.length) continue;
    final nameLength = view.getUint16(nameAt, Endian.little);
    found.add(
      BntxTexture(
        utf8.decode(d.sublist(nameAt + 2, nameAt + 2 + nameLength), allowMalformed: true),
        view.getUint32(i + 0x1c, Endian.little),
        view.getUint32(i + 0x24, Endian.little),
        view.getUint32(i + 0x28, Endian.little),
        view.getUint32(i + 0x34, Endian.little),
        view.getUint64(pointers, Endian.little),
        view.getUint32(i + 0x50, Endian.little),
        view.getUint16(i + 0x12, Endian.little),
      ),
    );
  }
  return found;
}

/// Undoes the console's block-linear memory layout: [data] holds
/// [wide] x [high] blocks of [bytes] bytes each.
Uint8List _deswizzle(Uint8List data, int wide, int high, int bytes, int blockHeightLog2) {
  final bh = 1 << blockHeightLog2;
  final gobsWide = (wide * bytes + 63) ~/ 64;
  final out = Uint8List(wide * high * bytes);
  for (var y = 0; y < high; y++) {
    // Inside a 512-byte group the address bits are x0-3, y0, y1, x4, y2, x5.
    // That is this game's order (found by minimising block seams); it
    // differs from the classic Switch one.
    final row =
        (y ~/ (8 * bh)) * 512 * bh * gobsWide +
        ((y % (8 * bh)) ~/ 8) * 512 +
        ((y % 8) ~/ 4) * 128 +
        ((y % 4) ~/ 2) * 32 +
        (y % 2) * 16;
    for (var block = 0; block < wide; block++) {
      final x = block * bytes;
      final from = row + (x ~/ 64) * 512 * bh + ((x % 64) ~/ 32) * 256 + ((x % 32) ~/ 16) * 64 + (x % 16);
      final to = (y * wide + block) * bytes;
      if (from + bytes <= data.length) out.setRange(to, to + bytes, data, from);
    }
  }
  return out;
}

/// Decodes [texture] of the BNTX file [d] to RGBA, 4 bytes a pixel.
Uint8List bntxDecode(Uint8List d, BntxTexture texture) {
  final block = _astc[texture.format >> 8];
  if (block == null) {
    throw FormatException('Unsupported texture format 0x${texture.format.toRadixString(16)}');
  }
  final (bw, bh) = block;
  final wide = (texture.width + bw - 1) ~/ bw, high = (texture.height + bh - 1) ~/ bh;
  final raw = Uint8List.sublistView(d, texture.offset, texture.offset + texture.size);
  final linear = texture.tile == 0 ? _deswizzle(raw, wide, high, 16, texture.blockHeightLog2) : raw;
  return astcDecode(linear, texture.width, texture.height, bw, bh);
}
