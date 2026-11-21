/// A Zstandard decompressor in plain Dart (RFC 8878), enough for the game's
/// `.zs` files that do not use a dictionary.
library;

import 'dart:typed_data';

class ZstdException implements Exception {
  ZstdException(this.message);
  final String message;
  @override
  String toString() => 'ZstdException: $message';
}

/// The dictionary id a frame asks for; 0 if none.
int zstdDictionaryId(Uint8List data) {
  if (data.length < 6 || ByteData.sublistView(data).getUint32(0, Endian.little) != 0xFD2FB528) return 0;
  final descriptor = data[4];
  final idSize = const [0, 1, 2, 4][descriptor & 3];
  var at = 5 + ((descriptor & 0x20) != 0 ? 0 : 1);
  var id = 0;
  for (var i = 0; i < idSize; i++) {
    id |= data[at++] << (8 * i);
  }
  return id;
}

/// Decompresses every frame in [data].
Uint8List zstdDecompress(Uint8List data) => _Decoder(data).run();

int _highBit(int v) => v.bitLength - 1;

/// Reads bits from the end of a buffer towards its start, as zstd's entropy
/// streams are written.
class _BackBits {
  _BackBits(this.d, this.start, int end) {
    if (end <= start || d[end - 1] == 0) throw ZstdException('Corrupt bitstream');
    // The last byte ends with a 1 bit that marks the end of the data.
    pos = (end - start) * 8 - (8 - _highBit(d[end - 1]));
  }
  final Uint8List d;
  final int start;

  /// Bits left to read; negative once more was read than there is.
  late int pos;

  @pragma('vm:prefer-inline')
  int peek(int n) {
    if (n == 0) return 0;
    final from = pos - n;
    if (from < 0) return _peekSlow(n);
    final byte = start + (from >> 3), shift = from & 7;
    // Up to 5 bytes cover 32 bits at any shift.
    var v = d[byte];
    final last = start + ((pos - 1) >> 3);
    for (var i = 1, b = byte + 1; b <= last; i++, b++) {
      v |= d[b] << (8 * i);
    }
    return (v >> shift) & ((1 << n) - 1);
  }

  // Past the start of the stream: the missing bits read as zero.
  int _peekSlow(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final bit = pos - 1 - i;
      v <<= 1;
      if (bit >= 0) v |= (d[start + (bit >> 3)] >> (bit & 7)) & 1;
    }
    return v;
  }

  @pragma('vm:prefer-inline')
  int read(int n) {
    final v = peek(n);
    pos -= n;
    return v;
  }
}

/// An FSE decoding table.
class _Fse {
  _Fse(this.log, int size) : symbol = Uint8List(size), bits = Uint8List(size), base = Uint16List(size);
  final int log;
  final Uint8List symbol, bits;
  final Uint16List base;

  factory _Fse.rle(int symbol) => _Fse(0, 1)..symbol[0] = symbol;

  factory _Fse.build(List<int> norm, int log) {
    final size = 1 << log;
    final t = _Fse(log, size);
    final next = List<int>.filled(norm.length, 0);
    var high = size - 1;
    for (var s = 0; s < norm.length; s++) {
      if (norm[s] == -1) {
        t.symbol[high--] = s;
        next[s] = 1;
      } else {
        next[s] = norm[s];
      }
    }
    final step = (size >> 1) + (size >> 3) + 3, mask = size - 1;
    var pos = 0;
    for (var s = 0; s < norm.length; s++) {
      for (var i = 0; i < norm[s]; i++) {
        t.symbol[pos] = s;
        do {
          pos = (pos + step) & mask;
        } while (pos > high);
      }
    }
    if (pos != 0) throw ZstdException('Corrupt FSE table');
    for (var u = 0; u < size; u++) {
      final x = next[t.symbol[u]]++;
      final nb = log - _highBit(x);
      t.bits[u] = nb;
      t.base[u] = (x << nb) - size;
    }
    return t;
  }
}

const _llNorm = [4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1];
const _mlNorm = [
  1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1,
];
const _ofNorm = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1];

const _llBase = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, //
  1024, 2048, 4096, 8192, 16384, 32768, 65536,
];
const _llBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
];
const _mlBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, //
  33, 34, 35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539,
];
const _mlBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, //
  3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
];

