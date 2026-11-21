/// An ASTC texture decoder in plain Dart: 2D blocks, LDR profile, decoded
/// the sRGB way (8 bits per channel, as stored). Blocks that are invalid or
/// use HDR endpoints come out magenta, as the format prescribes.
library;

import 'dart:typed_data';

/// Decodes [data] (16 bytes per block, row by row) to RGBA, 4 bytes a pixel.
Uint8List astcDecode(Uint8List data, int width, int height, int blockWidth, int blockHeight) {
  final out = Uint8List(width * height * 4);
  final blocksX = (width + blockWidth - 1) ~/ blockWidth, blocksY = (height + blockHeight - 1) ~/ blockHeight;
  final block = _Block(blockWidth, blockHeight);
  final pixels = block.pixels;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      block.decode(data, (by * blocksX + bx) * 16);
      final rows = by * blockHeight + blockHeight > height ? height - by * blockHeight : blockHeight;
      final columns = bx * blockWidth + blockWidth > width ? width - bx * blockWidth : blockWidth;
      for (var y = 0; y < rows; y++) {
        final to = ((by * blockHeight + y) * width + bx * blockWidth) * 4;
        final from = y * blockWidth * 4;
        out.setRange(to, to + columns * 4, pixels, from);
      }
    }
  }
  return out;
}

// Bit reversal of a byte.
final Uint8List _reverse = Uint8List.fromList([
  for (var i = 0; i < 256; i++)
    ((i & 1) << 7) |
        ((i & 2) << 5) |
        ((i & 4) << 3) |
        ((i & 8) << 1) |
        ((i & 16) >> 1) |
        ((i & 32) >> 3) |
        ((i & 64) >> 5) |
        ((i & 128) >> 7),
]);

// Trit and quint blocks unpacked once: 5 trits per 8 bits, 3 quints per 7.
final List<Uint8List> _trits = [for (var t = 0; t < 256; t++) _unpackTrits(t)];
final List<Uint8List> _quints = [for (var q = 0; q < 128; q++) _unpackQuints(q)];

Uint8List _unpackTrits(int t) {
  int bit(int v, int i) => (v >> i) & 1;
  int t0, t1, t2, t3, t4, c;
  if ((t >> 2) & 7 == 7) {
    c = ((t >> 5) << 2) | (t & 3);
    t4 = t3 = 2;
  } else {
    c = t & 0x1F;
    if ((t >> 5) & 3 == 3) {
      t4 = 2;
      t3 = bit(t, 7);
    } else {
      t4 = bit(t, 7);
      t3 = (t >> 5) & 3;
    }
  }
  if (c & 3 == 3) {
    t2 = 2;
    t1 = bit(c, 4);
    t0 = (bit(c, 3) << 1) | (bit(c, 2) & ~bit(c, 3) & 1);
  } else if ((c >> 2) & 3 == 3) {
    t2 = 2;
    t1 = 2;
    t0 = c & 3;
  } else {
    t2 = bit(c, 4);
    t1 = (c >> 2) & 3;
    t0 = (bit(c, 1) << 1) | (bit(c, 0) & ~bit(c, 1) & 1);
  }
  return Uint8List.fromList([t0, t1, t2, t3, t4]);
}

Uint8List _unpackQuints(int q) {
  int bit(int v, int i) => (v >> i) & 1;
  int q0, q1, q2;
  if ((q >> 1) & 3 == 3 && (q >> 5) & 3 == 0) {
    final n = ~bit(q, 0) & 1;
    q2 = (bit(q, 0) << 2) | ((bit(q, 4) & n) << 1) | (bit(q, 3) & n);
    q1 = q0 = 4;
  } else {
    int c;
    if ((q >> 1) & 3 == 3) {
      q2 = 4;
      c = (((q >> 3) & 3) << 3) | ((~(q >> 5) & 3) << 1) | bit(q, 0);
    } else {
      q2 = (q >> 5) & 3;
      c = q & 0x1F;
    }
    if (c & 7 == 5) {
      q1 = 4;
      q0 = (c >> 3) & 3;
    } else {
      q1 = (c >> 3) & 3;
      q0 = c & 7;
    }
  }
  return Uint8List.fromList([q0, q1, q2]);
}

