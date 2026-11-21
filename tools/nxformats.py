#!/usr/bin/env python3
"""Minimal readers for the Nintendo container formats used by the game data:
zstd (.zs, with the dictionaries from Pack/ZsDic.pack.zs), SARC (.pack) and BYML.

Usage as a module (see extract_gamedata.py / extract_banc.py), or to dump one file as JSON:
  python3 tools/nxformats.py <RomFS.img> <path inside image> [inner path inside SARC]

Needs the `zstandard` package (pip install --user zstandard); otherwise standard library.
"""
import json, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zstandard
from dmromfs import Image, DEFAULT_IMG


def sarc(data):
    """SARC archive -> {name: bytes}."""
    assert data[:4] == b'SARC', data[:4]
    bom = data[6:8]
    e = '<' if bom == b'\xff\xfe' else '>'
    hlen, = struct.unpack_from(e + 'H', data, 4)
    data_off, = struct.unpack_from(e + 'I', data, 12)
    assert data[hlen:hlen + 4] == b'SFAT'
    n, = struct.unpack_from(e + 'H', data, hlen + 6)
    nodes = hlen + 12
    sfnt = nodes + n * 16
    assert data[sfnt:sfnt + 4] == b'SFNT'
    names = sfnt + 8
    out = {}
    for i in range(n):
        _, attr, s, t = struct.unpack_from(e + 'IIII', data, nodes + i * 16)
        o = names + (attr & 0xFFFFFF) * 4
        name = data[o:data.index(b'\0', o)].decode()
        out[name] = data[data_off + s:data_off + t]
    return out


class Zs:
    """Decompressor that picks the right ZsDic dictionary by dict id."""
    def __init__(self, img):
        self.img = img
        pack = sarc(zstandard.ZstdDecompressor().decompress(
            img.read('Pack/ZsDic.pack.zs'), max_output_size=1 << 26))
        self.dicts = {}
        for blob in pack.values():
            d = zstandard.ZstdCompressionDict(blob)
            self.dicts[d.dict_id()] = d
        self.plain = zstandard.ZstdDecompressor()

    def decompress(self, data):
        did = zstandard.get_frame_parameters(data).dict_id
        dctx = zstandard.ZstdDecompressor(dict_data=self.dicts[did]) if did else self.plain
        return dctx.decompressobj().decompress(data)

    def read(self, path):
        data = self.img.read(path)
        return self.decompress(data) if path.endswith('.zs') else data


class U64(int):
    pass


def byml(data):
    """BYML (either endianness, v2-v7 incl. hash-keyed maps 0x20-0x3F) -> python objects.
    Hash-keyed maps become dicts with int keys."""
    assert data[:2] in (b'YB', b'BY'), data[:4]
    E = '<' if data[:2] == b'YB' else '>'
    hk_off, st_off, root = struct.unpack_from(E + 'III', data, 4)
    u32 = lambda o: struct.unpack_from(E + 'I', data, o)[0]
    if E == '<':
        head = lambda o: (data[o], u32(o) >> 8)
    else:
        head = lambda o: (data[o], u32(o) & 0xFFFFFF)

    def strtab(off):
        if not off:
            return []
        n = head(off)[1]
        offs = struct.unpack_from(E + '%dI' % (n + 1), data, off + 4)
        return [data[off + offs[i]:off + offs[i + 1] - 1].decode('utf-8', 'replace') for i in range(n)]
    keys, strs = strtab(hk_off), strtab(st_off)
    cache = {}

    def val(t, o):  # o = offset of the 4-byte value slot
        v = u32(o)
        if t == 0xA0: return strs[v]
        if t == 0xD0: return bool(v)
        if t == 0xD1: return struct.unpack_from(E + 'i', data, o)[0]
        if t == 0xD2: return struct.unpack_from(E + 'f', data, o)[0]
        if t == 0xD3: return v
        if t == 0xD4: return struct.unpack_from(E + 'q', data, v)[0]
        if t == 0xD5: return struct.unpack_from(E + 'Q', data, v)[0]
        if t == 0xD6: return struct.unpack_from(E + 'd', data, v)[0]
        if t == 0xFF: return None
        if t == 0xA1:
            return data[v + 4:v + 4 + u32(v)]
        if t == 0xA2:
            return data[v + 8:v + 8 + u32(v)]
        if v in cache: return cache[v]
        r = cache[v] = node(v)
        return r

    def node(off):
        t, n = head(off)
        if t == 0xC0:
            base = off + 4 + ((n + 3) & ~3)
            return [val(data[off + 4 + i], base + 4 * i) for i in range(n)]
        if t == 0xC1:
            d = {}
            for i in range(n):
                e = off + 4 + 8 * i
                k = u32(e)
                if E == '<':
                    d[keys[k & 0xFFFFFF]] = val(k >> 24, e + 4)
                else:
                    d[keys[k >> 8]] = val(k & 0xFF, e + 4)
            return d
        if 0x20 <= t <= 0x2F:
            types = off + 4 + 8 * n
            return {u32(off + 4 + 8 * i): val(data[types + i], off + 8 + 8 * i) for i in range(n)}
        if 0x30 <= t <= 0x3F:
            types = off + 4 + 12 * n
            return {struct.unpack_from(E + 'Q', data, off + 4 + 12 * i)[0]:
                    val(data[types + i], off + 12 + 12 * i) for i in range(n)}
        raise ValueError('byml node type 0x%02X at 0x%X' % (t, off))
    return node(root) if root else None


def _default(o):
    if isinstance(o, (bytes, bytearray)):
        return o.hex()
    raise TypeError(type(o))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    zs = Zs(Image(sys.argv[1]))
    d = zs.read(sys.argv[2])
    if len(sys.argv) > 3:
        d = sarc(d)[sys.argv[3]]
    if d[:4] == b'SARC':
        for k, v in sarc(d).items():
            print('%s\t%d' % (k, len(v)))
    else:
        json.dump(byml(d), sys.stdout, indent=1, default=_default)
