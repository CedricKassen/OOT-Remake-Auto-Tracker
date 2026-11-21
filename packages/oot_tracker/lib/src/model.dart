/// Game data definitions and the tracker state sent over the API.
/// Everything here is plain data with JSON (de)serialisation, shared by the
/// server and the app.
library;

typedef Json = Map<String, dynamic>;

/// Check categories, in display order.
const List<String> categories = [
  'skulltula',
  'heart_piece',
  'reward',
  'song',
  'item',
  'equipment',
  'upgrade',
  'mask',
  'bottle',
];

const Map<String, String> categoryNames = {
  'skulltula': 'Gold Skulltulas',
  'heart_piece': 'Heart Pieces',
  'reward': 'Dungeon Rewards',
  'song': 'Songs',
  'item': 'Items',
  'equipment': 'Equipment',
  'upgrade': 'Upgrades',
  'mask': 'Masks',
  'bottle': 'Bottles',
};

class AreaDef {
  AreaDef({
    required this.id,
    required this.name,
    required this.kind,
    this.bancs = const [],
    this.visitFlag,
  });

  final String id;
  final String name;

  /// `overworld` or `dungeon`.
  final String kind;

  /// The game's scene names that belong to this area.
  final List<String> bancs;

  /// Name of the Bool field that is set once the area was visited, if known.
  final String? visitFlag;

  factory AreaDef.fromJson(Json j) => AreaDef(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: j['kind'] as String? ?? 'overworld',
    bancs: (j['bancs'] as List? ?? const []).cast<String>(),
    visitFlag: j['visitFlag'] as String?,
  );
}

class CheckDef {
  CheckDef({
    required this.id,
    required this.area,
    required this.category,
    required this.title,
    this.number,
    this.description = '',
    this.era = const [],
    this.night = false,
    this.requires = const [],
    this.verified = false,
    this.source,
  });

  final String id;
  final String area;
  final String category;
  final String title;
  final int? number;
  final String description;
  final List<String> era;
  final bool night;
  final List<String> requires;

  /// Whether the entry was checked against the remake (not just the original).
  final bool verified;

  /// How completion is read from the save; null means ticked by hand.
  /// One of `{stock: actor}`, `{flag: name}`, `{hash: "0x…"}`,
  /// `{magic: n}`, `{bottle: n}`.
  final Json? source;

  factory CheckDef.fromJson(Json j) => CheckDef(
    id: j['id'] as String,
    area: j['area'] as String,
    category: j['category'] as String,
    title: j['title'] as String,
    number: j['number'] as int?,
    description: j['description'] as String? ?? '',
    era: (j['era'] as List? ?? const []).cast<String>(),
    night: j['night'] as bool? ?? false,
    requires: (j['requires'] as List? ?? const []).cast<String>(),
    verified: j['verified'] as bool? ?? false,
    source: (j['source'] as Map?)?.cast<String, dynamic>(),
  );
}

/// A collectible whose save flag is known, but not which checklist entry it
/// is. It still tells how many of a category were collected in an area.
class Collectible {
  Collectible({required this.area, required this.category, this.instance = '', this.scenes = const [], this.hash, this.key64, this.pos});
  final String area;
  final String category;

  /// The actor's instance id in the game data.
  final String instance;

  /// The game scenes that place it, e.g. `HyruleField_Adult`.
  final List<String> scenes;

  /// Hash of its Bool field, or
  final int? hash;

  /// its key in the save's 64-bit key store.
  final int? key64;
  final List<double>? pos;

  /// Reads an entry of `collectibles.json`; null if it has no area or flag.
  static Collectible? fromJson(Json j) {
    final hash = j['hash'] as String?;
    final key = j['key64'] as String?;
    if (j['area'] == null || (hash == null && key == null)) return null;
    return Collectible(
      area: j['area'] as String,
      category: j['kind'] as String,
      instance: j['instance'] as String? ?? '',
      scenes: (j['scenes'] as List? ?? [j['scene']]).whereType<String>().toList(),
      hash: hash == null ? null : int.parse(hash.substring(2), radix: 16),
      key64: key == null ? null : BigInt.parse(key.substring(2), radix: 16).toSigned(64).toInt(),
      pos: (j['pos'] as List?)?.map((v) => (v as num).toDouble()).toList(),
    );
  }
}

class GameData {
  GameData({required this.areas, required this.checks, this.collectibles = const [], this.links = const {}});
  final List<AreaDef> areas;
  final List<CheckDef> checks;
  final List<Collectible> collectibles;

  /// Check id -> the collectible it is (instance id) and how sure that is
  /// (`certain`, `likely` or `guess`). From `check_links.json`.
  final Map<String, (String, String)> links;

