#!/usr/bin/env python3
"""Link the human checklist (data/checks.json) to the game's collectibles (data/collectibles.json).

Both lists describe the same 100 Gold Skulltulas and 36 Heart Pieces. data/check_links.json maps
check id -> {"instance", "confidence" (certain|likely|guess), "why"}; most of it was established by
hand (map renders, Banc actor neighbourhoods, dungeon room contents). This script

  (a) reproduces the mechanical part of that matching: per area and kind it builds the set of
      compatible (check, collectible) pairs from hard constraints and reports every pair that is
      forced, i.e. present in all perfect matchings of the area:
        - area + kind          (the per-area counts of the two lists agree)
        - era                  a collectible placed only in *_Child scenes needs a check playable as
                               child (same for adult); dungeon scenes carry no era
        - flag name            heart piece reward flags (MiniGame_Fishing_GetHeartPiece, ...) against
                               the check text
        - actor parameters     only with --actors <dump of tools/extract_banc.py>: IsMagicBeanSoil
                               <-> "soil" checks, pop-out-of-tree parameters <-> "tree" checks
  (b) --validate: checks data/check_links.json (all 136 checks covered, ids exist, one-to-one,
      area and kind agree, confidence values valid, no contradiction with a mechanically forced
      pair) and prints the counts per confidence. Exit status 1 on any error.

Usage:
  python3 tools/link_checks.py [--actors actors.json]              # print the mechanical result
  python3 tools/link_checks.py --validate [--actors actors.json]   # validate data/check_links.json
  python3 tools/link_checks.py --notes --actors actors.json        # era / night differences of the links
"""
import argparse, collections, itertools, json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KINDS = ('skulltula', 'heart_piece')
CONFIDENCES = ('certain', 'likely', 'guess')

# (regex on the collectible's flag name, regex on the check's title + description)
NAME_RULES = [
    (r'BombchuBowling', r'bowling'),
    (r'ChoiceTreasure', r'treasure chest (game|shop)'),
    (r'FindRichard', r'richard'),
    (r'Scrub_Business', r'business scrub'),
    (r'Fishing', r'fishing|\bfish\b'),
    (r'HasDived', r'\bdiv(e|ing)\b'),
    (r'FrogTenors_StormSong', r'^(?!.*follow-the-buttons).*song of storms'),
    (r'FrogTenors_InsectRepellent', r'follow-the-buttons'),
    (r'DiggingHole', r'\bdig\b|gravedigging'),
    (r'HorsebackArchery', r'archery'),
    (r'SkullKidSession', r'memory game'),
    (r'Npc_SkullKid_Child_IsGetHeartPiece', r"saria's song"),
    (r'GoronLargePot', r'\burn\b'),
    (r'Npc_Hylia_025', r'50 (gold skulltula )?tokens'),
]


def load(path):
    with open(os.path.join(REPO, path)) as f:
        return json.load(f)


def eras_of(col):
    """{'child'}, {'adult'}, both, or empty set (dungeon / era-less scene)."""
    out = set()
    for s in col.get('scenes') or [col.get('scene') or '']:
        parts = s.split('_')
        if 'Child' in parts:
            out.add('child')
        if 'Adult' in parts:
            out.add('adult')
    return out


def actor_params(path):
    """instance -> merged placement parameters of the skulltula actors (from an extract_banc.py dump)."""
    out = collections.defaultdict(dict)
    with open(path) as f:
        for a in json.load(f):
            if a.get('actor') == 'Enemy_Skulltula_Gold':
                out[a['hash']].update(a.get('dynamic') or {})
    return out


def compatible(check, col, params):
    text = (check['title'] + ' ' + check.get('description', '')).lower().replace('\n', ' ')
    ce, ie = set(check.get('era') or []), eras_of(col)
    if ie and ce and not (ie & ce):
        return False
    name = col.get('name') or ''
    for nre, tre in NAME_RULES:
        if re.search(nre, name) != None and not re.search(tre, text):
            return False
        if re.search(tre, text) and name and not name.startswith('IsTreasureBoxOpen') and not re.search(nre, name):
            # the check describes this reward, the collectible is a different reward
            if any(re.search(n2, name) for n2, _ in NAME_RULES):
                return False
    if params is not None and col['kind'] == 'skulltula':
        p = params.get(col['instance'], {})
        soil = bool(p.get('Enemy_Skulltula_Gold_IsMagicBeanSoil'))
        if soil != bool(re.search(r'soil patch', check['title'].lower())):
            return False
        tree = 'Enemy_Skulltula_Gold_AppearWarpRotOffset' in p
        if tree and not re.search(r'\btrees?\b', text):
            return False
    return True


def solve(checks, cols, params=None):
    """-> (forced {check id: instance}, open groups [(area, kind, [check ids], [instances], n matchings)], errors)"""
    forced, groups, errors = {}, [], []
    areas = sorted({c['area'] for c in checks})
    for area in areas:
        for kind in KINDS:
            cs = [c for c in checks if c['area'] == area and c['category'] == kind]
            ks = [k for k in cols if k['area'] == area and k['kind'] == kind]
            if len(cs) != len(ks):
                errors.append('%s %s: %d checks vs %d collectibles' % (area, kind, len(cs), len(ks)))
                continue
            if not cs:
                continue
            ok = [[compatible(c, k, params) for k in ks] for c in cs]
            matchings = [p for p in itertools.permutations(range(len(ks)))
                         if all(ok[i][p[i]] for i in range(len(cs)))]
            if not matchings:
                errors.append('%s %s: constraints leave no perfect matching' % (area, kind))
                continue
            rest_c, rest_k = [], set()
            for i, c in enumerate(cs):
                opts = {m[i] for m in matchings}
                if len(opts) == 1:
                    forced[c['id']] = ks[opts.pop()]['instance']
                else:
                    rest_c.append(c['id'])
                    rest_k |= {ks[j]['instance'] for j in opts}
            if rest_c:
                groups.append((area, kind, rest_c, sorted(rest_k), len(matchings)))
    return forced, groups, errors


