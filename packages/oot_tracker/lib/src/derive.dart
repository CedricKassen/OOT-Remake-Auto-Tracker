import 'package:oot_save/oot_save.dart';

import 'model.dart';

final Map<String, int> _stockHash = {for (final i in inventoryItems) i.$1: i.$4};
const _bottleSlots = ['BottleA', 'BottleB', 'BottleC', 'BottleD', 'BottleE'];
const _medallions = ['Forest', 'Fire', 'Water', 'Shadow', 'Spirit'];
const _stones = ['Forest', 'Fire', 'Water'];

int _stock(SaveFile save, String actor) =>
    save.integer(_stockHash[actor] ?? murmur3('PouchData.$actor.StockNum')) ?? 0;

int? _parseHash(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value.replaceFirst(RegExp('^0[xX]'), ''), radix: 16);
  return null;
}

/// Whether the save can answer [source], and the answer. Returns null when
/// the check has to be ticked by hand (no source, or its field is missing).
bool? evaluateSource(SaveFile save, Json? source) {
  if (source == null) return null;
  if (source['stock'] case final String actor) {
    // Owned now, or acquired at some point: the game keeps `IsGet.<actor>`
    // set after an item is traded on or handed back.
    final stock = save.integer(_stockHash[actor] ?? murmur3('PouchData.$actor.StockNum'));
    final acquired = save.booleanNamed('IsGet.$actor');
    if (stock == null && acquired == null) return null;
    return (stock ?? 0) > 0 || (acquired ?? false);
  }
  if (source['flag'] case final String name) return save.booleanNamed(name);
  if (source.containsKey('hash')) {
    final hash = _parseHash(source['hash']);
    return hash == null ? null : save.boolean(hash);
  }
  if (source['magic'] case final int size) {
    final max = save.integerNamed('PlayerStatus.MPMax');
    return max == null ? null : max ~/ 10 >= size;
  }
  if (source['bottle'] case final int count) {
    return _bottleSlots.where((slot) => _stock(save, slot) > 0).length >= count;
  }
  return null;
}

/// Maps the game's scene name (e.g. `KokiriForest_Adult`) to an area id.
String? areaOfBanc(String banc, List<AreaDef> areas) {
  final base = banc.replaceFirst(RegExp(r'_(Adult|Child)$'), '');
  String? best;
  var bestLength = -1;
  for (final area in areas) {
    for (final name in area.bancs) {
      if (name == base) return area.id;
      if (base.startsWith(name) && name.length > bestLength) {
        best = area.id;
        bestLength = name.length;
      }
    }
  }
  return best;
}

SaveInfo readSaveInfo(SaveSlot slot, List<AreaDef> areas) {
  final save = slot.progress;
  final banc = save.stringNamed('Sequence_CurrentBanc') ?? '';
  final magicMax = (save.integerNamed('PlayerStatus.MPMax') ?? 0) ~/ 10;
  return SaveInfo(
    slot: slot.id,
    savedAt: slot.time?.toString(),
    autosave: slot.isAutosave,
    banc: banc,
    area: areaOfBanc(banc, areas),
    era: (save.booleanNamed('Sequence_IsChildhood') ?? true) ? 'child' : 'adult',
    hearts: (save.integerNamed('PlayerStatus.MaxLife') ?? 0) ~/ 4,
    life: save.integerNamed('PlayerStatus.Life') ?? 0,
    heartPieceStock: _stock(save, 'Obj_Heart_Piece'),
    rupees: save.integerNamed('PlayerStatus.CurrentRupee') ?? 0,
    tokens: _stock(save, 'Item_Token_Gold'),
    magic: magicMax >= 48 ? 2 : (magicMax >= 24 ? 1 : 0),
    position: save.vector3(murmur3('PlayerStatus.SavePos')),
  );
}

/// Heart pieces collected so far, estimated from the heart total: three
/// starting hearts and one container per cleared dungeon (assumed taken) are
/// subtracted, the rest came from pieces.
int estimateHeartPieces(SaveFile save) {
  final hearts = (save.integerNamed('PlayerStatus.MaxLife') ?? 12) ~/ 4;
  final containers =
      _stones.where((s) => _stock(save, 'Item_Stone_$s') > 0).length +
      _medallions.where((m) => _stock(save, 'Item_Medal_$m') > 0).length;
  final pieces = (hearts - 3 - containers) * 4 + _stock(save, 'Obj_Heart_Piece');
  return pieces.clamp(0, 36);
}