class _Decoder {
  _Decoder(this.d);
  final Uint8List d;
  int at = 0;

  Uint8List out = Uint8List(0);
  int n = 0;

  // State that lives for one frame.
  int frameStart = 0;
  final rep = [1, 4, 8];
  _Fse? ll, of, ml;
  Uint8List? huffSymbol, huffBits;
  int huffLog = 0;
  Uint8List literals = Uint8List(0);
  int literalCount = 0;

  int u8() => d[at++];
  int le(int bytes) {
    var v = 0;
    for (var i = 0; i < bytes; i++) {
      v |= d[at++] << (8 * i);
    }
    return v;
  }

  void reserve(int extra) {
    if (n + extra <= out.length) return;
    var size = out.length < 1 << 16 ? 1 << 16 : out.length;
    while (size < n + extra) {
      size *= 2;
    }
    out = Uint8List(size)..setRange(0, n, out);
  }

  Uint8List run() {
    try {
      while (at + 4 <= d.length) {
        final magic = le(4);
        if (magic & 0xFFFFFFF0 == 0x184D2A50) {
          at += le(4); // skippable frame
          continue;
        }
        if (magic != 0xFD2FB528) throw ZstdException('Not zstd data');
        frame();
      }
    } on RangeError {
      throw ZstdException('Truncated data');
    }
    return n == out.length ? out : Uint8List.sublistView(out, 0, n);
  }

  void frame() {
    final descriptor = u8();
    final single = descriptor & 0x20 != 0;
    if (!single) u8(); // window descriptor
    final dictionary = le(const [0, 1, 2, 4][descriptor & 3]);
    if (dictionary != 0) throw ZstdException('Data needs dictionary $dictionary');
    final sizeFlag = descriptor >> 6;
    final sizeBytes = sizeFlag == 0 ? (single ? 1 : 0) : 1 << sizeFlag;
    if (sizeBytes > 0) {
      var size = le(sizeBytes);
      if (sizeBytes == 2) size += 256;
      if (size < 0 || size > 1 << 31) throw ZstdException('Unreasonable size');
      reserve(size);
    }
    frameStart = n;
    rep
      ..[0] = 1
      ..[1] = 4
      ..[2] = 8;
    ll = of = ml = null;
    huffSymbol = null;

    for (var last = false; !last;) {
      final header = le(3);
      last = header & 1 != 0;
      final type = (header >> 1) & 3, size = header >> 3;
      switch (type) {
        case 0:
          reserve(size);
          out.setRange(n, n + size, d, at);
          n += size;
          at += size;
        case 1:
          reserve(size);
          out.fillRange(n, n + size, u8());
          n += size;
        case 2:
          final end = at + size;
          if (end > d.length) throw ZstdException('Truncated data');
          block(end);
          at = end;
        default:
          throw ZstdException('Reserved block type');
      }
    }
    if (descriptor & 4 != 0) at += 4; // content checksum, not verified
  }

  void block(int end) {
    readLiterals(end);
    sequences(end);
  }

  void readLiterals(int end) {
    final b0 = d[at];
    final type = b0 & 3, format = (b0 >> 2) & 3;
    if (type < 2) {
      final int size;
      if (format == 1) {
        size = le(2) >> 4;
      } else if (format == 3) {
        size = le(3) >> 4;
      } else {
        size = u8() >> 3;
      }
      if (literals.length < size) literals = Uint8List(size);
      if (type == 0) {
        literals.setRange(0, size, d, at);
        at += size;
      } else {
        literals.fillRange(0, size, u8());
      }
      literalCount = size;
      return;
    }
    final int size, compressed;
    final streams = format == 0 ? 1 : 4;
    if (format < 2) {
      final h = le(3);
      size = (h >> 4) & 0x3FF;
      compressed = h >> 14;
    } else if (format == 2) {
      final h = le(4);
      size = (h >> 4) & 0x3FFF;
      compressed = h >> 18;
    } else {
      final h = le(5);
      size = (h >> 4) & 0x3FFFF;
      compressed = h >> 22;
    }
    final stop = at + compressed;
    if (stop > end) throw ZstdException('Corrupt literals');
    if (type == 2) {
      readHuffman();
    } else if (huffSymbol == null) {
      throw ZstdException('Literals reuse a table that was never sent');
    }
    if (literals.length < size) literals = Uint8List(size);
    literalCount = size;
    if (streams == 1) {
      huffStream(at, stop, 0, size);
    } else {
      final s1 = le(2), s2 = le(2), s3 = le(2);
      final quarter = (size + 3) >> 2;
      final a = at, b = a + s1, c = b + s2, e = c + s3;
      if (e > stop) throw ZstdException('Corrupt literals');
      huffStream(a, b, 0, quarter);
      huffStream(b, c, quarter, quarter);
      huffStream(c, e, 2 * quarter, quarter);
      huffStream(e, stop, 3 * quarter, size - 3 * quarter);
    }
    at = stop;
  }