def validate(checks, cols, forced, links):
    errs = []
    cby = {c['id']: c for c in checks if c['category'] in KINDS}
    kby = {k['instance']: k for k in cols if k['kind'] in KINDS}
    for cid in cby:
        if cid not in links:
            errs.append('missing link for %s' % cid)
    used = collections.defaultdict(list)
    for cid, l in links.items():
        c = cby.get(cid)
        if c is None:
            errs.append('%s: not a skulltula / heart piece check id' % cid)
            continue
        if not isinstance(l, dict) or not {'instance', 'confidence', 'why'} <= set(l):
            errs.append('%s: entry needs instance, confidence, why' % cid)
            continue
        k = kby.get(str(l['instance']))
        if k is None:
            errs.append('%s: unknown instance %s' % (cid, l['instance']))
            continue
        used[k['instance']].append(cid)
        if k['area'] != c['area']:
            errs.append('%s: area %s but instance is in %s' % (cid, c['area'], k['area']))
        if k['kind'] != c['category']:
            errs.append('%s: category %s but instance is a %s' % (cid, c['category'], k['kind']))
        if l['confidence'] not in CONFIDENCES:
            errs.append('%s: bad confidence %r' % (cid, l['confidence']))
        if not str(l['why']).strip():
            errs.append('%s: empty why' % cid)
        if cid in forced and forced[cid] != k['instance']:
            errs.append('%s: linked to %s but the hard constraints force %s' % (cid, k['instance'], forced[cid]))
    for inst, cids in used.items():
        if len(cids) > 1:
            errs.append('instance %s used by %s' % (inst, ', '.join(sorted(cids))))
    for inst in kby:
        if inst not in used:
            errs.append('instance %s (%s %s) is not linked' % (inst, kby[inst]['area'], kby[inst]['kind']))
    return errs


def notes(checks, cols, links, params):
    """Differences between the checklist and the game data for the linked pairs (not errors)."""
    cby = {c['id']: c for c in checks}
    kby = {k['instance']: k for k in cols}
    for cid in sorted(links, key=lambda x: (x[:2], int(x.split('-')[1]))):
        c, k = cby[cid], kby[links[cid]['instance']]
        ce, ie = set(c.get('era') or []), eras_of(k)
        if ie and ce != ie:
            print('era   %s checklist %s, game places it in %s  (%s: %s)'
                  % (cid, '/'.join(sorted(ce)), '/'.join(sorted(ie)), c['area'], c['title']))
        if params is not None and k['kind'] == 'skulltula':
            noct = bool(params.get(k['instance'], {}).get('Enemy_Skulltula_Gold_Nocturnal'))
            if noct != bool(c.get('night')):
                print('night %s checklist night=%s, game Nocturnal=%s  (%s: %s)'
                      % (cid, bool(c.get('night')), noct, c['area'], c['title']))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--validate', action='store_true', help='validate data/check_links.json')
    ap.add_argument('--notes', action='store_true', help='print era / night differences of the linked pairs')
    ap.add_argument('--actors', help='JSON dump of tools/extract_banc.py (enables the actor parameter constraints)')
    ap.add_argument('--links', default=os.path.join(REPO, 'data', 'check_links.json'))
    a = ap.parse_args()

    checks = [c for c in load('data/checks.json') if c['category'] in KINDS]
    cols = [k for k in load('data/collectibles.json') if k['kind'] in KINDS]
    params = actor_params(a.actors) if a.actors else None
    forced, groups, errors = solve(checks, cols, params)

    if not (a.validate or a.notes):
        for cid in sorted(forced, key=lambda x: (x[:2], int(x.split('-')[1]))):
            print('%s\t%s' % (cid, forced[cid]))
        print('\n%d of %d checks forced by hard constraints%s' % (
            len(forced), len(checks), '' if params is not None else ' (no --actors: area, era and flag names only)'))
        for area, kind, cs, ks, n in groups:
            print('open  %-22s %-11s %d matchings: %s <-> %d instances' % (area, kind, n, ' '.join(cs), len(ks)))
        for e in errors:
            print('ERROR', e)
        return 1 if errors else 0

    with open(a.links) as f:
        links = json.load(f)
    if a.notes:
        notes(checks, cols, links, params)
        return 0
    errs = errors + validate(checks, cols, forced, links)
    cby = {c['id']: c for c in checks}
    for kind in KINDS:
        cnt = collections.Counter(l.get('confidence') for cid, l in links.items()
                                  if cid in cby and cby[cid]['category'] == kind and isinstance(l, dict))
        print('%-11s %3d links: %s' % (kind, sum(cnt.values()),
                                       ', '.join('%s %d' % (c, cnt.get(c, 0)) for c in CONFIDENCES)))
    agree = sum(1 for cid, inst in forced.items() if cid in links and links[cid].get('instance') == inst)
    print('mechanical: %d forced pairs, %d agree with the file' % (len(forced), agree))
    for e in errs:
        print('ERROR', e)
    print('OK' if not errs else 'FAILED: %d errors' % len(errs))
    return 1 if errs else 0


if __name__ == '__main__':
    sys.exit(main())