/// How values are packed: one trit or one quint (or neither) plus [bits].
class _Range {
  const _Range(this.trits, this.quints, this.bits);
  final int trits, quints, bits;

  int size(int count) =>
      bits * count + (trits != 0 ? (8 * count + 4) ~/ 5 : 0) + (quints != 0 ? (7 * count + 2) ~/ 3 : 0);
}

// Weight ranges by the block mode's R (2..7), without and with the H bit.
const _weightRanges = [
  [_Range(0, 0, 1), _Range(1, 0, 0), _Range(0, 0, 2), _Range(0, 1, 0), _Range(1, 0, 1), _Range(0, 0, 3)],
  [_Range(0, 1, 1), _Range(1, 0, 2), _Range(0, 0, 4), _Range(0, 1, 2), _Range(1, 0, 3), _Range(0, 0, 5)],
];

// Colour ranges from finest (0..255) to coarsest (0..5).
const _colorRanges = [
  _Range(0, 0, 8), _Range(1, 0, 6), _Range(0, 1, 5), _Range(0, 0, 7), _Range(1, 0, 5), _Range(0, 1, 4), //
  _Range(0, 0, 6), _Range(1, 0, 4), _Range(0, 1, 3), _Range(0, 0, 5), _Range(1, 0, 3), _Range(0, 1, 2),
  _Range(0, 0, 4), _Range(1, 0, 2), _Range(0, 1, 1), _Range(0, 0, 3), _Range(1, 0, 1),
];

int _hash52(int p) {
  p &= 0xFFFFFFFF;
  p ^= p >> 15;
  p = (p - (p << 17)) & 0xFFFFFFFF;
  p = (p + (p << 7)) & 0xFFFFFFFF;
  p = (p + (p << 4)) & 0xFFFFFFFF;
  p ^= p >> 5;
  p = (p + (p << 16)) & 0xFFFFFFFF;
  p ^= p >> 7;
  p ^= p >> 3;
  p = (p ^ (p << 6)) & 0xFFFFFFFF;
  p ^= p >> 17;
  return p;
}

class _Block {
  _Block(this.bw, this.bh) : pixels = Uint8List(bw * bh * 4), small = bw * bh < 31;
  final int bw, bh;
  final bool small;

  /// The decoded block, RGBA, [bw] pixels per row.
  final Uint8List pixels;

  final Uint8List _bytes = Uint8List(16), _flipped = Uint8List(16);
  final Uint8List _hi = Uint8List(64), _lo = Uint8List(64); // trit/quint and bits of each value
  final Uint8List _weights = Uint8List(128);
  final Int32List _colors = Int32List(18);
  final Int32List _ends = Int32List(4 * 8); // per partition: e0 rgba, e1 rgba
  final Uint8List _modes = Uint8List(4);

  int _bits(Uint8List b, int at, int count) {
    var v = 0;
    for (var i = 0; i < count; i++, at++) {
      v |= ((b[at >> 3] >> (at & 7)) & 1) << i;
    }
    return v;
  }

  /// Unpacks [count] values of [range] starting at bit [at] of [b] into
  /// [_hi] (the trit or quint) and [_lo] (the plain bits).
  void _unpack(Uint8List b, int at, int count, _Range range) {
    final bits = range.bits;
    if (range.trits != 0) {
      for (var i = 0; i < count; i += 5) {
        // m0 T0T1 m1 T2T3 m2 T4 m3 T5T6 m4 T7; a short last group ends early.
        var t = 0;
        const width = [2, 2, 1, 2, 1], shift = [0, 2, 4, 5, 7];
        for (var k = 0; k < 5 && i + k < count; k++) {
          _lo[i + k] = _bits(b, at, bits);
          at += bits;
          t |= _bits(b, at, width[k]) << shift[k];
          at += width[k];
        }
        final values = _trits[t];
        for (var k = 0; k < 5 && i + k < count; k++) {
          _hi[i + k] = values[k];
        }
      }
    } else if (range.quints != 0) {
      for (var i = 0; i < count; i += 3) {
        var q = 0;
        const width = [3, 2, 2], shift = [0, 3, 5];
        for (var k = 0; k < 3 && i + k < count; k++) {
          _lo[i + k] = _bits(b, at, bits);
          at += bits;
          q |= _bits(b, at, width[k]) << shift[k];
          at += width[k];
        }
        final values = _quints[q];
        for (var k = 0; k < 3 && i + k < count; k++) {
          _hi[i + k] = values[k];
        }
      }
    } else {
      for (var i = 0; i < count; i++, at += bits) {
        _lo[i] = _bits(b, at, bits);
        _hi[i] = 0;
      }
    }
  }