  factory GameData.fromJson(List areas, List checks, [List collectibles = const [], Map links = const {}]) => GameData(
    links: {
      for (final e in links.entries)
        if (e.value is Map && (e.value as Map)['instance'] != null)
          e.key as String: ('${(e.value as Map)['instance']}', (e.value as Map)['confidence'] as String? ?? 'guess'),
    },
    areas: [for (final a in areas) AreaDef.fromJson((a as Map).cast())],
    checks: [for (final c in checks) CheckDef.fromJson((c as Map).cast())],
    collectibles: [
      for (final c in collectibles) ?Collectible.fromJson((c as Map).cast()),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tracker state (API payload)

class Progress {
  const Progress(this.done, this.total);
  final int done;
  final int total;
  int get missing => total - done;
  double get fraction => total == 0 ? 1 : done / total;

  factory Progress.fromJson(Json j) => Progress(j['done'] as int, j['total'] as int);
  Json toJson() => {'done': done, 'total': total};

  static Map<String, Progress> mapFromJson(Object? j) => {
    for (final e in ((j as Map?) ?? const {}).entries)
      e.key as String: Progress.fromJson((e.value as Map).cast()),
  };
}

/// What the save says about the player right now.
class SaveInfo {
  SaveInfo({
    required this.slot,
    required this.savedAt,
    required this.autosave,
    required this.banc,
    required this.area,
    required this.era,
    required this.hearts,
    required this.life,
    required this.heartPieceStock,
    required this.rupees,
    required this.tokens,
    required this.magic,
    this.position,
  });

  final String slot;

  /// Local save time `yyyy-MM-ddTHH:mm:ss`, or null if the slot has none.
  final String? savedAt;
  final bool autosave;

  /// The game's name of the current scene, e.g. `KokiriForest_Adult`.
  final String banc;

  /// Id of the area the player is in, if it maps to one.
  final String? area;

  /// `child` or `adult`.
  final String era;

  /// Heart containers (maximum hearts).
  final int hearts;

  /// Current life in quarter hearts.
  final int life;

  /// Heart pieces held towards the next container (0-3).
  final int heartPieceStock;
  final int rupees;
  final int tokens;

  /// Magic meter size: 0 none, 1 normal, 2 doubled.
  final int magic;
  final List<double>? position;

  factory SaveInfo.fromJson(Json j) => SaveInfo(
    slot: j['slot'] as String,
    savedAt: j['savedAt'] as String?,
    autosave: j['autosave'] as bool? ?? false,
    banc: j['banc'] as String? ?? '',
    area: j['area'] as String?,
    era: j['era'] as String? ?? 'child',
    hearts: j['hearts'] as int? ?? 0,
    life: j['life'] as int? ?? 0,
    heartPieceStock: j['heartPieceStock'] as int? ?? 0,
    rupees: j['rupees'] as int? ?? 0,
    tokens: j['tokens'] as int? ?? 0,
    magic: j['magic'] as int? ?? 0,
    position: (j['position'] as List?)?.map((v) => (v as num).toDouble()).toList(),
  );

  Json toJson() => {
    'slot': slot,
    'savedAt': savedAt,
    'autosave': autosave,
    'banc': banc,
    'area': area,
    'era': era,
    'hearts': hearts,
    'life': life,
    'heartPieceStock': heartPieceStock,
    'rupees': rupees,
    'tokens': tokens,
    'magic': magic,
    'position': position,
  };
}

class CheckState {
  CheckState({required this.def, required this.done, required this.auto, this.uncertain = false});
  final CheckDef def;
  final bool done;

  /// True when [done] is read from the save, false when it is a manual tick.
  final bool auto;

  /// True when [done] comes from a save flag that was matched to this entry
  /// by a guess: the count is right, but it may be a neighbouring entry.
  final bool uncertain;

  factory CheckState.fromJson(Json j) => CheckState(
    def: CheckDef.fromJson(j),
    done: j['done'] as bool,
    auto: j['auto'] as bool,
    uncertain: j['uncertain'] as bool? ?? false,
  );

  Json toJson() => {
    'id': def.id,
    'area': def.area,
    'category': def.category,
    'title': def.title,
    if (def.number != null) 'number': def.number,
    'description': def.description,
    'era': def.era,
    if (def.night) 'night': true,
    'requires': def.requires,
    'verified': def.verified,
    'done': done,
    'auto': auto,
    if (uncertain) 'uncertain': true,
  };
}

class AreaState {
  AreaState({
    required this.id,
    required this.name,
    required this.kind,
    required this.visited,
    required this.progress,
    required this.byCategory,
    this.anonymous = const {},
    this.counted = const [],
  });
  final String id;
  final String name;
  final String kind;

  /// Per category: how many of the done count are finds the player marked
  /// without saying which check they were.
  final Map<String, int> anonymous;

  /// Categories whose done count here is read from the save, although the
  /// save cannot tell which of the checks they are.
  final List<String> counted;

  /// Whether the save shows the area was entered; null if the save cannot tell.
  final bool? visited;
  final Progress progress;
  final Map<String, Progress> byCategory;

  factory AreaState.fromJson(Json j) => AreaState(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: j['kind'] as String? ?? 'overworld',
    visited: j['visited'] as bool?,
    progress: Progress.fromJson((j['progress'] as Map).cast()),
    byCategory: Progress.mapFromJson(j['byCategory']),
    anonymous: ((j['anonymous'] as Map?) ?? const {}).cast<String, int>(),
    counted: (j['counted'] as List? ?? const []).cast<String>(),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'visited': visited,
    'anonymous': anonymous,
    'counted': counted,
    'progress': progress.toJson(),
    'byCategory': {for (final e in byCategory.entries) e.key: e.value.toJson()},
  };
}

/// A collectible at a known place in the game world, for the map.
class Pin {
  Pin({required this.id, this.check, required this.category, required this.area, required this.scenes, required this.pos, required this.done});
  /// The actor's instance id.
  final String id;

  /// Id of the checklist entry this is, if known.
  final String? check;
  final String category;
  final String area;
  final List<String> scenes;

  /// Position in scene coordinates: x, y (height), z.
  final List<double> pos;
  final bool done;

  factory Pin.fromJson(Json j) => Pin(
    id: j['id'] as String? ?? '',
    check: j['check'] as String?,
    category: j['category'] as String,
    area: j['area'] as String,
    scenes: (j['scenes'] as List).cast<String>(),
    pos: (j['pos'] as List).map((v) => (v as num).toDouble()).toList(),
    done: j['done'] as bool,
  );
  Json toJson() => {'id': id, if (check != null) 'check': check, 'category': category, 'area': area, 'scenes': scenes, 'pos': pos, 'done': done};
}

/// A disagreement between what is ticked and what the save counts.
class Mismatch {
  Mismatch({required this.category, required this.save, required this.ticked, this.estimate = false});
  final String category;

  /// How many the save says were collected.
  final int save;

  /// How many checks of the category are marked done.
  final int ticked;

  /// True when [save] is derived indirectly and may be slightly off.
  final bool estimate;

  factory Mismatch.fromJson(Json j) => Mismatch(
    category: j['category'] as String,
    save: j['save'] as int,
    ticked: j['ticked'] as int,
    estimate: j['estimate'] as bool? ?? false,
  );
  Json toJson() => {'category': category, 'save': save, 'ticked': ticked, 'estimate': estimate};
}

class TrackerState {
  TrackerState({
    required this.save,
    required this.areas,
    required this.checks,
    required this.total,
    required this.byCategory,
    required this.mismatches,
    this.pins = const [],
    this.error,
  });

  static const int apiVersion = 1;

  /// Null while no save could be read; [error] then says why.
  final SaveInfo? save;
  final List<AreaState> areas;
  final List<CheckState> checks;
  final Progress total;
  final Map<String, Progress> byCategory;
  final List<Mismatch> mismatches;

  /// Where each located collectible is and whether the save has it.
  final List<Pin> pins;
  final String? error;

  factory TrackerState.fromJson(Json j) => TrackerState(
    save: j['save'] == null ? null : SaveInfo.fromJson((j['save'] as Map).cast()),
    areas: [for (final a in j['areas'] as List) AreaState.fromJson((a as Map).cast())],
    checks: [for (final c in j['checks'] as List) CheckState.fromJson((c as Map).cast())],
    total: Progress.fromJson((j['total'] as Map).cast()),
    byCategory: Progress.mapFromJson(j['byCategory']),
    mismatches: [for (final m in j['mismatches'] as List? ?? const []) Mismatch.fromJson((m as Map).cast())],
    pins: [for (final p in j['pins'] as List? ?? const []) Pin.fromJson((p as Map).cast())],
    error: j['error'] as String?,
  );

  Json toJson() => {
    'version': apiVersion,
    'save': save?.toJson(),
    'error': error,
    'total': total.toJson(),
    'byCategory': {for (final e in byCategory.entries) e.key: e.value.toJson()},
    'mismatches': [for (final m in mismatches) m.toJson()],
    'areas': [for (final a in areas) a.toJson()],
    'checks': [for (final c in checks) c.toJson()],
    'pins': [for (final p in pins) p.toJson()],
  };
}
