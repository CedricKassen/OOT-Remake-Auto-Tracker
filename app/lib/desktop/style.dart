import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../icons.dart';

/// Colours and text styles of the macOS interface, for light and dark mode.
class DesktopStyle {
  DesktopStyle._(this.dark, this.accent);

  factory DesktopStyle.of(BuildContext context) =>
      DesktopStyle._(MacosTheme.brightnessOf(context) == Brightness.dark, MacosTheme.of(context).primaryColor);

  final bool dark;
  final Color accent;

  Color get _ink => dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get label => _ink.withValues(alpha: 0.85);
  Color get secondary => _ink.withValues(alpha: 0.55);
  Color get tertiary => _ink.withValues(alpha: 0.3);
  Color get hairline => _ink.withValues(alpha: dark ? 0.12 : 0.1);
  Color get groupFill => _ink.withValues(alpha: dark ? 0.05 : 0.035);
  Color get track => _ink.withValues(alpha: 0.1);
  Color get hover => _ink.withValues(alpha: 0.06);

  TextStyle _text(double size, FontWeight weight, Color color) =>
      TextStyle(fontFamily: '.AppleSystemUIFont', fontSize: size, fontWeight: weight, color: color, height: 1.25);

  TextStyle get largeTitle => _text(26, FontWeight.w700, label);
  TextStyle get title => _text(17, FontWeight.w600, label);
  TextStyle get headline => _text(13, FontWeight.w600, label);
  TextStyle get body => _text(13, FontWeight.w400, label);
  TextStyle get bodySecondary => _text(13, FontWeight.w400, secondary);
  TextStyle get caption => _text(11, FontWeight.w400, secondary);
  TextStyle get sectionHeader => _text(11, FontWeight.w600, secondary);
  TextStyle get number =>
      _text(13, FontWeight.w500, label).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// A rounded box that groups rows, as in macOS System Settings.
class GroupBox extends StatelessWidget {
  const GroupBox({super.key, required this.children, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: style.groupFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 0.5, margin: const EdgeInsets.only(left: 12), color: style.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A small heading above a [GroupBox].
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon, this.iconColor, this.trailing});
  final String title;
  final Object? icon;
  final Color? iconColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 15, color: iconColor), const SizedBox(width: 6)],
          Expanded(child: Text(title, style: style.headline)),
          if (trailing != null) Text(trailing!, style: style.number.copyWith(color: style.secondary)),
        ],
      ),
    );
  }
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
    child: Text(title, style: DesktopStyle.of(context).sectionHeader),
  );
}

/// One row of the source list in the sidebar.
class SidebarRow extends StatefulWidget {
  const SidebarRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.complete = false,
    this.here = false,
  });

  final Object icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown at the right edge, e.g. how many are missing.
  final String? trailing;

  /// Nothing left to collect: the row is dimmed and gets a check mark.
  final bool complete;

  /// The player is here right now.
  final bool here;

  @override
  State<SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<SidebarRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    final selected = widget.selected;
    const white = Color(0xFFFFFFFF);
    final ink = selected ? white : (widget.complete ? style.secondary : style.label);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(vertical: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? style.accent : (_hover ? style.hover : null),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              AppIcon(widget.icon, size: 15, color: selected ? white : style.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: style.body.copyWith(color: ink),
                ),
              ),
              if (widget.here)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(CupertinoIcons.location_fill, size: 11, color: selected ? white : style.accent),
                ),
              if (widget.complete)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(CupertinoIcons.checkmark, size: 12, color: selected ? white : style.tertiary),
                )
              else if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    widget.trailing!,
                    style: style.number.copyWith(color: selected ? white : style.secondary, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin horizontal progress bar.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: style.track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