  void huffStream(int from, int to, int offset, int count) {
    final bits = _BackBits(d, from, to);
    final symbol = huffSymbol!, lengths = huffBits!, log = huffLog, lit = literals;
    for (var i = 0; i < count; i++) {
      final index = bits.peek(log);
      lit[offset + i] = symbol[index];
      bits.pos -= lengths[index];
    }
    if (bits.pos != 0) throw ZstdException('Corrupt literals');
  }

  void readHuffman() {
    final header = u8();
    final weights = <int>[];
    if (header >= 128) {
      final count = header - 127;
      for (var i = 0; i < count; i++) {
        final byte = d[at + (i >> 1)];
        weights.add(i.isEven ? byte >> 4 : byte & 15);
      }
      at += (count + 1) >> 1;
    } else {
      final stop = at + header;
      final table = readFse(6, 255);
      final bits = _BackBits(d, at, stop);
      var s1 = bits.read(table.log), s2 = bits.read(table.log);
      while (true) {
        weights.add(table.symbol[s1]);
        s1 = table.base[s1] + bits.read(table.bits[s1]);
        if (bits.pos < 0) {
          weights.add(table.symbol[s2]);
          break;
        }
        weights.add(table.symbol[s2]);
        s2 = table.base[s2] + bits.read(table.bits[s2]);
        if (bits.pos < 0) {
          weights.add(table.symbol[s1]);
          break;
        }
        if (weights.length > 255) throw ZstdException('Corrupt Huffman table');
      }
      at = stop;
    }
    var sum = 0;
    for (final w in weights) {
      if (w > 11) throw ZstdException('Corrupt Huffman table');
      if (w > 0) sum += 1 << (w - 1);
    }
    if (sum == 0) throw ZstdException('Corrupt Huffman table');
    final log = _highBit(sum) + 1;
    final left = (1 << log) - sum;
    if (left & (left - 1) != 0) throw ZstdException('Corrupt Huffman table');
    weights.add(_highBit(left) + 1);
    if (log > 11) throw ZstdException('Corrupt Huffman table');

    final size = 1 << log;
    final symbol = Uint8List(size), lengths = Uint8List(size);
    var pos = 0;
    for (var w = 1; w <= log; w++) {
      final span = 1 << (w - 1);
      for (var s = 0; s < weights.length; s++) {
        if (weights[s] != w) continue;
        symbol.fillRange(pos, pos + span, s);
        lengths.fillRange(pos, pos + span, log + 1 - w);
        pos += span;
      }
    }
    huffSymbol = symbol;
    huffBits = lengths;
    huffLog = log;
  }

  /// Reads an FSE table description at [at] and moves past it.
  _Fse readFse(int maxLog, int maxSymbol) {
    var bitAt = at * 8;
    int take(int count) {
      var v = 0;
      for (var i = 0; i < count; i++, bitAt++) {
        v |= ((d[bitAt >> 3] >> (bitAt & 7)) & 1) << i;
      }
      return v;
    }

    final log = take(4) + 5;
    if (log > maxLog) throw ZstdException('Corrupt FSE table');
    var remaining = (1 << log) + 1, threshold = 1 << log, nbBits = log + 1;
    final norm = <int>[];
    while (remaining > 1 && norm.length <= maxSymbol) {
      final max = (2 * threshold - 1) - remaining;
      final low = take(nbBits - 1);
      int count;
      if (low < max) {
        count = low;
      } else {
        count = low | (take(1) << (nbBits - 1));
        if (count >= threshold) count -= max;
      }
      count--;
      remaining -= count < 0 ? -count : count;
      norm.add(count);
      if (count == 0) {
        for (var repeat = 3; repeat == 3;) {
          repeat = take(2);
          for (var i = 0; i < repeat; i++) {
            norm.add(0);
          }
        }
      }
      while (remaining < threshold) {
        nbBits--;
        threshold >>= 1;
      }
    }
    if (remaining != 1 || norm.length > maxSymbol + 1) throw ZstdException('Corrupt FSE table');
    at = (bitAt + 7) >> 3;
    return _Fse.build(norm, log);
  }

