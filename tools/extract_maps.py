#!/usr/bin/env python3
"""Extract the game's own map artwork (pause-menu area maps, dungeon floor maps, world illustration)
from the user's RomFS.img as PNGs, and write the world->pixel calibration to data/maps.json.

Usage:
  python3 tools/extract_maps.py [RomFS.img] [--out data/local/maps] [--json data/maps.json]
                                [--no-images]     # only rewrite maps.json (still decodes, to get crops)

Needs: zstandard, Pillow, numpy, texture2ddecoder  (pip install --user zstandard Pillow numpy texture2ddecoder)
The PNGs are game artwork: they go to data/local/maps/ which is git-ignored. maps.json holds metadata only.

Where the data comes from (all read-only, inside RomFS.img)
  UI/CustomTex/Map/Field/<Loc>_<Child|Adult>_<NN>.bntx.zs    area maps, 2000x1440, ASTC 5x5
  UI/CustomTex/Map/Field/Mini_<...>.bntx.zs                   same capture, 1067x1067 (minimap; not exported)
  UI/CustomTex/Map/Dungeon/<Dungeon>_<Floor>[_LvN][_StateNN]_Main.bntx.zs   floor maps, 2000x1440, ASTC 6x6
       (_Back = silhouette, _Alpha = per-room reveal mask, _Grad = door glows, <Dungeon>_All = outline; not exported)
  UI/Layout2Archive/Common...bntx.zs : MapTexWorldAll_00      illustrated world map, 4608x3360 (no coordinates)
  Game/MapMenuInfo/MapMenuInfo...bgyml                        map list: LocationName, banc names, texture names
  Game/MapCaptureInfo/MapCaptureInfo...bgyml                  same order: top-down orthographic capture camera
                                                              (CameraPos X/Z = centre, Height = side length in world units)
  Banc/BancBasedResource/MapParam.byml.zs                     per dungeon: floors (TransY = floor base height), MinFloor

Calibration (confidence "exact": taken from game data, checked against door/chest/entrance anchors)
  Every map texture is a square orthographic capture of side `Height` world units centred on CameraPos,
  rendered at 2000x2000 px and cropped vertically to the middle 1440 rows. North (-z) is up, +x is right:
      px = 1000 + (x - CamX) * 2000/Height        py = 720 + (z - CamZ) * 2000/Height
  This script additionally trims transparent borders (and downsizes if > 2048 px); the transform written
  to maps.json already includes that.

maps.json schema
  {"maps": [{
     "id": "HyruleField_Child",           unique id
     "file": "HyruleField_Child.png",     inside data/local/maps/
     "width": .., "height": ..,           PNG size in px
     "title": "Hyrule Field",
     "kind": "field" | "dungeon" | "world",
     "location": "HyruleField",           the game's LocationName (LonLonRanch/LakeHylia are sub-maps of the HyruleField scene)
     "scenes": ["HyruleField"],           scene base names (no _Child/_Adult) whose coordinates this map uses
     "bancs": ["HyruleField_Child"],      exact scene names (Sequence_CurrentBanc) this image is meant for
     "era": "child" | "adult" | null,     null = same image for both eras / dungeons
     "transform": {"*": {"ax":..,"bx":..,"az":..,"bz":..}},   px = ax*x + bx, py = az*z + bz (no rotation anywhere)
     "world": {"xmin":..,"xmax":..,"zmin":..,"zmax":..},      world rectangle the PNG covers (use it to pick between
                                                              HyruleField / LonLonRanch / LakeHylia for a position)
     "floor": null | {"label": "1F", "index": 2, "ymin": 94.5, "ymax": 112.2},
                                          dungeon floors: a position belongs to the floor with ymin <= y < ymax
                                          (ymin null on the lowest floor, ymax null on the top floor)
     "variant": "State00" | "Lv1" | ...   which state texture was exported (others exist, see report)
     "source": "UI/CustomTex/Map/...",    texture the PNG was decoded from
     "areas": ["hyrule_field"],           tracker area ids (data/areas.json) this map is the natural one for
     "confidence": "exact" | "fitted" | "guess" | "none"      ("none": world illustration, no transform)
  }],
  "instances": {"<actor instance id>": {"maps": ["ForestTemple_1F"], "pos": [x, y, z]}}
       The game's own assignment of map icons (gold skulltulas, heart pieces, chests) to maps, from MapParam:
       which area map / dungeon floor shows the icon, and the icon position (occasionally differs from the
       actor position, which is why a pure y-range floor test is wrong for a handful of dungeon items).
       Keys match "instance" in data/collectibles.json. Prefer this over "world"/"floor" tests when present.
  }
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nxformats import Zs, byml
from dmromfs import Image, DEFAULT_IMG
import bntx
import numpy as np
from PIL import Image as PImage

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = 'UI/CustomTex/Map/'
CAPTURE_PX = 2000.0          # square capture size in texture pixels
TEX_W, TEX_H = 2000, 1440    # stored texture (capture cropped to the middle 1440 rows)
MAX_SIDE = 2048

TITLES = {
    'KokiriForest': 'Kokiri Forest', 'KakarikoVillage': 'Kakariko Village', 'LonLonRanch': 'Lon Lon Ranch',
    'Market': 'Castle Town Market', 'GoronCity': 'Goron City', 'ZoraDomain': "Zora's Domain",
    'GerudoFortress': "Gerudo's Fortress", 'LostWood': 'Lost Woods', 'SacredForestMeadow': 'Sacred Forest Meadow',
    'HyruleField': 'Hyrule Field', 'HyruleCastle': 'Hyrule Castle', 'Graveyard': 'Kakariko Graveyard',
    'DeathMountainTrail': 'Death Mountain Trail', 'DeathMountainCrater': 'Death Mountain Crater',
    'ZoraRiver': "Zora's River", 'ZoraFountain': "Zora's Fountain", 'LakeHylia': 'Lake Hylia',
    'GerudoValley': 'Gerudo Valley', 'HountedWasteland': 'Haunted Wasteland', 'DesertColossus': 'Desert Colossus',
    'InsideTheDekuTree': 'Inside the Deku Tree', 'DodongoCavern': "Dodongo's Cavern",
    'InsideJabuJabuBelly': "Inside Jabu-Jabu's Belly", 'ForestTemple': 'Forest Temple', 'FireTemple': 'Fire Temple',
    'WaterTemple': 'Water Temple', 'ShadowTemple': 'Shadow Temple', 'SpiritTemple': 'Spirit Temple',
    'BottomOfTheWell': 'Bottom of the Well', 'IceCavern': 'Ice Cavern', 'GanonCastle': "Ganon's Castle (outside)",
}
# LocationNames that are drawn from another scene's coordinates (one banc, several maps).
AREAS = {
    'KokiriForest': 'kokiri_forest', 'KakarikoVillage': 'kakariko_village', 'LonLonRanch': 'lon_lon_ranch',
    'Market': 'castle_town', 'GoronCity': 'goron_city', 'ZoraDomain': 'zoras_domain',
    'GerudoFortress': 'gerudo_fortress', 'LostWood': 'lost_woods', 'SacredForestMeadow': 'lost_woods',
    'HyruleField': 'hyrule_field', 'HyruleCastle': 'hyrule_castle', 'Graveyard': 'graveyard',
    'DeathMountainTrail': 'death_mountain_trail', 'DeathMountainCrater': 'death_mountain_crater',
    'ZoraRiver': 'zoras_river', 'ZoraFountain': 'zoras_domain', 'LakeHylia': 'lake_hylia',
    'GerudoValley': 'gerudo_valley', 'HountedWasteland': 'desert_colossus', 'DesertColossus': 'desert_colossus',
    'InsideTheDekuTree': 'deku_tree', 'DodongoCavern': 'dodongos_cavern', 'InsideJabuJabuBelly': 'jabu_jabu',
    'ForestTemple': 'forest_temple', 'FireTemple': 'fire_temple', 'WaterTemple': 'water_temple',
    'ShadowTemple': 'shadow_temple', 'SpiritTemple': 'spirit_temple', 'BottomOfTheWell': 'bottom_of_the_well',
    'IceCavern': 'ice_cavern', 'GanonCastle': 'hyrule_castle',
}
SCENE_OF = {'LonLonRanch': 'HyruleField', 'LakeHylia': 'HyruleField'}


def base(banc):
    return re.sub(r'_(Child|Adult)(_Alternative)?$', '', banc)


def trim(img):
    """Crop transparent borders (8 px margin), cap the longest side. -> (image, x0, y0, scale)"""
    a = np.asarray(img)[:, :, 3] > 8
    ys, xs = np.where(a.any(1))[0], np.where(a.any(0))[0]
    if len(xs) == 0 or (len(xs) > 0.98 * img.width and len(ys) > 0.98 * img.height):
        x0, y0, x1, y1 = 0, 0, img.width, img.height
    else:
        x0, x1 = max(0, xs[0] - 8), min(img.width, xs[-1] + 9)
        y0, y1 = max(0, ys[0] - 8), min(img.height, ys[-1] + 9)
    out = img.crop((x0, y0, x1, y1))
    s = 1.0
    if max(out.size) > MAX_SIDE:
        s = MAX_SIDE / max(out.size)
        out = out.resize((round(out.width * s), round(out.height * s)), PImage.LANCZOS)
    return out, int(x0), int(y0), s


def main():
    args = sys.argv[1:]
    def opt(name, default):
        if name in args:
            i = args.index(name)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return default
    out_dir = opt('--out', os.path.join(REPO, 'data', 'local', 'maps'))
    json_path = opt('--json', os.path.join(REPO, 'data', 'maps.json'))
    write_images = '--no-images' not in args
    args = [a for a in args if a != '--no-images']
    img_path = args[0] if args else DEFAULT_IMG
    if os.path.abspath(out_dir).startswith(os.path.dirname(os.path.abspath(img_path))):
        sys.exit('refusing to write inside the game directory')
    os.makedirs(out_dir, exist_ok=True)

    zs = Zs(Image(img_path))
    menu = byml(zs.read('Game/MapMenuInfo/MapMenuInfo.game__ui__MapMenuInfo.bgyml'))['MapMenuParamArray']
    capture = byml(zs.read('Game/MapCaptureInfo/MapCaptureInfo.game__MapCaptureInfo.bgyml'))['MapCaptureParamArray']
    param = byml(zs.read('Banc/BancBasedResource/MapParam.byml.zs'))
    have = set(zs.img.ls(TEX))
    real_bancs = set(os.path.basename(x).split('.')[0] for x in zs.img.ls('Banc/GameBancParam/'))
    own_entry = set(e['LocationName'] for e in menu)
    instances = {}

    def note(inst, mid, pos):
        d = instances.setdefault(str(inst), {'maps': [], 'pos': [round(v, 3) for v in pos]})
        if mid not in d['maps']:
            d['maps'].append(mid)
    maps = []

    def decode(path):
        return bntx.first_image(zs.read(path))[2]

    def emit(mid, img, cam, extra):
        img, x0, y0, s = trim(img)
        fn = mid + '.png'
        if write_images:
            img.save(os.path.join(out_dir, fn), optimize=True)
        k = CAPTURE_PX / cam['Height']
        cx, cz = cam['CameraPos'].get('X', 0.0), cam['CameraPos'].get('Z', 0.0)
        ax = k * s
        bx = (TEX_W / 2 - cx * k - x0) * s
        bz = (TEX_H / 2 - cz * k - y0) * s
        m = {'id': mid, 'file': fn, 'width': img.width, 'height': img.height}
        m.update(extra)
        m['transform'] = {'*': {'ax': round(ax, 6), 'bx': round(bx, 3), 'az': round(ax, 6), 'bz': round(bz, 3)}}
        m['world'] = {'xmin': round(-bx / ax, 2), 'xmax': round((img.width - bx) / ax, 2),
                      'zmin': round(-bz / ax, 2), 'zmax': round((img.height - bz) / ax, 2)}
        m.setdefault('floor', None)
        m['areas'] = [AREAS[m['location']]] if m['location'] in AREAS else []
        m['confidence'] = 'exact'
        maps.append(m)
        print('%-34s %4dx%-4d  %.3f px/unit' % (mid, img.width, img.height, ax))

    for i, e in enumerate(menu):
        loc, cam = e['LocationName'], capture[i]
        title = TITLES.get(loc, loc)
        if loc in param and param[loc].get('Floor'):            # ---- dungeon: one map per floor
            p = param[loc]
            floors = p['Floor']
            for fi, f in enumerate(floors):
                n = p['MinFloor'] + fi
                label = 'B%d' % -n if n < 0 else '%dF' % (n + 1)
                cands = sorted(x for x in have
                               if re.fullmatch(re.escape(TEX + 'Dungeon/%s_%s' % (loc, label)) +
                                               r'(_Lv\d+)?(_State\d+)?_Main\.bntx\.zs', x))
                if not cands:
                    print('no texture for', loc, label)
                    continue
                src = cands[0]                                   # Lv1 / State00 sorts first
                variant = re.search(r'_%s_(.*?)_?Main' % label, src).group(1) or None
                emit('%s_%s' % (loc, label), decode(src), cam, {
                    'title': '%s %s' % (title, label), 'kind': 'dungeon', 'location': loc,
                    'scenes': [loc], 'bancs': [loc], 'era': None,
                    'floor': {'label': label, 'index': fi,
                              'ymin': round(f['TransY'], 3) if fi else None,
                              'ymax': round(floors[fi + 1]['TransY'], 3) if fi + 1 < len(floors) else None},
                    'variant': variant, 'variants': [re.search(r'_%s_(.*?)_?Main' % label, c).group(1) or None for c in cands],
                    'source': src})
                for cat in ('CollectSign', 'CollectHeart', 'TBox'):
                    for it in f.get(cat, []):
                        note(it['InstanceID'], '%s_%s' % (loc, label), it['Trans'])
            continue
        # ---- field: child / adult texture (merged when identical)
        tex = e['TextureName'][:2]
        paths = [TEX + 'Field/%s.bntx.zs' % t for t in tex]
        imgs = [decode(p) if p in have else None for p in paths]
        same = False
        if imgs[0] is not None and imgs[1] is not None and paths[0] != paths[1]:
            d = np.abs(np.asarray(imgs[0]).astype(np.int16) - np.asarray(imgs[1]).astype(np.int16)).mean()
            same = d < 0.5
        if paths[0] == paths[1]:
            same = True
        bancs = [e['BancName'][0], e['BancName'][1]]
        alt = [c['BancName'] for c in e.get('ChangeBancInfo', [])]
        scene = SCENE_OF.get(loc)
        for era_i, era in enumerate(('child', 'adult')):
            if imgs[era_i] is None:
                continue
            if same and era_i == 1:
                continue
            if base(bancs[era_i]) != loc and base(bancs[era_i]) in own_entry and not scene:
                continue        # e.g. HyruleCastle's adult texture is the GanonCastle scene, which has its own entry
            if scene:
                bn = [scene + ('_Child' if era_i == 0 else '_Adult')] if not same else [scene + '_Child', scene + '_Adult']
            else:
                bn = sorted(set(bancs)) + alt if same else [bancs[era_i]] + (alt if era_i == 1 else [])
            bn = [b for b in bn if b in real_bancs]      # GerudoFortress_Child etc. do not exist as scenes
            mid = loc if same else '%s_%s' % (loc, era.capitalize())
            for key in ([loc + '_Child', loc + '_Adult', loc] if same else
                        [loc + ('_Child' if era_i == 0 else '_Adult'), loc] +
                        ([loc + '_Adult_Alternative'] if era_i else [])):
                for cat in ('CollectSign', 'CollectHeart', 'CollectSignAll', 'CollectHeartAll', 'TBox'):
                    for it in param.get(key, {}).get(cat, []):
                        note(it['InstanceID'], mid, it['Trans'])
            emit(mid, imgs[era_i], cam, {
                'title': title, 'kind': 'field', 'location': loc,
                'scenes': sorted(set(base(b) for b in bn)), 'bancs': bn,
                'era': None if same else era, 'variant': None, 'source': paths[era_i]})

    # ---- illustrated world map (artwork only; scenes are separate coordinate systems, so no transform)
    common = zs.read('UI/Layout2Archive/Common.Product.100.Nin_Ounce_NVN2.bntx.zs')
    for name, t in bntx.textures(common):
        if name == 'MapTexWorldAll_00':
            img = bntx.decode(common, t)
            s = MAX_SIDE / max(img.size)
            img = img.resize((round(img.width * s), round(img.height * s)), PImage.LANCZOS)
            if write_images:
                img.save(os.path.join(out_dir, 'world.png'), optimize=True)
            maps.append({'id': 'world', 'file': 'world.png', 'width': img.width, 'height': img.height,
                         'title': 'Hyrule', 'kind': 'world', 'location': None, 'scenes': [], 'bancs': [],
                         'era': None, 'transform': {}, 'world': None, 'floor': None, 'variant': None,
                         'source': 'UI/Layout2Archive/Common.Product.100.Nin_Ounce_NVN2.bntx.zs:MapTexWorldAll_00',
                         'confidence': 'none'})
            print('world %dx%d' % img.size)

    with open(json_path, 'w') as f:
        json.dump({'maps': maps, 'instances': instances}, f, indent=1)
        f.write('\n')
    print(len(maps), 'maps,', len(instances), 'icon instances ->', json_path)


if __name__ == '__main__':
    main()
