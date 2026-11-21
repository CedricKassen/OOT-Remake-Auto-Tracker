import 'dart:convert';

const int _m32 = 0xFFFFFFFF;

int _mul32(int a, int b) {
  // 32x32 multiply without overflowing 53 bits, so it is also correct on the web.
  final lo = (a & 0xFFFF) * b;
  final hi = ((a >> 16) & 0xFFFF) * b;
  return (lo + ((hi & 0xFFFF) << 16)) & _m32;
}

int _rotl(int x, int r) => ((x << r) | (x >> (32 - r))) & _m32;

/// MurmurHash3 (x86, 32-bit, seed 0) of the UTF-8 bytes of [text].
///
/// The game derives the hash of every save field, and of every enum value,
/// from its name this way: `PlayerStatus.CurrentRupee` -> `0xA77921D7`.
int murmur3(String text) {
  final data = utf8.encode(text);
  var h = 0;
  final blocks = data.length & ~3;
  for (var i = 0; i < blocks; i += 4) {
    var k = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);
    k = _mul32(_rotl(_mul32(k, 0xCC9E2D51), 15), 0x1B873593);
    h = (_mul32(_rotl(h ^ k, 13), 5) + 0xE6546B64) & _m32;
  }
  var k = 0;
  final tail = data.length & 3;
  if (tail == 3) k ^= data[blocks + 2] << 16;
  if (tail >= 2) k ^= data[blocks + 1] << 8;
  if (tail >= 1) {
    k ^= data[blocks];
    h ^= _mul32(_rotl(_mul32(k, 0xCC9E2D51), 15), 0x1B873593);
  }
  h ^= data.length;
  h ^= h >> 16;
  h = _mul32(h, 0x85EBCA6B);
  h ^= h >> 13;
  h = _mul32(h, 0xC2B2AE35);
  h ^= h >> 16;
  return h;
}