/// Combines the game data, a save slot and the manual input into the state
/// the app shows.
///
/// [flagMap] maps check ids to Bool field hashes found by research; it turns
/// manual checks into save-driven ones. [anonymous] counts collectibles the
/// player marked as found without saying which (spoiler-free mode), keyed by
/// `<area id>/<category>`; they count towards progress but tick no check.
TrackerState deriveState(
  GameData data,
  SaveSlot? slot, {
  Set<String> manualTicks = const {},
  Map<String, int> anonymous = const {},
  Map<String, int> flagMap = const {},
  String? error,
}) {
  final save = slot?.progress;
  bool has(Collectible c) {
    if (c.listed case final listed?) {
      final at = save!.array(listed.ids)?.indexOf(listed.id) ?? -1;
      final flags = save.array(listed.flags);
      return at >= 0 && flags != null && at < flags.length && flags[at] == true;
    }
    return c.key64 != null ? save!.hasKey64(c.key64!) : save!.boolean(c.hash!) ?? false;
  }
  final byInstance = {for (final c in data.collectibles) c.instance: c};
  final checkOfInstance = {for (final e in data.links.entries) e.value.$1: e.key};

  final checks = <CheckState>[];
  for (final def in data.checks) {
    bool? fromSave;
    var uncertain = false;
    if (save != null) {
      final mapped = flagMap[def.id];
      final link = data.links[def.id];
      final linked = link == null ? null : byInstance[link.$1];
      // A link says which collectible in the save this entry is. A guessed
      // link does not override a source the entry already has.
      if (mapped != null) {
        fromSave = save.boolean(mapped);
      } else if (linked != null && (def.source == null || link!.$2 != 'guess')) {
        fromSave = has(linked);
        // Anything short of hard evidence could be a neighbouring entry.
        uncertain = link!.$2 != 'certain';
      } else {
        fromSave = evaluateSource(save, def.source);
      }
    }
    checks.add(
      CheckState(
        def: def,
        done: fromSave ?? manualTicks.contains(def.id),
        auto: fromSave != null,
        uncertain: uncertain,
      ),
    );
  }

  final totals = <String, Progress>{};
  final areas = <AreaState>[];
  for (final area in data.areas) {
    final own = checks.where((c) => c.def.area == area.id).toList();
    final byCategory = <String, Progress>{};
    final anonymousHere = <String, int>{};
    final counted = <String>[];
    for (final category in categories) {
      final list = own.where((c) => c.def.category == category).toList();
      if (list.isEmpty) continue;
      var done = list.where((c) => c.done).length;
      var extra = 0;
      final known = data.collectibles.where((c) => c.area == area.id && c.category == category).toList();
      if (save != null && known.length == list.length) {
        // The save knows every collectible of this kind here: its count is
        // the truth, ticks only say which ones they are.
        done = known.where(has).length;
        counted.add(category);
        // All or none collected: then every single check is known as well.
        if (done == list.length || done == 0) {
          for (final check in list) {
            if (check.auto && !check.uncertain && check.done == done > 0) continue;
            checks[checks.indexOf(check)] = CheckState(def: check.def, done: done > 0, auto: true);
          }
        }
      } else {
        // Anonymous finds can only stand in for manual checks not ticked yet.
        final open = list.where((c) => !c.auto && !c.done).length;
        extra = (anonymous['${area.id}/$category'] ?? 0).clamp(0, open);
        if (extra > 0) anonymousHere[category] = extra;
      }
      byCategory[category] = Progress(done + extra, list.length);
      final total = totals[category] ?? const Progress(0, 0);
      totals[category] = Progress(total.done + done + extra, total.total + list.length);
    }
    areas.add(
      AreaState(
        id: area.id,
        name: area.name,
        kind: area.kind,
        visited: save == null || area.visitFlag == null ? null : save.booleanNamed(area.visitFlag!),
        progress: Progress(
          byCategory.values.fold(0, (sum, p) => sum + p.done),
          byCategory.values.fold(0, (sum, p) => sum + p.total),
        ),
        byCategory: byCategory,
        anonymous: anonymousHere,
        counted: counted,
      ),
    );
  }
  final byCategory = {
    for (final category in categories)
      if (totals[category] != null) category: totals[category]!,
  };

  final mismatches = <Mismatch>[];
  if (save != null) {
    void compare(String category, int fromSave, {bool estimate = false}) {
      final ticked = byCategory[category]?.done;
      // Only meaningful while the category is ticked by hand somewhere.
      final manual =
          checks.any((c) => c.def.category == category && !c.auto) &&
          areas.any((a) => a.byCategory.containsKey(category) && !a.counted.contains(category));
      if (ticked != null && manual && ticked != fromSave) {
        mismatches.add(Mismatch(category: category, save: fromSave, ticked: ticked, estimate: estimate));
      }
    }

    compare('skulltula', _stock(save, 'Item_Token_Gold'));
    compare('heart_piece', estimateHeartPieces(save), estimate: true);
  }

  return TrackerState(
    save: slot == null ? null : readSaveInfo(slot, data.areas),
    areas: areas,
    checks: checks,
    total: Progress(
      byCategory.values.fold(0, (sum, p) => sum + p.done),
      byCategory.values.fold(0, (sum, p) => sum + p.total),
    ),
    byCategory: byCategory,
    mismatches: mismatches,
    pins: [
      if (save != null)
        for (final c in data.collectibles)
          if (c.pos != null && categories.contains(c.category))
            Pin(
              id: c.instance,
              check: checkOfInstance[c.instance],
              category: c.category,
              area: c.area,
              scenes: c.scenes,
              pos: c.pos!,
              done: has(c),
            ),
    ],
    error: error,
  );
}
