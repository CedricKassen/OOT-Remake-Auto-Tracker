import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../widgets.dart';
import 'areas.dart';
import 'schematic_map.dart';

/// Where each area's badge sits on the world illustration, as fractions of
/// its width and height. Placed by hand: the illustration has no coordinates.
const Map<String, (double, double)> _worldSpots = {
  'hyrule_field': (0.455, 0.560),
  'lon_lon_ranch': (0.375, 0.520),
  'castle_town': (0.425, 0.385),
  'hyrule_castle': (0.400, 0.245),
  'ganons_castle': (0.470, 0.280),
  'kakariko_village': (0.625, 0.415),
  'bottom_of_the_well': (0.585, 0.345),
  'graveyard': (0.730, 0.345),
  'shadow_temple': (0.790, 0.300),
  'death_mountain_trail': (0.570, 0.270),
  'dodongos_cavern': (0.535, 0.205),
  'goron_city': (0.650, 0.255),
  'death_mountain_crater': (0.630, 0.110),
  'fire_temple': (0.705, 0.190),
  'zoras_river': (0.610, 0.530),
  'zoras_domain': (0.775, 0.465),
  'jabu_jabu': (0.705, 0.525),
  'ice_cavern': (0.860, 0.440),
  'kokiri_forest': (0.615, 0.640),
  'deku_tree': (0.685, 0.730),
  'lost_woods': (0.700, 0.610),
  'forest_temple': (0.840, 0.640),
  'lake_hylia': (0.340, 0.800),
  'water_temple': (0.415, 0.870),
  'gerudo_valley': (0.245, 0.540),
  'gerudo_fortress': (0.200, 0.400),
  'desert_colossus': (0.130, 0.320),
  'spirit_temple': (0.165, 0.215),
};

const _mapBackdrop = Color(0xFF2B1D12);