  _Fse table(int mode, _Fse? previous, List<int> predefined, int predefinedLog, int maxLog, int maxSymbol) {
    switch (mode) {
      case 0:
        return _Fse.build(predefined, predefinedLog);
      case 1:
        return _Fse.rle(u8());
      case 2:
        return readFse(maxLog, maxSymbol);
      default:
        if (previous == null) throw ZstdException('Sequences reuse a table that was never sent');
        return previous;
    }
  }

  void sequences(int end) {
    var count = u8();
    if (count >= 128) {
      count = count == 255 ? le(2) + 0x7F00 : ((count - 128) << 8) + u8();
    }
    final lit = literals;
    if (count == 0) {
      reserve(literalCount);
      out.setRange(n, n + literalCount, lit);
      n += literalCount;
      return;
    }
    final modes = u8();
    final llT = ll = table(modes >> 6, ll, _llNorm, 6, 9, 35);
    final ofT = of = table((modes >> 4) & 3, of, _ofNorm, 5, 8, 31);
    final mlT = ml = table((modes >> 2) & 3, ml, _mlNorm, 6, 9, 52);

    final bits = _BackBits(d, at, end);
    var llS = bits.read(llT.log), ofS = bits.read(ofT.log), mlS = bits.read(mlT.log);
    var litAt = 0;
    final r = rep;
    for (var i = 0; i < count; i++) {
      final ofCode = ofT.symbol[ofS], mlCode = mlT.symbol[mlS], llCode = llT.symbol[llS];
      // Offsets can need more than 32 bits' worth in two reads.
      var offset = ofCode > 24
          ? (1 << ofCode) + (bits.read(ofCode - 16) << 16) + bits.read(16)
          : (1 << ofCode) + bits.read(ofCode);
      final matchLength = _mlBase[mlCode] + bits.read(_mlBits[mlCode]);
      final literalLength = _llBase[llCode] + bits.read(_llBits[llCode]);
      if (i + 1 < count) {
        llS = llT.base[llS] + bits.read(llT.bits[llS]);
        mlS = mlT.base[mlS] + bits.read(mlT.bits[mlS]);
        ofS = ofT.base[ofS] + bits.read(ofT.bits[ofS]);
      }

      if (offset > 3) {
        offset -= 3;
        r[2] = r[1];
        r[1] = r[0];
        r[0] = offset;
      } else {
        final index = literalLength == 0 ? offset : offset - 1;
        if (index == 0) {
          offset = r[0];
        } else {
          offset = index == 3 ? r[0] - 1 : r[index];
          if (index > 1) r[2] = r[1];
          r[1] = r[0];
          r[0] = offset;
        }
      }

      if (litAt + literalLength > literalCount) throw ZstdException('Corrupt sequences');
      reserve(literalLength + matchLength);
      final o = out;
      var w = n;
      for (var k = 0; k < literalLength; k++) {
        o[w++] = lit[litAt++];
      }
      var from = w - offset;
      if (offset <= 0 || from < frameStart) throw ZstdException('Corrupt sequences');
      if (offset >= matchLength) {
        o.setRange(w, w + matchLength, o, from);
        w += matchLength;
      } else {
        for (var k = 0; k < matchLength; k++) {
          o[w++] = o[from++];
        }
      }
      n = w;
    }
    if (bits.pos < 0) throw ZstdException('Corrupt sequences');
    final rest = literalCount - litAt;
    reserve(rest);
    out.setRange(n, n + rest, lit, litAt);
    n += rest;
  }
}
