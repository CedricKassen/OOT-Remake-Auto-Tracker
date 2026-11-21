#!/usr/bin/env python3
"""Adds the tracker's area id to every entry of data/collectibles.json.

Run after build_collectibles.py:  python3 tools/assign_areas.py

The game's scenes do not line up with the checklist's areas everywhere, so
this maps scene names to areas, and splits the Hyrule Field scene (which also
holds Lon Lon Ranch and Lake Hylia) by position. With --check it prints the
per-area counts next to the number of checklist entries; they must agree for
skulltulas and heart pieces.
"""
import collections, json, os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')
SCENES = {
    'KokiriForest': 'kokiri_forest', 'InsideTheDekuTree': 'deku_tree', 'Market': 'castle_town',
    'TimeTemple': 'castle_town', 'HyruleCastle': 'hyrule_castle', 'GanonCastle': 'hyrule_castle',
    'KakarikoVillage': 'kakariko_village', 'Graveyard': 'graveyard', 'GraveYard': 'graveyard',
    'DeathMountainTrail': 'death_mountain_trail', 'GoronCity': 'goron_city',
    'LostWood': 'lost_woods', 'SacredForestMeadow': 'lost_woods', 'DodongoCavern': 'dodongos_cavern',
    'DeathMountainCrater': 'death_mountain_crater', 'ZoraRiver': 'zoras_river',
    'ZoraDomain': 'zoras_domain', 'ZoraFountain': 'zoras_domain', 'InsideJabuJabuBelly': 'jabu_jabu',
    'GerudoValley': 'gerudo_valley', 'ForestTemple': 'forest_temple', 'FireTemple': 'fire_temple',
    'IceCavern': 'ice_cavern', 'WaterTemple': 'water_temple', 'BottomOfTheWell': 'bottom_of_the_well',
    'ShadowTemple': 'shadow_temple', 'GerudoFortress': 'gerudo_fortress',
    'GerudoTrainingGround': 'gerudo_fortress', 'HountedWasteland': 'desert_colossus',
    'DesertColossus': 'desert_colossus', 'SpiritTemple': 'spirit_temple',
    'InsideGanonCastle': 'ganons_castle',
}

def area_of(entry):
    scene = re.sub(r'_(Adult|Child|Alternative)$', '', entry['scene'])
    scene = re.sub(r'_(Adult|Child|Alternative)$', '', scene)
    if scene == 'HyruleField':
        x, y, z = entry['pos']
        if z > 400: return 'lake_hylia'          # the lake lies at the south end of the scene
        if -170 < x < -20 and 190 < z < 280 and y > 150: return 'lon_lon_ranch'  # raised plateau
        return 'hyrule_field'
    return SCENES.get(scene)

path = os.path.join(root, 'collectibles.json')
items = json.load(open(path))
for item in items:
    item['area'] = area_of(item)
json.dump(items, open(path, 'w'), indent=1)

if '--check' in sys.argv:
    checks = json.load(open(os.path.join(root, 'checks.json')))
    ok = True
    for kind in ('skulltula', 'heart_piece'):
        want = collections.Counter(c['area'] for c in checks if c['category'] == kind)
        have = collections.Counter(i['area'] for i in items if i['kind'] == kind)
        for area in sorted(set(want) | set(have), key=str):
            if want[area] != have[area]:
                ok = False
                print(f'MISMATCH {kind} {area}: checklist {want[area]}, save data {have[area]}')
    print('areas agree with the checklist' if ok else 'differences found')
    print('without area:', collections.Counter(i['scene'] for i in items if not i['area']))