  void _fill(int r, int g, int b, int a) {
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = a;
    }
  }

  void _error() => _fill(255, 0, 255, 255);

  static int _colorValue(_Range range, int hi, int lo) {
    final bits = range.bits;
    if (range.trits == 0 && range.quints == 0) {
      // Replicate the bits to fill a byte.
      var v = lo << (8 - bits);
      for (var filled = bits; filled < 8; filled *= 2) {
        v |= v >> filled;
      }
      return v & 0xFF;
    }
    final a = (lo & 1) != 0 ? 0x1FF : 0;
    final x = lo >> 1; // the bits above the lowest
    int b, c;
    if (range.trits != 0) {
      switch (bits) {
        case 1:
          c = 204;
          b = 0;
        case 2:
          c = 93;
          b = x * 0x116; // b000b0bb0
        case 3:
          c = 44;
          b = (x << 7) | (x << 2) | x; // cb000cbcb
        case 4:
          c = 22;
          b = (x << 6) | x; // dcb000dcb
        case 5:
          c = 11;
          b = (x << 5) | (x >> 2); // edcb000ed
        default:
          c = 5;
          b = (x << 4) | (x >> 4); // fedcb000f
      }
    } else {
      switch (bits) {
        case 1:
          c = 113;
          b = 0;
        case 2:
          c = 54;
          b = x * 0x10C; // b0000bb00
        case 3:
          c = 26;
          b = (x << 7) | (x << 1) | (x >> 1); // cb0000cbc
        case 4:
          c = 13;
          b = (x << 6) | (x >> 1); // dcb0000dc
        default:
          c = 6;
          b = (x << 5) | (x >> 3); // edcb0000e
      }
    }
    var t = (hi * c + b) ^ a;
    t = (a & 0x80) | (t >> 2);
    return t & 0xFF;
  }

  static int _weightValue(_Range range, int hi, int lo) {
    final bits = range.bits;
    int v;
    if (range.trits == 0 && range.quints == 0) {
      v = lo << (6 - bits);
      for (var filled = bits; filled < 6; filled *= 2) {
        v |= v >> filled;
      }
      v &= 0x3F;
    } else if (bits == 0) {
      v = range.trits != 0 ? const [0, 32, 63][hi] : const [0, 16, 32, 47, 63][hi];
    } else {
      final a = (lo & 1) != 0 ? 0x7F : 0;
      final x = lo >> 1;
      int b, c;
      if (range.trits != 0) {
        switch (bits) {
          case 1:
            c = 50;
            b = 0;
          case 2:
            c = 23;
            b = x * 0x45; // b000b0b
          default:
            c = 11;
            b = (x << 5) | x; // cb000cb
        }
      } else {
        if (bits == 1) {
          c = 28;
          b = 0;
        } else {
          c = 13;
          b = x * 0x42; // b0000b0
        }
      }
      final t = (hi * c + b) ^ a;
      v = (a & 0x20) | (t >> 2);
    }
    return v > 32 ? v + 1 : v;
  }

  int _partition(int seed, int x, int y, int count) {
    if (small) {
      x <<= 1;
      y <<= 1;
    }
    seed += (count - 1) * 1024;
    final r = _hash52(seed);
    var s1 = r & 0xF, s2 = (r >> 4) & 0xF, s3 = (r >> 8) & 0xF, s4 = (r >> 12) & 0xF;
    var s5 = (r >> 16) & 0xF, s6 = (r >> 20) & 0xF, s7 = (r >> 24) & 0xF, s8 = (r >> 28) & 0xF;
    s1 *= s1;
    s2 *= s2;
    s3 *= s3;
    s4 *= s4;
    s5 *= s5;
    s6 *= s6;
    s7 *= s7;
    s8 *= s8;
    int sh1, sh2;
    if (seed & 1 != 0) {
      sh1 = seed & 2 != 0 ? 4 : 5;
      sh2 = count == 3 ? 6 : 5;
    } else {
      sh1 = count == 3 ? 6 : 5;
      sh2 = seed & 2 != 0 ? 4 : 5;
    }
    s1 >>= sh1;
    s2 >>= sh2;
    s3 >>= sh1;
    s4 >>= sh2;
    s5 >>= sh1;
    s6 >>= sh2;
    s7 >>= sh1;
    s8 >>= sh2;
    final a = (s1 * x + s2 * y + (r >> 14)) & 0x3F;
    final b = (s3 * x + s4 * y + (r >> 10)) & 0x3F;
    final c = count < 3 ? 0 : (s5 * x + s6 * y + (r >> 6)) & 0x3F;
    final d = count < 4 ? 0 : (s7 * x + s8 * y + (r >> 2)) & 0x3F;
    if (a >= b && a >= c && a >= d) return 0;
    if (b >= c && b >= d) return 1;
    return c >= d ? 2 : 3;
  }

  static int _clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  /// Turns the colour values from [at] on into the two endpoints of
  /// partition [p]. Returns false for the HDR modes.
  bool _endpoints(int mode, int at, int p) {
    final v = _colors, e = _ends, o = p * 8;
    void set(int r0, int g0, int b0, int a0, int r1, int g1, int b1, int a1) {
      e[o] = _clamp(r0);
      e[o + 1] = _clamp(g0);
      e[o + 2] = _clamp(b0);
      e[o + 3] = _clamp(a0);
      e[o + 4] = _clamp(r1);
      e[o + 5] = _clamp(g1);
      e[o + 6] = _clamp(b1);
      e[o + 7] = _clamp(a1);
    }

    // Blue contraction, with the two endpoints swapped.
    void contracted(int r0, int g0, int b0, int a0, int r1, int g1, int b1, int a1) =>
        set((r1 + b1) >> 1, (g1 + b1) >> 1, b1, a1, (r0 + b0) >> 1, (g0 + b0) >> 1, b0, a0);

    // bit_transfer_signed: moves the top bit of a into b, leaves a signed.
    int a0 = 0, b0 = 0;
    void transfer(int a, int b) {
      b = (b >> 1) | (a & 0x80);
      a = (a >> 1) & 0x3F;
      if (a & 0x20 != 0) a -= 0x40;
      a0 = a;
      b0 = b;
    }

    final v0 = v[at], v1 = v[at + 1];
    switch (mode) {
      case 0:
        set(v0, v0, v0, 255, v1, v1, v1, 255);
      case 1:
        final l0 = (v0 >> 2) | (v1 & 0xC0);
        final l1 = l0 + (v1 & 0x3F);
        set(l0, l0, l0, 255, l1, l1, l1, 255);
      case 4:
        set(v0, v0, v0, v[at + 2], v1, v1, v1, v[at + 3]);
      case 5:
        transfer(v1, v0);
        final l = b0, dl = a0;
        transfer(v[at + 3], v[at + 2]);
        set(l, l, l, b0, l + dl, l + dl, l + dl, b0 + a0);
      case 6:
        final s = v[at + 3];
        set((v0 * s) >> 8, (v1 * s) >> 8, (v[at + 2] * s) >> 8, 255, v0, v1, v[at + 2], 255);
      case 8:
      case 12:
        final alpha0 = mode == 12 ? v[at + 6] : 255, alpha1 = mode == 12 ? v[at + 7] : 255;
        if (v1 + v[at + 3] + v[at + 5] >= v0 + v[at + 2] + v[at + 4]) {
          set(v0, v[at + 2], v[at + 4], alpha0, v1, v[at + 3], v[at + 5], alpha1);
        } else {
          contracted(v0, v[at + 2], v[at + 4], alpha0, v1, v[at + 3], v[at + 5], alpha1);
        }
      case 9:
      case 13:
        transfer(v1, v0);
        final r = b0, dr = a0;
        transfer(v[at + 3], v[at + 2]);
        final g = b0, dg = a0;
        transfer(v[at + 5], v[at + 4]);
        final b = b0, db = a0;
        var al = 255, da = 0;
        if (mode == 13) {
          transfer(v[at + 7], v[at + 6]);
          al = b0;
          da = a0;
        }
        if (dr + dg + db >= 0) {
          set(r, g, b, al, r + dr, g + dg, b + db, al + da);
        } else {
          contracted(r, g, b, al, r + dr, g + dg, b + db, al + da);
        }
      case 10:
        final s = v[at + 3];
        set((v0 * s) >> 8, (v1 * s) >> 8, (v[at + 2] * s) >> 8, v[at + 4], v0, v1, v[at + 2], v[at + 5]);
      default:
        return false;
    }
    return true;
  }

  void decode(Uint8List data, int offset) {
    final b = _bytes;
    b.setRange(0, 16, data, offset);
    final mode = b[0] | ((b[1] & 7) << 8);

    if (mode & 0x1FF == 0x1FC) {
      // Void extent: one colour for the whole block.
      if (mode & 0x200 != 0) return _error(); // HDR
      return _fill(b[9], b[11], b[13], b[15]);
    }

    // ---- block mode: weight grid size, weight range, dual plane
    int w, h, r;
    var dual = (mode >> 10) & 1 != 0, high = (mode >> 9) & 1;
    if (mode & 3 != 0) {
      r = ((mode >> 4) & 1) | ((mode & 3) << 1);
      final a = (mode >> 5) & 3, bb = (mode >> 7) & 3;
      switch ((mode >> 2) & 3) {
        case 0:
          w = bb + 4;
          h = a + 2;
        case 1:
          w = bb + 8;
          h = a + 2;
        case 2:
          w = a + 2;
          h = bb + 8;
        default:
          if (bb & 2 != 0) {
            w = (bb & 1) + 2;
            h = a + 2;
          } else {
            w = a + 2;
            h = (bb & 1) + 6;
          }
      }
    } else {
      r = ((mode >> 4) & 1) | (((mode >> 2) & 3) << 1);
      if ((mode >> 2) & 3 == 0) return _error();
      final a = (mode >> 5) & 3, bb = (mode >> 9) & 3;
      switch ((mode >> 7) & 3) {
        case 0:
          w = 12;
          h = a + 2;
        case 1:
          w = a + 2;
          h = 12;
        case 2:
          w = a + 6;
          h = bb + 6;
          dual = false;
          high = 0;
        default:
          if ((mode >> 5) & 3 == 0) {
            w = 6;
            h = 10;
          } else if ((mode >> 5) & 3 == 1) {
            w = 10;
            h = 6;
          } else {
            return _error();
          }
      }
    }
    if (r < 2 || w > bw || h > bh) return _error();
    final weightRange = _weightRanges[high][r - 2];
    final weightCount = w * h * (dual ? 2 : 1);
    final weightBits = weightRange.size(weightCount);
    if (weightCount > 64 || weightBits < 24 || weightBits > 96) return _error();

    // ---- partitions and colour endpoint modes
    final partitions = _bits(b, 11, 2) + 1;
    if (dual && partitions == 4) return _error();
    var colorStart = 17, belowWeights = 128 - weightBits, seed = 0;
    if (partitions == 1) {
      _modes[0] = _bits(b, 13, 4);
    } else {
      seed = _bits(b, 13, 10);
      var cem = _bits(b, 23, 6);
      colorStart = 29;
      if (cem & 3 == 0) {
        for (var i = 0; i < partitions; i++) {
          _modes[i] = cem >> 2;
        }
      } else {
        // The rest of the mode bits sits right below the weights.
        final extra = 3 * partitions - 4;
        belowWeights -= extra;
        cem |= _bits(b, belowWeights, extra) << 6;
        final baseClass = (cem & 3) - 1;
        for (var i = 0; i < partitions; i++) {
          final c = (cem >> (2 + i)) & 1, m = (cem >> (2 + partitions + 2 * i)) & 3;
          _modes[i] = ((baseClass + c) << 2) | m;
        }
      }
    }
    var plane2 = -1;
    if (dual) {
      belowWeights -= 2;
      plane2 = _bits(b, belowWeights, 2);
    }

    // ---- colour values: the finest range that fits the bits left over
    var valueCount = 0;
    for (var i = 0; i < partitions; i++) {
      valueCount += ((_modes[i] >> 2) + 1) * 2;
    }
    final colorBits = belowWeights - colorStart;
    if (valueCount > 18 || colorBits < (13 * valueCount + 4) ~/ 5) return _error();
    _Range? colorRange;
    for (final range in _colorRanges) {
      if (range.size(valueCount) <= colorBits) {
        colorRange = range;
        break;
      }
    }
    if (colorRange == null) return _error();
    _unpack(b, colorStart, valueCount, colorRange);
    for (var i = 0; i < valueCount; i++) {
      _colors[i] = _colorValue(colorRange, _hi[i], _lo[i]);
    }
    for (var i = 0, at = 0; i < partitions; i++) {
      if (!_endpoints(_modes[i], at, i)) return _error();
      at += ((_modes[i] >> 2) + 1) * 2;
    }

    // ---- weights: stored from the top of the block, bits reversed
    final f = _flipped;
    for (var i = 0; i < 16; i++) {
      f[i] = _reverse[b[15 - i]];
    }
    _unpack(f, 0, weightCount, weightRange);
    for (var i = 0; i < weightCount; i++) {
      _weights[i] = _weightValue(weightRange, _hi[i], _lo[i]);
    }

    // ---- pixels: infill the weight grid, pick the partition, interpolate
    final ds = (1024 + bw ~/ 2) ~/ (bw - 1), dt = (1024 + bh ~/ 2) ~/ (bh - 1);
    final planes = dual ? 2 : 1;
    final ends = _ends, weights = _weights, px = pixels;
    for (var y = 0; y < bh; y++) {
      final gt = (dt * y * (h - 1) + 32) >> 6;
      final jt = gt >> 4, ft = gt & 0xF;
      for (var x = 0; x < bw; x++) {
        final gs = (ds * x * (w - 1) + 32) >> 6;
        final js = gs >> 4, fs = gs & 0xF;
        final w11 = (fs * ft + 8) >> 4;
        final w10 = ft - w11, w01 = fs - w11, w00 = 16 - fs - ft + w11;
        final v0 = js + jt * w;
        var weight0 = 0, weight1 = 0;
        for (var plane = 0; plane < planes; plane++) {
          int at(int index) => index < w * h ? weights[index * planes + plane] : 0;
          final value = (at(v0) * w00 + at(v0 + 1) * w01 + at(v0 + w) * w10 + at(v0 + w + 1) * w11 + 8) >> 4;
          if (plane == 0) {
            weight0 = value;
          } else {
            weight1 = value;
          }
        }
        final o = (partitions == 1 ? 0 : _partition(seed, x, y, partitions)) * 8;
        final to = (y * bw + x) * 4;
        for (var c = 0; c < 4; c++) {
          final weight = c == plane2 ? weight1 : weight0;
          // sRGB decoding: endpoints widened to 16 bits with 0x80 below.
          final c0 = (ends[o + c] << 8) | 0x80, c1 = (ends[o + 4 + c] << 8) | 0x80;
          px[to + c] = ((c0 * (64 - weight) + c1 * weight + 32) >> 6) >> 8;
        }
      }
    }
  }
}
