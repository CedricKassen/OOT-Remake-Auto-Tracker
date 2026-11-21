import 'model.dart';

/// One map image of the game with the transform from scene coordinates to
/// its pixels. Built from an entry of `maps.json`.
class MapDef {
  MapDef({
    required this.id,
    required this.file,
    required this.width,
    required this.height,
    required this.title,
    required this.kind,
    this.scenes = const [],
    this.bancs = const [],
    this.areas = const [],
    this.era,
    this.floor,
    this.floorIndex = 0,
    this.yMin,
    this.yMax,
    this.ax = 1,
    this.bx = 0,
    this.az = 1,
    this.bz = 0,
  });

  final String id;
  final String file;
  final int width;
  final int height;
  final String title;

  /// `field`, `dungeon` or `world` (the illustration, without coordinates).
  final String kind;

  /// Scene base names drawn on this map, and the exact scene names.
  final List<String> scenes;
  final List<String> bancs;

  /// Tracker area ids this map belongs to.
  final List<String> areas;

  /// `child` or `adult` when the map exists per era, else null.
  final String? era;

  /// Floor label (`B1`, `2F`) of a dungeon floor map, with the height range
  /// it covers; an open end is null.
  final String? floor;
  final int floorIndex;
  final double? yMin;
  final double? yMax;

  // px = ax * x + bx, py = az * z + bz
  final double ax, bx, az, bz;

  /// What to call this map among the maps of one area.
  String get label {
    final eraName = era == null ? '' : (era == 'child' ? ' · Child' : ' · Adult');
    return floor != null ? floor! : '$title$eraName';
  }

  /// Pixel position of a scene position `[x, y, z]`.
  (double, double) project(List<double> pos) => (ax * pos[0] + bx, az * pos[2] + bz);

  bool _inImage(List<double> pos, {double margin = 0}) {
    final (px, py) = project(pos);
    return px >= -margin && py >= -margin && px <= width + margin && py <= height + margin;
  }

  bool _onFloor(List<double> pos) =>
      (yMin == null || pos[1] >= yMin!) && (yMax == null || pos[1] < yMax!);

  /// Whether a position in scene [banc] is shown on this map.
  bool covers(String banc, List<double> pos) {
    final base = banc.replaceAll(RegExp(r'_(Adult|Child|Alternative)'), '');
    if (!bancs.contains(banc) && !scenes.contains(base)) return false;
    return _inImage(pos) && _onFloor(pos);
  }

  factory MapDef.fromJson(Json j) {
    final t = ((j['transform'] as Map?)?['*'] as Map?)?.cast<String, dynamic>();
    final floor = (j['floor'] as Map?)?.cast<String, dynamic>();
    double n(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
    return MapDef(
      id: j['id'] as String,
      file: j['file'] as String,
      width: j['width'] as int,
      height: j['height'] as int,
      title: j['title'] as String? ?? j['id'] as String,
      kind: j['kind'] as String? ?? 'field',
      scenes: (j['scenes'] as List? ?? const []).cast<String>(),
      bancs: (j['bancs'] as List? ?? const []).cast<String>(),
      areas: (j['areas'] as List? ?? const []).cast<String>(),
      era: j['era'] as String?,
      floor: floor?['label'] as String?,
      floorIndex: floor?['index'] as int? ?? 0,
      yMin: (floor?['ymin'] as num?)?.toDouble(),
      yMax: (floor?['ymax'] as num?)?.toDouble(),
      ax: n(t?['ax'], 1),
      bx: n(t?['bx'], 0),
      az: n(t?['az'], 1),
      bz: n(t?['bz'], 0),
    );
  }
}

/// A pin placed on one map.
class PlacedPin {
  PlacedPin(this.pin, this.x, this.y);
  final Pin pin;
  final double x, y;
}

/// All maps, plus the game's own assignment of collectibles to maps.
class MapIndex {
  MapIndex({required this.maps, this.instances = const {}});
  final List<MapDef> maps;

  /// Actor instance id -> the maps its icon is on and the icon position.
  final Map<String, (List<String>, List<double>)> instances;

  bool get isEmpty => maps.isEmpty;

  MapDef? get world => maps.where((m) => m.kind == 'world').firstOrNull;

  factory MapIndex.fromJson(Json j) => MapIndex(
    maps: [for (final m in j['maps'] as List? ?? const []) MapDef.fromJson((m as Map).cast())],
    instances: {
      for (final e in ((j['instances'] as Map?) ?? const {}).entries)
        e.key as String: (
          ((e.value as Map)['maps'] as List).cast<String>(),
          ((e.value as Map)['pos'] as List).map((v) => (v as num).toDouble()).toList(),
        ),
    },
  );

  /// The maps of an area: outdoor maps first, then floors from the bottom up.
  List<MapDef> ofArea(String areaId) =>
      maps.where((m) => m.kind != 'world' && m.areas.contains(areaId)).toList()
        ..sort((a, b) => a.floorIndex.compareTo(b.floorIndex));

  /// The pins shown on [map]. The game's own assignment decides where it
  /// exists; otherwise scene, picture bounds and floor height do.
  List<PlacedPin> pinsOn(MapDef map, List<Pin> pins) {
    final placed = <PlacedPin>[];
    for (final pin in pins) {
      final assigned = instances[pin.id];
      final List<double> pos;
      if (assigned != null) {
        // A collectible assigned to one era's map is shown on the other
        // era's map of the same place as well.
        final sameMap = assigned.$1.contains(map.id);
        final sibling =
            map.era != null &&
            assigned.$1.any((id) => id != map.id && id.replaceAll(RegExp(r'_(Adult|Child)$'), '') == map.id.replaceAll(RegExp(r'_(Adult|Child)$'), '')) &&
            pin.scenes.any(map.bancs.contains);
        if (!sameMap && !sibling) continue;
        // Something that exists in one era only is not on the other era's map.
        if (map.era != null && !pin.scenes.any(map.bancs.contains)) continue;
        pos = assigned.$2;
      } else {
        if (!pin.scenes.any((scene) => map.covers(scene, pin.pos))) continue;
        pos = pin.pos;
      }
      if (!map._inImage(pos, margin: 40)) continue;
      final (x, y) = map.project(pos);
      placed.add(PlacedPin(pin, x, y));
    }
    return placed;
  }

  /// The map the player is on, if any.
  MapDef? ofPlayer(SaveInfo save) {
    final pos = save.position;
    final candidates = maps.where((m) => m.bancs.contains(save.banc)).toList();
    if (candidates.isEmpty) return null;
    if (pos == null) return candidates.first;
    return candidates.where((m) => m.covers(save.banc, pos)).firstOrNull ?? candidates.first;
  }
}
