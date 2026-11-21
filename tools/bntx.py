#!/usr/bin/env python3
"""Minimal BNTX (Switch texture container) decoder: first mip of every texture -> PIL RGBA image.

Handles the Tegra block-linear swizzle and the formats the map textures use
(ASTC 4x4..12x12, BC1-BC5, BC7, R8, R8G8, RGBA8/BGRA8).
Needs: Pillow, numpy, texture2ddecoder (pip install --user Pillow numpy texture2ddecoder).

Usage:  python3 tools/bntx.py <file.bntx> <out.png>      # plain (already decompressed) bntx
"""
import struct, sys
import numpy as np
from PIL import Image as PImage
import texture2ddecoder as t2d

ASTC = {0x2d: (4, 4), 0x2e: (5, 4), 0x2f: (5, 5), 0x30: (6, 5), 0x31: (6, 6), 0x32: (8, 5), 0x33: (8, 6),
        0x34: (8, 8), 0x35: (10, 5), 0x36: (10, 6), 0x37: (10, 8), 0x38: (10, 10), 0x39: (12, 10), 0x3a: (12, 12)}
BCN = {0x1a: (t2d.decode_bc1, 8), 0x1c: (t2d.decode_bc3, 16),
       0x1d: (t2d.decode_bc4, 8), 0x1e: (t2d.decode_bc5, 16), 0x20: (t2d.decode_bc7, 16)}
RAW = {0x02: 1, 0x09: 2, 0x0b: 4, 0x0c: 4}


def deswizzle(data, wb, hb, bpp, bh_log2):
    """Block-linear -> linear. wb/hb = size in blocks (or pixels), bpp = bytes per block."""
    bh = 1 << bh_log2
    x = np.arange(wb, dtype=np.int64)[None, :] * bpp
    y = np.arange(hb, dtype=np.int64)[:, None]
    gobs_w = (wb * bpp + 63) // 64
    # Within a 512-byte GOB the byte address bits are x0-3, y0, y1, x4, y2, x5.  NOTE: this differs
    # from the classic Switch 1 order (x0-3, y0, x4, y1, y2, x5); found empirically (minimal block seams)
    # for this title's NVN2 textures.
    addr = ((y // (8 * bh)) * 512 * bh * gobs_w + (x // 64) * 512 * bh + ((y % (8 * bh)) // 8) * 512
            + ((x % 64) // 32) * 256 + ((y % 8) // 4) * 128 + ((x % 32) // 16) * 64
            + ((y % 4) // 2) * 32 + (y % 2) * 16 + (x % 16))
    src = np.frombuffer(data, dtype=np.uint8)
    idx = addr[:, :, None] + np.arange(bpp, dtype=np.int64)[None, None, :]
    if idx.max() >= len(src):
        src = np.concatenate([src, np.zeros(int(idx.max()) + 1 - len(src), np.uint8)])
    return src[idx].tobytes()


def textures(d):
    """Yield (name, info dict) for every BRTI in a BNTX blob."""
    assert d[:4] == b'BNTX', d[:4]
    pos = 0
    while True:
        i = d.find(b'BRTI', pos)
        if i < 0:
            return
        pos = i + 4
        tile, swz, mips = struct.unpack_from('<HHH', d, i + 0x12)
        fmt, = struct.unpack_from('<I', d, i + 0x1c)
        w, h, depth, arr, bhl = struct.unpack_from('<5I', d, i + 0x24)
        size, align = struct.unpack_from('<II', d, i + 0x50)
        name_off, = struct.unpack_from('<Q', d, i + 0x60)
        ptrs, = struct.unpack_from('<Q', d, i + 0x70)
        nlen, = struct.unpack_from('<H', d, name_off)
        name = d[name_off + 2:name_off + 2 + nlen].decode()
        data_off, = struct.unpack_from('<Q', d, ptrs)
        yield name, dict(fmt=fmt, w=w, h=h, bhl=bhl, size=size, off=data_off, tile=tile, mips=mips)


def decode(d, t):
    typ = t['fmt'] >> 8
    w, h = t['w'], t['h']
    raw = d[t['off']:t['off'] + t['size']]
    if typ in ASTC:
        bw, bhh = ASTC[typ]
        wb, hb = -(-w // bw), -(-h // bhh)
        lin = deswizzle(raw, wb, hb, 16, t['bhl']) if not t['tile'] else raw
        return PImage.frombytes('RGBA', (w, h), t2d.decode_astc(lin, w, h, bw, bhh), 'raw', 'BGRA')
    if typ in BCN:
        fn, bpp = BCN[typ]
        wb, hb = -(-w // 4), -(-h // 4)
        lin = deswizzle(raw, wb, hb, bpp, t['bhl']) if not t['tile'] else raw
        return PImage.frombytes('RGBA', (w, h), fn(lin, w, h), 'raw', 'BGRA')
    if typ in RAW:
        bpp = RAW[typ]
        lin = deswizzle(raw, w, h, bpp, t['bhl']) if not t['tile'] else raw
        a = np.frombuffer(lin, np.uint8).reshape(h, w, bpp)
        if bpp == 1:
            return PImage.fromarray(a[:, :, 0], 'L').convert('RGBA')
        if bpp == 2:
            return PImage.merge('RGBA', [PImage.fromarray(a[:, :, 0])] * 3 + [PImage.fromarray(a[:, :, 1])])
        img = PImage.fromarray(a, 'RGBA')
        if typ == 0x0c:
            b, g, r, al = img.split()
            img = PImage.merge('RGBA', (r, g, b, al))
        return img
    raise ValueError('unsupported BNTX format 0x%04x' % t['fmt'])


def first_image(d):
    name, t = next(textures(d))
    return name, t, decode(d, t)


if __name__ == '__main__':
    d = open(sys.argv[1], 'rb').read()
    for name, t in textures(d):
        print(name, t)
    first_image(d)[2].save(sys.argv[2])
