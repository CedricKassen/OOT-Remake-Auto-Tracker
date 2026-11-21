#!/usr/bin/env python3
"""Read-only access to an nxnative DMROMFS1 image (RomFS.img).

Usage:
  python3 tools/dmromfs.py <RomFS.img> ls [substring]        # path<TAB>size
  python3 tools/dmromfs.py <RomFS.img> cat <path> > out      # raw bytes
  python3 tools/dmromfs.py <RomFS.img> get <outdir> <path>.. # extract (never inside the game dir)

Layout: "DMROMFS1", u64 index offset, u64 index size, u64 entry count; index =
count * {u64 a, u64 b, u32 name, u16 nlen, u8 type, u8 flags} + name pool.
Directory (type 0): a = first child index, b = child count. File: a = offset, b = size.
Standard library only.
"""
import os, struct, sys

DEFAULT_IMG = os.path.expanduser(
    '~/Documents/Games/0400486024DEC000_build_main/extract/v131072/RomFS.img')


class Image:
    def __init__(self, path=DEFAULT_IMG):
        self.f = open(path, 'rb')
        h = self.f.read(32)
        if h[:8] != b'DMROMFS1':
            raise ValueError('not a DMROMFS1 image')
        ioff, isz, n = struct.unpack('<QQQ', h[8:])
        self.f.seek(ioff)
        idx = self.f.read(isz)
        pool = n * 24
        self.files = {}
        stack = [(0, '')]
        while stack:
            k, prefix = stack.pop()
            a, b, name, nlen, typ, _ = struct.unpack_from('<QQIHBB', idx, k * 24)
            p = prefix + idx[pool + name:pool + name + nlen].decode('utf-8')
            if typ:
                self.files[p] = (a, b)
            else:
                for j in range(a, a + b):
                    stack.append((j, p + '/' if k else ''))

    def read(self, path):
        off, size = self.files[path]
        self.f.seek(off)
        return self.f.read(size)

    def ls(self, sub=''):
        return sorted(p for p in self.files if sub in p)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    img = Image(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == 'ls':
        for p in img.ls(sys.argv[3] if len(sys.argv) > 3 else ''):
            print('%s\t%d' % (p, img.files[p][1]))
    elif cmd == 'cat':
        sys.stdout.buffer.write(img.read(sys.argv[3]))
    elif cmd == 'get':
        out = sys.argv[3]
        for p in sys.argv[4:]:
            dst = os.path.join(out, p)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'wb') as o:
                o.write(img.read(p))
    else:
        sys.exit(__doc__)
