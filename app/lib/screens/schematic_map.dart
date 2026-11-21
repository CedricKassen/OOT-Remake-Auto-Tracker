import 'package:flutter/material.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../widgets.dart';
import 'areas.dart';

/// Where each area sits on the stylised overworld (a 1100 x 760 canvas,
/// north up), and which area it hangs off.
const Map<String, (double, double, String?)> _layout = {
  'hyrule_field': (560, 430, null),
  'lon_lon_ranch': (440, 340, 'hyrule_field'),
  'castle_town': (560, 240, 'hyrule_field'),
  'hyrule_castle': (560, 100, 'castle_town'),
  'ganons_castle': (410, 90, 'hyrule_castle'),
  'kakariko_village': (760, 270, 'hyrule_field'),
  'bottom_of_the_well': (670, 170, 'kakariko_village'),
  'graveyard': (900, 310, 'kakariko_village'),
  'shadow_temple': (1020, 250, 'graveyard'),
  'death_mountain_trail': (800, 140, 'kakariko_village'),
  'dodongos_cavern': (700, 50, 'death_mountain_trail'),
  'goron_city': (940, 150, 'death_mountain_trail'),
  'death_mountain_crater': (900, 50, 'death_mountain_trail'),
  'fire_temple': (1030, 60, 'death_mountain_crater'),
  'zoras_river': (790, 440, 'hyrule_field'),
  'zoras_domain': (940, 420, 'zoras_river'),
  'jabu_jabu': (1040, 360, 'zoras_domain'),
  'ice_cavern': (1040, 480, 'zoras_domain'),
  'kokiri_forest': (800, 620, 'hyrule_field'),
  'deku_tree': (700, 700, 'kokiri_forest'),
  'lost_woods': (940, 600, 'kokiri_forest'),
  'forest_temple': (1040, 690, 'lost_woods'),
  'lake_hylia': (470, 640, 'hyrule_field'),
  'water_temple': (350, 700, 'lake_hylia'),
  'gerudo_valley': (310, 430, 'hyrule_field'),
  'gerudo_fortress': (190, 310, 'gerudo_valley'),
  'desert_colossus': (110, 180, 'gerudo_fortress'),
  'spirit_temple': (120, 55, 'desert_colossus'),
};

const Size _canvas = Size(1100, 760);

class SchematicMap extends StatefulWidget {
  const SchematicMap({super.key, this.onOpenArea});

  /// Called when an area is tapped; by default its page is pushed.
  final void Function(String areaId)? onOpenArea;

  @override
  State<SchematicMap> createState() => _MapScreenState();
}

class _MapScreenState extends State<SchematicMap> {
  // Created once the available size is known, then kept so that live
  // updates do not reset where the user panned and zoomed to.
  TransformationController? _view;

  @override
  void dispose() {
    _view?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ClientScope.of(context).state;
    if (state == null) return const EmptyState();
    final scheme = Theme.of(context).colorScheme;

    // Areas the layout does not know are lined up along the bottom edge.
    final positions = <String, Offset>{};
    var spare = 0;
    for (final area in state.areas) {
      final place = _layout[area.id];
      positions[area.id] = place != null
          ? Offset(place.$1, place.$2)
          : Offset(80.0 + 110 * spare++, _canvas.height - 40);
    }
    final here = state.save?.area;

    return LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth / _canvas.width).clamp(0.2, box.maxHeight / _canvas.height).clamp(0.2, 1.0);
        if (_view == null) {
          // Show the whole map if it stays readable; otherwise (portrait
          // phones) open zoomed in on where the player is.
          final scale = fit >= 0.6 ? fit : 0.75;
          final focus = fit >= 0.6
              ? _canvas.center(Offset.zero)
              : positions[here] ?? positions['hyrule_field'] ?? _canvas.center(Offset.zero);
          double shift(double focus, double view, double extent) => extent * scale <= view
              ? (view - extent * scale) / 2
              : (view / 2 - focus * scale).clamp(view - extent * scale, 0.0);
          _view = TransformationController(
            Matrix4.identity()
              ..translateByDouble(
                shift(focus.dx, box.maxWidth, _canvas.width),
                shift(focus.dy, box.maxHeight, _canvas.height),
                0,
                1,
              )
              ..scaleByDouble(scale, scale, 1, 1),
          );
        }
        return InteractiveViewer(
          constrained: false,
          minScale: 0.25,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(120),
          transformationController: _view,
          child: SizedBox.fromSize(
            size: _canvas,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LinkPainter(positions, scheme.outlineVariant, scheme.surfaceContainerLow),
                  ),
                ),
                for (final area in state.areas)
                  if (area.progress.total > 0)
                    Positioned(
                      left: positions[area.id]!.dx - _AreaNode.width / 2,
                      top: positions[area.id]!.dy - _AreaNode.ring(area) / 2,
                      child: _AreaNode(
                        area: area,
                        here: area.id == here,
                        onTap: () =>
                            widget.onOpenArea != null ? widget.onOpenArea!(area.id) : openArea(context, area.id),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LinkPainter extends CustomPainter {
  _LinkPainter(this.positions, this.line, this.land);
  final Map<String, Offset> positions;
  final Color line;
  final Color land;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(36)), Paint()..color = land);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    _layout.forEach((id, place) {
      final from = positions[id], to = positions[place.$3];
      if (from != null && to != null) canvas.drawLine(from, to, paint);
    });
  }

  @override
  bool shouldRepaint(_LinkPainter old) => old.line != line || old.land != land;
}

class _AreaNode extends StatelessWidget {
  const _AreaNode({required this.area, required this.here, required this.onTap});
  final AreaState area;
  final bool here;
  final VoidCallback onTap;

  static const double width = 120;
  static double ring(AreaState area) => area.kind == 'dungeon' ? 50 : 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = ring(area);
    final missing = area.progress.missing;

    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: area.kind == 'dungeon' ? scheme.surfaceContainerHighest : scheme.surface,
                boxShadow: here ? [BoxShadow(color: scheme.primary, blurRadius: 14, spreadRadius: 3)] : null,
              ),
              child: ProgressRing(
                progress: area.progress,
                size: size,
                stroke: 5,
                child: missing == 0
                    ? const Icon(Icons.check, color: gold)
                    : Text('$missing', style: theme.textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              area.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall!.copyWith(
                color: here ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: here ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
