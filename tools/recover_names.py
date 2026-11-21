#!/usr/bin/env python3
"""Recover GameData field names by hashing every string found in the game data.

Usage:
  python3 tools/recover_names.py <out.json> [RomFS.img] [extra binary ...]

Reads GameData/GameDataList.Product.*.byml.zs for the set of 32-bit field hashes (all types),
then scans the decompressed contents of every non-media file (and every file inside SARC
packs, plus any extra binaries given, e.g. ExeFS/main) for printable strings. A string is a
field name when murmur3_x86_32(string, seed 0) is one of the hashes. Candidates tried per
string: the string itself, the part after '?' (GameData entity paths) and the file stem.
Struct members are then composed: a Struct lists {member-name hash, field hash} pairs, the
field's name is "<StructName>.<MemberName>" (nested: "PouchData.<Actor>.StockNum"), and many
structs use the decimal u64 instance hash of a placed actor as the member name
("IsTreasureBoxOpen.15117164073907033527"), so those are generated from the Banc files.
Writes {"0xHASH": {"name": ..., "type": ..., "source": first file seen}}.
Expect a handful of false positives per million distinct strings (32-bit hash); names made
only of [A-Za-z0-9_.] and >= 4 chars are kept.
Takes a few minutes. Needs `zstandard`.
"""
import json, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmromfs import Image, DEFAULT_IMG
from nxformats import Zs, byml, sarc

SKIP_DIRS = ('Tex/', 'TerrainArc/', 'Sound/', 'Voice/', 'Bake/', 'Phive/', 'PreComputedCulling/',
             'Model/', 'Foliage/', 'Font2/', 'Movie/', 'Shader/', 'agl/', 'gsys/', 'Effect/',
             'VolumeStats/', 'Layout2Shader/')
STR = re.compile(rb'[\x20-\x7e]{4,160}')
IDENT = re.compile(r'^[A-Za-z0-9_.]{4,}$')


def murmur3(data):
    h = 0
    n = len(data) & ~3
    for (k,) in struct.iter_unpack('<I', data[:n]):
        k = (k * 0xcc9e2d51) & 0xffffffff; k = ((k << 15) | (k >> 17)) & 0xffffffff
        k = (k * 0x1b873593) & 0xffffffff
        h ^= k; h = ((h << 13) | (h >> 19)) & 0xffffffff; h = (h * 5 + 0xe6546b64) & 0xffffffff
    k = 0; t = data[n:]
    if len(t) >= 3: k ^= t[2] << 16
    if len(t) >= 2: k ^= t[1] << 8
    if len(t) >= 1:
        k ^= t[0]; k = (k * 0xcc9e2d51) & 0xffffffff; k = ((k << 15) | (k >> 17)) & 0xffffffff
        k = (k * 0x1b873593) & 0xffffffff; h ^= k
    h ^= len(data); h ^= h >> 16; h = (h * 0x85ebca6b) & 0xffffffff
    h ^= h >> 13; h = (h * 0xc2b2ae35) & 0xffffffff; h ^= h >> 16
    return h


def gamedata(img, zs):
    path = [p for p in img.ls('GameData/GameDataList.Product.') if p.endswith('.byml.zs')][0]
    return byml(zs.read(path))


def field_hashes(gd):
    """{hash: type name} for every 32-bit keyed field (struct members included)."""
    out = {}
    for typ, entries in gd['Data'].items():
        if typ != 'Bool64bitKey':
            for e in entries:
                out[e['Hash']] = typ
    for e in gd['Data']['Struct']:
        for m in e.get('DefaultValue') or []:
            out.setdefault(m['Hash'], 'StructMember')  # hash of the member name, not a field
    return out


def compose(gd, hashes, found, img):
    """Name struct members: field name = StructName + '.' + MemberName, to a fixpoint."""
    from extract_banc import actors
    for a in actors(img):
        h = murmur3(a['hash'].encode())
        if h in hashes and h not in found:
            found[h] = {'name': a['hash'], 'type': 'StructMember', 'source': 'actor instance hash'}
    structs = [e for e in gd['Data']['Struct'] if e.get('DefaultValue')]
    changed = True
    while changed:
        changed = False
        for e in structs:
            sname = found.get(e['Hash'], {}).get('name')
            for m in e['DefaultValue']:
                mname = found.get(m['Hash'], {}).get('name')
                vname = found.get(m['Value'], {}).get('name')
                if sname and mname and m['Value'] not in found:
                    cand = sname + '.' + mname
                    if murmur3(cand.encode()) == m['Value']:
                        found[m['Value']] = {'name': cand, 'type': hashes[m['Value']], 'source': 'struct'}
                        changed = True
                elif not sname and mname and vname and vname.endswith('.' + mname):
                    cand = vname[:-len(mname) - 1]
                    if murmur3(cand.encode()) == e['Hash']:
                        found[e['Hash']] = {'name': cand, 'type': 'Struct', 'source': 'struct'}
                        sname = cand
                        changed = True
    for h in list(found):  # keep real fields only; member-name hashes are not fields
        if found[h]['type'] in ('StructMember',) and hashes.get(h) == 'StructMember':
            found[h]['member_only'] = True


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    img = Image(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_IMG)
    zs = Zs(img)
    gd = gamedata(img, zs)
    hashes = field_hashes(gd)
    found, seen = {}, set()

    def try_name(s, src):
        if s in seen:
            return
        seen.add(s)
        if not IDENT.match(s):
            return
        h = murmur3(s.encode())
        if h in hashes and h not in found:
            found[h] = {'name': s, 'type': hashes[h], 'source': src}

    def scan(data, src):
        for m in STR.finditer(data):
            s = m.group().decode()
            if s in seen:
                continue
            try_name(s, src)
            parts = set(re.split(r'[?/\\ ,;:"\'()\[\]{}<>=|]+', s))
            if '?' in s:
                parts.add(s.rsplit('?', 1)[1])
            for p in parts:
                if len(p) < 3 or p == s:
                    continue
                try_name(p, src)
                stem = p.split('.')[0]
                try_name(stem, src)

    def handle(data, src, depth=0):
        if data[:4] == b'SARC' and depth < 2:
            for name, blob in sarc(data).items():
                scan(name.encode(), src)
                handle(blob, src + '//' + name, depth + 1)
        else:
            scan(data, src)

    paths = [p for p in img.ls() if not p.startswith(SKIP_DIRS)]
    for i, p in enumerate(paths):
        if i % 2000 == 0:
            print('%d/%d files, %d names' % (i, len(paths), len(found)), file=sys.stderr)
        scan(p.encode(), p)
        if img.files[p][1] > 64 << 20:
            continue
        try:
            handle(zs.read(p), p)
        except Exception as e:
            print('skip %s: %s' % (p, e), file=sys.stderr)
    for extra in sys.argv[3:]:
        scan(open(extra, 'rb').read(), extra)
    # Short names with digits / lowercase start are almost always chance hits in binary data.
    for h in [h for h, v in found.items()
              if len(v['name']) < 6 and not re.match(r'^([A-Z][a-z]+)+$', v['name'])]:
        del found[h]
    compose(gd, hashes, found, img)
    out = {'0x%08X' % h: v for h, v in sorted(found.items(), key=lambda x: x[1]['name'])}
    with open(sys.argv[1], 'w') as f:
        json.dump(out, f, indent=1)
    print('%d of %d field hashes named' % (len(found), len(hashes)), file=sys.stderr)


if __name__ == '__main__':
    main()
