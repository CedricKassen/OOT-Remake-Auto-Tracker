#!/usr/bin/env python3
"""List every placed actor of every scene (Banc/**/*.bcett.byml.zs) from the local RomFS.img.

Usage:
  python3 tools/extract_banc.py <out.json> [RomFS.img]

Writes a JSON array of {"scene", "layer" (Static|Dynamic), "actor" (Gyaml), "hash" (u64 as
string), "srt" (u32), "pos" [x,y,z], "dynamic" {...placement params}, "links" [...]}.
The output is derived from game data: keep it out of the repository (use a scratch dir).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmromfs import Image, DEFAULT_IMG
from nxformats import Zs, byml

SUFFIX = '.bcett.byml.zs'


def actors(img=None):
    img = img or Image()
    zs = Zs(img)
    for path in img.ls('Banc/'):
        if not path.endswith(SUFFIX):
            continue
        base = path.rsplit('/', 1)[1][:-len(SUFFIX)]
        scene, layer = base.rsplit('_', 1)
        doc = byml(zs.read(path)) or {}
        for a in doc.get('Actors', []):
            yield {
                'scene': scene, 'layer': layer, 'actor': a.get('Gyaml'),
                'hash': str(a.get('Hash')), 'srt': a.get('SRTHash'),
                'pos': [round(v, 3) for v in a.get('Translate', [0.0, 0.0, 0.0])],
                'dynamic': a.get('Dynamic', {}),
                'links': [{'dst': str(l.get('Dst')), 'name': l.get('Name')} for l in a.get('Links', [])],
                'name': a.get('Name'),
            }


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    img = Image(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_IMG)
    out = list(actors(img))
    with open(sys.argv[1], 'w') as f:
        json.dump(out, f, default=lambda o: o.hex() if isinstance(o, bytes) else str(o))
    print('%d actors' % len(out), file=sys.stderr)
