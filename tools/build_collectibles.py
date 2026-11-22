#!/usr/bin/env python3
"""Build data/collectibles.json: every Gold Skulltula, Heart Piece, Heart Container and
treasure chest with the save flag that records it, from the user's own RomFS.img.

Usage:
  python3 tools/build_collectibles.py [--img RomFS.img] [--save fixtures/save/slot_03/progress.sav]
                                      [--out data/collectibles.json] [--check]

How the game stores them (see also recover_names.py):
  * Bool64bitKey ("store": "bool64"): the save holds a sorted list of the u64 keys that are
    true. It is the data block of the single entry in table section 32 (entry hash 0xA3DB7114):
    little-endian u64 values, terminated by 0. The key of a placed actor is its Banc instance
    hash ("instance"). Gold Skulltulas, free-standing Heart Pieces and Heart Containers use it.
    Skulltulas also own the key (instance XOR 2); in the fixture saves both are always set together.
  * Bool ("store": "bool"): an ordinary table field, hash = murmur3_x86_32(name). Chests are
    "IsTreasureBoxOpen.<decimal instance hash>"; reward Heart Pieces use the flag named by the
    HeartPieceAnchor actor (HeartPieceAnchor_GameDataPath).
Heart Pieces are enumerated through the 36 HeartPieceAnchor actors (the map-icon anchors),
each of which links to an Obj_Heart_Piece, to a chest, or names a flag.
--check prints counts per kind/scene and the Gold Skulltula count of every fixture slot.
Needs `zstandard`.
"""
import argparse, collections, glob, json, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dmromfs import Image, DEFAULT_IMG
from nxformats import Zs
from extract_banc import actors
from recover_names import murmur3, gamedata

ROOT = os.path.dirname(HERE)
KEY64_SECTION = 32
BIG_POE_IDS, BIG_POE_SOLD = '0xE1A508C4', '0x40772671'  # unnamed fields, found in the save journal


def read_save(path):
    """-> ({field hash: raw u32} for Bool fields, set of true 64-bit keys)."""
    b = open(path, 'rb').read()
    end, = struct.unpack_from('<I', b, 8)
    sec, bools, keys = 0, {}, set()
    for o in range(40, end, 8):
        h, v = struct.unpack_from('<II', b, o)
        if h == 0:
            sec = v
        elif sec == 0:
            bools[h] = v
        elif sec == KEY64_SECTION:
            while True:
                k, = struct.unpack_from('<Q', b, v)
                if not k:
                    break
                keys.add(k)
                v += 8
    return bools, keys


def build(img):
    gd = gamedata(img, Zs(img))
    keys64 = {e['Hash'] for e in gd['Data']['Bool64bitKey']}
    bool32 = {e['Hash'] for e in gd['Data']['Bool'] if e['SaveFileIndex'] == 0}
    by_hash = collections.OrderedDict()
    for a in actors(img):
        by_hash.setdefault(a['hash'], []).append(a)

    def base(kind, a_list, **kw):
        a = a_list[0]
        d = {'kind': kind, 'store': None, 'hash': None, 'key64': None, 'name': None,
             'scene': a['scene'], 'scenes': sorted({x['scene'] for x in a_list}),
             'actor': a['actor'], 'instance': a['hash'], 'pos': a['pos']}
        room = a['dynamic'].get('DefaultDungeonRoomIndex')
        if room is not None:
            d['room'] = room
        d.update(kw)
        return d

    def as_key64(d, inst):
        assert int(inst) in keys64, inst
        d.update(store='bool64', key64='0x%016X' % int(inst))
        return d

    def as_bool(d, name):
        h = murmur3(name.encode())
        assert h in bool32, name
        d.update(store='bool', hash='0x%08X' % h, name=name)
        return d

    out = []
    for inst, l in by_hash.items():
        actor = l[0]['actor']
        if actor == 'Enemy_Skulltula_Gold' and int(inst) in keys64:
            out.append(as_key64(base('skulltula', l), inst))
        elif actor == 'Enemy_Poe_Big':
            # Not a flag of its own: the save lists the Big Poes met so far (IntArray of
            # PoeBig_FenceID) and keeps a "sold to the Poe collector" BoolArray in the same order.
            d = base('big_poe', l, store='listed')
            d['listed'] = {'ids': BIG_POE_IDS, 'flags': BIG_POE_SOLD, 'id': l[0]['dynamic']['PoeBig_FenceID']}
            out.append(d)
        elif actor == 'Obj_Heart_Container':
            out.append(as_key64(base('heart_container', l), inst))
        elif 'TBox' in actor:
            name = 'IsTreasureBoxOpen.' + inst
            if murmur3(name.encode()) in bool32:
                d = as_bool(base('chest', l), name)
                item = l[0]['dynamic'].get('Drop__DropActor')
                if item:
                    d['item'] = item
                out.append(d)
        elif actor == 'HeartPieceAnchor':
            path = l[0]['dynamic'].get('HeartPieceAnchor_GameDataPath')
            if path:
                out.append(as_bool(base('heart_piece', l, source='reward'), path))
                continue
            for link in l[0]['links']:
                t = by_hash.get(link['dst'])
                if not t:
                    continue
                if 'Heart_Piece' in t[0]['actor']:
                    d = as_key64(base('heart_piece', t, source='freestanding'), link['dst'])
                elif 'TBox' in t[0]['actor']:
                    d = as_bool(base('heart_piece', t, source='chest'), 'IsTreasureBoxOpen.' + link['dst'])
                else:
                    continue
                d['scenes'] = sorted({x['scene'] for x in l})
                out.append(d)
                break
            else:
                raise SystemExit('unresolved HeartPieceAnchor ' + inst)
    return out


def collected(entry, bools, keys):
    if entry['store'] == 'listed':
        return False  # adult-only late-game errand; read_save does not decode arrays
    if entry['store'] == 'bool64':
        return int(entry['key64'], 16) in keys
    return bool(bools.get(int(entry['hash'], 16), 0))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--img', default=DEFAULT_IMG)
    ap.add_argument('--save', default=os.path.join(ROOT, 'fixtures/save/slot_03/progress.sav'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'data/collectibles.json'))
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    out = build(Image(args.img))
    bools, keys = read_save(args.save)
    for e in out:
        e['collectedInFixtureSlot03'] = collected(e, bools, keys)
    order = {'skulltula': 0, 'heart_piece': 1, 'big_poe': 2, 'heart_container': 3, 'chest': 4}
    out.sort(key=lambda e: (order[e['kind']], e['scene'], e.get('room', -1), e['instance']))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w') as f:
        f.write('[\n' + ',\n'.join(json.dumps(e) for e in out) + '\n]\n')
    kinds = collections.Counter(e['kind'] for e in out)
    got = collections.Counter(e['kind'] for e in out if e['collectedInFixtureSlot03'])
    print('wrote %s: %s' % (args.out, ', '.join('%s %d (%d collected)' % (k, n, got[k]) for k, n in kinds.items())))
    if args.check:
        for kind in order:
            per = collections.Counter(e['scene'] for e in out if e['kind'] == kind)
            print(kind, dict(sorted(per.items())))
        for p in sorted(glob.glob(os.path.join(ROOT, 'fixtures/save/slot_*/progress.sav'))):
            b, k = read_save(p)
            print(os.path.basename(os.path.dirname(p)), {kind: sum(collected(e, b, k) for e in out if e['kind'] == kind) for kind in order})


if __name__ == '__main__':
    main()
