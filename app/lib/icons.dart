import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oot_tracker/oot_tracker.dart';

/// Icons drawn by this app, for things the stock icon sets have no fitting
/// picture of.
enum Glyph { rupee, skull, bottle, medallion }

/// Shows a stock icon ([IconData]) or one of the app's own ([Glyph]).
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  /// An [IconData] or a [Glyph].
  final Object icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color ?? const Color(0xFF000000);
    final icon = this.icon;
    if (icon is IconData) return Icon(icon, size: size, color: color);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(icon as Glyph, color)),
    );
  }
}

/// Paints a [Glyph] in a 24 x 24 design grid scaled to the given size.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A layer, so that details can be cut out of the shape whatever is behind.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final cut = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    final cutLine = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (glyph) {
      case Glyph.rupee:
        // A tall six-sided gem with a facet in the middle.
        const outer = [
          Offset(12, 1.5),
          Offset(18.5, 7),
          Offset(18.5, 17),
          Offset(12, 22.5),
          Offset(5.5, 17),
          Offset(5.5, 7),
        ];
        const inner = [
          Offset(12, 6),
          Offset(15, 8.6),
          Offset(15, 15.4),
          Offset(12, 18),
          Offset(9, 15.4),
          Offset(9, 8.6),
        ];
        canvas.drawPath(Path()..addPolygon(outer, true), fill);
        canvas.drawPath(Path()..addPolygon(inner, true), cutLine);
        for (var i = 0; i < 6; i++) {
          canvas.drawLine(outer[i], inner[i], cutLine);
        }
      case Glyph.skull:
        // Cranium and jaw, with eye sockets, nose and teeth cut out.
        final head = Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 10), radius: 8.5))
          ..addRRect(RRect.fromLTRBR(7.5, 14, 16.5, 21.5, const Radius.circular(2)));
        canvas.drawPath(head, fill);
        canvas.drawOval(Rect.fromCenter(center: const Offset(8.6, 10.4), width: 4.6, height: 5), cut);
        canvas.drawOval(Rect.fromCenter(center: const Offset(15.4, 10.4), width: 4.6, height: 5), cut);
        canvas.drawPath(
          Path()
            ..moveTo(12, 13.2)
            ..lineTo(13.2, 15.6)
            ..lineTo(10.8, 15.6)
            ..close(),
          cut,
        );
        canvas.drawLine(const Offset(10.5, 18.6), const Offset(10.5, 21.6), cutLine);
        canvas.drawLine(const Offset(13.5, 18.6), const Offset(13.5, 21.6), cutLine);
      case Glyph.bottle:
        // Cork, neck and a round-shouldered body with a highlight.
        canvas.drawRRect(RRect.fromLTRBR(9.6, 1.5, 14.4, 4.4, const Radius.circular(1)), fill);
        final body = Path()
          ..moveTo(10.2, 5.4)
          ..lineTo(13.8, 5.4)
          ..lineTo(13.8, 8.2)
          ..cubicTo(17.6, 9.4, 18.8, 12, 18.8, 15.4)
          ..cubicTo(18.8, 19.8, 16.4, 22.5, 12, 22.5)
          ..cubicTo(7.6, 22.5, 5.2, 19.8, 5.2, 15.4)
          ..cubicTo(5.2, 12, 6.4, 9.4, 10.2, 8.2)
          ..close();
        canvas.drawPath(body, fill);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 15.6), radius: 4.2),
          math.pi * 0.95,
          math.pi * 0.5,
          false,
          cutLine,
        );
      case Glyph.medallion:
        // A disc with an inner ring and a boss in the centre.
        canvas.drawCircle(const Offset(12, 12), 10.2, fill);
        canvas.drawCircle(const Offset(12, 12), 6.6, cutLine);
        canvas.drawCircle(const Offset(12, 12), 2.6, cut);
        canvas.drawCircle(const Offset(12, 12), 1.2, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

const Map<String, IconData> _areaIcons = {
  'kokiri_forest': Icons.park,
  'hyrule_field': Icons.grass,
  'castle_town': Icons.storefront,
  'hyrule_castle': Icons.castle,
  'lon_lon_ranch': Icons.cottage,
  'kakariko_village': Icons.holiday_village,
  'graveyard': Icons.church,
  'death_mountain_trail': Icons.terrain,
  'goron_city': Icons.landscape,
  'lost_woods': Icons.forest,
  'death_mountain_crater': Icons.volcano,
  'zoras_river': Icons.waves,
  'zoras_domain': Icons.water_drop,
  'lake_hylia': Icons.water,
  'gerudo_valley': Icons.filter_hdr,
  'gerudo_fortress': Icons.fort,
  'desert_colossus': Icons.wb_sunny,
};

/// A picture for an area: what kind of place it is. Dungeons share one.
IconData areaIcon(AreaState area) =>
    area.kind == 'dungeon' ? Icons.account_balance : (_areaIcons[area.id] ?? Icons.place);
