import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import 'client.dart';
import 'icons.dart';

export 'icons.dart';

/// Makes the [TrackerClient] available to the widget tree and rebuilds
/// dependents when it changes.
class ClientScope extends InheritedNotifier<TrackerClient> {
  const ClientScope({super.key, required TrackerClient client, required super.child}) : super(notifier: client);

  static TrackerClient of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ClientScope>()!.notifier!;
}

const gold = Color(0xFFE2B33C);

class CategoryStyle {
  const CategoryStyle(this.icon, this.color);

  /// An [IconData] or a [Glyph]; show it with [AppIcon].
  final Object icon;
  final Color color;

  static const _styles = {
    'skulltula': CategoryStyle(Glyph.skull, gold),
    'heart_piece': CategoryStyle(Icons.favorite, Color(0xFFE5645E)),
    'reward': CategoryStyle(Glyph.medallion, Color(0xFF63C7B2)),
    'song': CategoryStyle(Icons.music_note, Color(0xFF8FB8F0)),
    'item': CategoryStyle(Icons.backpack, Color(0xFFD9A066)),
    'equipment': CategoryStyle(Icons.shield, Color(0xFFA9B4C2)),
    'upgrade': CategoryStyle(Icons.keyboard_double_arrow_up, Color(0xFF9CCC65)),
    'mask': CategoryStyle(Icons.theater_comedy, Color(0xFFC79BE0)),
    'bottle': CategoryStyle(Glyph.bottle, Color(0xFF6FD0E8)),
    'big_poe': CategoryStyle(Glyph.ghost, Color(0xFFB39DDB)),
  };

  static CategoryStyle of(String category) => _styles[category] ?? const CategoryStyle(Icons.check_circle, Colors.grey);
}

String categoryName(String category) => categoryNames[category] ?? category;

/// A circular progress ring with content in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.size,
    this.stroke = 6,
    this.color,
    this.track,
    this.child,
  });

  final Progress progress;
  final double size;
  final double stroke;
  final Color? color;

  /// Colour of the unfilled part; the theme's by default.
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress.fraction,
          color ?? (progress.missing == 0 ? gold : scheme.primary),
          track ?? scheme.surfaceContainerHighest,
          stroke,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color, this.track, this.stroke);
  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}

/// Icon plus `done/total` for one category; dimmed when complete.
class CategoryCount extends StatelessWidget {
  const CategoryCount({super.key, required this.category, required this.progress});
  final String category;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    final complete = progress.missing == 0;
    final text = Theme.of(context).textTheme.labelLarge!;
    return Tooltip(
      message: '${categoryName(category)}: ${progress.missing} missing',
      child: Opacity(
        opacity: complete ? 0.45 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(complete ? Icons.check : style.icon, size: 16, color: style.color),
            const SizedBox(width: 4),
            Text('${progress.done}/${progress.total}', style: text),
          ],
        ),
      ),
    );
  }
}

String percent(Progress p) => '${(p.fraction * 100).floor()}%';

/// Shown instead of content while there is no state at all.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final (icon, title, detail) = switch (client.status) {
      LinkStatus.searching => (
        Icons.wifi_find,
        'Looking for the tracker server…',
        'Start ootd on your Mac. Both devices need to be on the same Wi-Fi.',
      ),
      LinkStatus.connecting => (Icons.sync, 'Connecting…', client.targetLabel),
      _ => (Icons.cloud_off, 'Not connected', client.lastError ?? 'Set the server address in Settings.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