/// The map: the game's world illustration with a badge per area, and the
/// game's own area and dungeon-floor maps with pins. Falls back to a drawn
/// diagram when the server has no map images.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.onOpenArea, this.initialArea});

  /// Opens the checklist of an area; by default its page is pushed.
  final void Function(String areaId)? onOpenArea;

  /// Start on this area's map instead of the world.
  final String? initialArea;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late String? _area = widget.initialArea;
  String? _mapId;

  void _openChecklist(String areaId) =>
      widget.onOpenArea != null ? widget.onOpenArea!(areaId) : openArea(context, areaId);

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final index = client.maps;
    if (state == null) return const EmptyState();
    final world = index?.world;
    if (index == null || world == null) return SchematicMap(onOpenArea: widget.onOpenArea);

    final area = state.areas.where((a) => a.id == _area).firstOrNull;
    final maps = area == null ? const <MapDef>[] : index.ofArea(area.id);
    if (area == null || maps.isEmpty) {
      return _WorldView(
        world: world,
        state: state,
        onArea: (id) {
          // Areas without a map of their own go straight to the checklist.
          if (index.ofArea(id).isEmpty) return _openChecklist(id);
          setState(() {
            _area = id;
            _mapId = null;
          });
        },
      );
    }

    final spoilerFree = client.spoilerFree;
    final save = state.save;
    final playerMap = save == null ? null : index.ofPlayer(save);
    final areaPins = state.pins.where((p) => p.area == area.id).toList();

    // Start on the map the player is on, else one with something missing,
    // else the first one of the current era.
    MapDef pick() {
      if (playerMap != null && maps.contains(playerMap)) return playerMap;
      final ofEra = maps.where((m) => m.era == null || m.era == save?.era).toList();
      final pool = ofEra.isEmpty ? maps : ofEra;
      if (!spoilerFree) {
        final open = pool.where((m) => index.pinsOn(m, areaPins).any((p) => !p.pin.done)).firstOrNull;
        if (open != null) return open;
      }
      return pool.first;
    }

    final map = maps.where((m) => m.id == _mapId).firstOrNull ?? pick();
    final placed = index.pinsOn(map, areaPins);
    final placedAnywhere = {
      for (final m in maps)
        for (final p in index.pinsOn(m, areaPins)) p.pin.id,
    };
    final unplaced = areaPins.where((p) => !p.done && !placedAnywhere.contains(p.id)).length;
    final missingHere = placed.where((p) => !p.pin.done).length;

    // The checklist entry behind each pin, where the match is known.
    final checkOf = {for (final c in state.checks) c.def.id: c};

    final theme = Theme.of(context);
    final caption = spoilerFree
        ? 'Spoiler-free mode: locations are hidden. ${area.progress.missing} missing in this area.'
        : [
            missingHere == 0 ? 'Nothing missing on this map' : '$missingHere missing on this map',
            if (unplaced > 0) '$unplaced more in places no map shows',
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _area = null),
                icon: const Icon(Icons.chevron_left, size: 20),
                label: const Text('Hyrule'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  maps.length > 1 && map.floor != null ? '${area.name} · ${map.floor}' : map.title,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: () => _openChecklist(area.id), child: const Text('Checklist')),
            ],
          ),
        ),
        if (maps.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final m in maps)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(m.label),
                      selected: m.id == map.id,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _mapId = m.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _Canvas(
            key: ValueKey(map.id),
            file: map.file,
            width: map.width.toDouble(),
            height: map.height.toDouble(),
            builder: (scale) => [
              if (!spoilerFree)
                // Collected ones first, so that missing ones are drawn on top.
                for (final p in [...placed]..sort((a, b) => (a.pin.done ? 0 : 1) - (b.pin.done ? 0 : 1)))
                  _at(p.x, p.y, _PinDot(pin: p.pin, scale: scale, check: checkOf[p.pin.check])),
              if (save?.position != null && playerMap?.id == map.id)
                () {
                  final (x, y) = map.project(save!.position!);
                  return _at(x, y, _PlayerDot(scale: scale));
                }(),
            ],
          ),
        ),
        Padding(
          // Clear of whatever covers the lower edge (the tab bar on iOS).
          padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + MediaQuery.paddingOf(context).bottom),
          child: Text(caption, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Centres [child] on a point of the map picture.
Widget _at(double x, double y, Widget child) => Positioned(
  left: x,
  top: y,
  child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
);

/// A map picture that can be panned and zoomed, with widgets placed on it in
/// picture coordinates. [builder] gets the scale at which the picture is
/// first shown, so that markers can keep a constant size on screen.
class _Canvas extends StatelessWidget {
  const _Canvas({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    required this.builder,
    this.backdrop = _mapBackdrop,
  });

  final String file;
  final double width;
  final double height;
  final List<Widget> Function(double scale) builder;
  final Color backdrop;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    return ColoredBox(
      color: backdrop,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, box) {
            final scale = (box.maxWidth / width).clamp(0.01, box.maxHeight / height);
            return InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: FittedBox(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: FutureBuilder<File?>(
                            future: client.mapImage(file),
                            builder: (context, snapshot) {
                              final image = snapshot.data;
                              if (image != null) {
                                return Image.file(image, fit: BoxFit.fill, gaplessPlayback: true);
                              }
                              return Center(
                                child: Transform.scale(
                                  scale: 1 / scale,
                                  child: snapshot.connectionState == ConnectionState.done
                                      ? const Text(
                                          'This map could not be loaded.',
                                          style: TextStyle(color: Colors.white70),
                                        )
                                      : const CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                        ),
                        ...builder(scale),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorldView extends StatelessWidget {
  const _WorldView({required this.world, required this.state, required this.onArea});
  final MapDef world;
  final TrackerState state;
  final ValueChanged<String> onArea;

  @override
  Widget build(BuildContext context) {
    final here = state.save?.area;
    final w = world.width.toDouble(), h = world.height.toDouble();
    return _Canvas(
      file: world.file,
      width: w,
      height: h,
      backdrop: const Color(0xFFB8862B),
      builder: (scale) => [
        for (final area in state.areas)
          if (area.progress.total > 0 && _worldSpots[area.id] != null)
            _at(
              _worldSpots[area.id]!.$1 * w,
              _worldSpots[area.id]!.$2 * h,
              _AreaBadge(area: area, here: area.id == here, scale: scale, onTap: () => onArea(area.id)),
            ),
      ],
    );
  }
}

/// How many are missing in an area, on the world illustration.
class _AreaBadge extends StatelessWidget {
  const _AreaBadge({required this.area, required this.here, required this.scale, required this.onTap});
  final AreaState area;
  final bool here;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final missing = area.progress.missing;
    final done = missing == 0;
    // Sized in screen pixels, whatever the picture is scaled to.
    // Smaller where the whole picture is small (phones), so badges stay apart.
    final onScreen = (scale * 110).clamp(19.0, 32.0);
    final size = (area.kind == 'dungeon' ? onScreen * 0.82 : onScreen) / scale;
    return Tooltip(
      message: done ? '${area.name}: complete' : '${area.name}: $missing missing',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? const Color(0xE63E6B45) : const Color(0xF2221812),
            border: Border.all(
              color: here ? const Color(0xFF5AB0FF) : (done ? const Color(0xFFB9D7B0) : gold),
              width: (here ? 3.0 : 2.0) / scale,
            ),
            boxShadow: [
              BoxShadow(
                color: here ? const Color(0xCC5AB0FF) : Colors.black54,
                blurRadius: (here ? 10 : 4) / scale,
                spreadRadius: (here ? 2 : 0) / scale,
              ),
            ],
          ),
          child: done
              ? Icon(Icons.check, size: size * 0.6, color: Colors.white)
              : Text(
                  '$missing',
                  style: TextStyle(color: Colors.white, fontSize: size * 0.46, fontWeight: FontWeight.w700, height: 1),
                ),
        ),
      ),
    );
  }
}

/// A collectible on an area map: bright when missing, faint when collected.
class _PinDot extends StatelessWidget {
  const _PinDot({required this.pin, required this.scale, this.check});
  final Pin pin;
  final double scale;

  /// The checklist entry this pin is, if that is known.
  final CheckState? check;

  @override
  Widget build(BuildContext context) {
    final look = CategoryStyle.of(pin.category);
    final kind = categoryName(pin.category).replaceFirst(RegExp(r's$'), '');
    final def = check?.def;
    // "Gold Skulltula #39: Underside of the small bridge" where the entry is known.
    final name = def == null
        ? kind
        : '$kind${def.number == null ? '' : ' #${def.number}'}: ${def.title}'
              '${check!.uncertain ? ' (match not certain)' : ''}';
    final missing = def == null || def.description.isEmpty ? '$name (missing)' : '$name\n${def.description}\n(missing)';
    if (pin.done) {
      final size = 14 / scale;
      return Tooltip(
        message: '$name (collected)',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black45,
            border: Border.all(color: look.color.withValues(alpha: 0.7), width: 1.5 / scale),
          ),
          child: Icon(Icons.check, size: size * 0.7, color: Colors.white70),
        ),
      );
    }
    final size = 26 / scale;
    return Tooltip(
      message: missing,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: look.color,
          border: Border.all(color: Colors.white, width: 2 / scale),
          boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 5 / scale)],
        ),
        child: AppIcon(look.icon, size: size * 0.6, color: const Color(0xFF1B1208)),
      ),
    );
  }
}

/// Where the player stood at the last save.
class _PlayerDot extends StatelessWidget {
  const _PlayerDot({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = 18 / scale;
    return Tooltip(
      message: 'You, at the last save',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2F8FFF),
          border: Border.all(color: Colors.white, width: 3 / scale),
          boxShadow: [BoxShadow(color: const Color(0xAA2F8FFF), blurRadius: 12 / scale, spreadRadius: 3 / scale)],
        ),
      ),
    );
  }
}
