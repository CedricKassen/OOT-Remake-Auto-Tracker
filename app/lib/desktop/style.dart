import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:oot_ui/oot_ui.dart';

import '../icons.dart';

export 'package:oot_ui/oot_ui.dart' show DesktopLook;

/// The interface icons, from the icon set of each system.
class DesktopIcons {
  const DesktopIcons({
    required this.overview,
    required this.map,
    required this.settings,
    required this.settingsActive,
    required this.filter,
    required this.filterActive,
    required this.chevron,
    required this.searching,
    required this.connecting,
    required this.offline,
    required this.heart,
    required this.person,
    required this.warning,
    required this.unknown,
    required this.done,
    required this.open,
    required this.here,
    required this.check,
  });

  final IconData overview, map, settings, settingsActive, filter, filterActive, chevron;
  final IconData searching, connecting, offline;
  final IconData heart, person, warning, unknown;

  /// A check the save has / does not have yet.
  final IconData done, open;

  /// Marks the area the player is in.
  final IconData here;
  final IconData check;

  static const mac = DesktopIcons(
    overview: CupertinoIcons.chart_pie,
    map: CupertinoIcons.map,
    settings: CupertinoIcons.gear,
    settingsActive: CupertinoIcons.gear_solid,
    filter: CupertinoIcons.line_horizontal_3_decrease_circle,
    filterActive: CupertinoIcons.line_horizontal_3_decrease_circle_fill,
    chevron: CupertinoIcons.chevron_right,
    searching: CupertinoIcons.wifi,
    connecting: CupertinoIcons.arrow_2_circlepath,
    offline: CupertinoIcons.wifi_slash,
    heart: CupertinoIcons.heart_fill,
    person: CupertinoIcons.person_fill,
    warning: CupertinoIcons.exclamationmark_triangle_fill,
    unknown: CupertinoIcons.question_circle,
    done: CupertinoIcons.checkmark_circle_fill,
    open: CupertinoIcons.circle,
    here: CupertinoIcons.location_fill,
    check: CupertinoIcons.checkmark,
  );

  static const windows = DesktopIcons(
    overview: FluentIcons.view_dashboard,
    map: FluentIcons.nav2_d_map_view,
    settings: FluentIcons.settings,
    settingsActive: FluentIcons.settings,
    filter: FluentIcons.filter,
    filterActive: FluentIcons.filter_solid,
    chevron: FluentIcons.chevron_right,
    searching: FluentIcons.wifi,
    connecting: FluentIcons.sync,
    offline: FluentIcons.plug_disconnected,
    heart: FluentIcons.heart_fill,
    person: FluentIcons.contact,
    warning: FluentIcons.warning,
    unknown: FluentIcons.unknown,
    done: FluentIcons.completed_solid,
    open: FluentIcons.circle_ring,
    here: FluentIcons.location_fill,
    check: FluentIcons.check_mark,
  );

  static const linux = DesktopIcons(
    overview: Icons.pie_chart_outline,
    map: Icons.map_outlined,
    settings: Icons.settings_outlined,
    settingsActive: Icons.settings,
    filter: Icons.filter_list,
    filterActive: Icons.filter_list,
    chevron: Icons.chevron_right,
    searching: Icons.wifi_find,
    connecting: Icons.sync,
    offline: Icons.cloud_off,
    heart: Icons.favorite,
    person: Icons.person,
    warning: Icons.warning_rounded,
    unknown: Icons.help_outline,
    done: Icons.check_circle,
    open: Icons.radio_button_unchecked,
    here: Icons.near_me,
    check: Icons.check,
  );
}

/// Colours, text styles and measures of the desktop interface in the look of
/// one system, for light and dark mode.
class DesktopStyle {
  const DesktopStyle({required this.look, required this.dark, required this.accent});

  /// The style of the window [context] is in; a [DesktopTheme] provides it.
  static DesktopStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DesktopTheme>()!.style;

  final DesktopLook look;
  final bool dark;
  final Color accent;

  T _pick<T>(T mac, T windows, T linux) => switch (look) {
    DesktopLook.mac => mac,
    DesktopLook.windows => windows,
    DesktopLook.linux => linux,
  };

  DesktopIcons get icons => _pick(DesktopIcons.mac, DesktopIcons.windows, DesktopIcons.linux);

  /// "Mac" on a Mac, "computer" elsewhere.
  String get computer => look == DesktopLook.mac ? 'Mac' : 'computer';

  Color get _ink => dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get label => _ink.withValues(alpha: dark ? _pick(0.85, 1.0, 1.0) : _pick(0.85, 0.9, 0.8));
  Color get secondary => _ink.withValues(alpha: dark ? _pick(0.55, 0.77, 0.55) : _pick(0.55, 0.62, 0.45));
  Color get tertiary => _ink.withValues(alpha: _pick(0.3, 0.4, 0.35));
  Color get hairline => _ink.withValues(alpha: dark ? _pick(0.12, 0.09, 0.1) : _pick(0.1, 0.07, 0.08));
  Color get groupFill => _pick(
    _ink.withValues(alpha: dark ? 0.05 : 0.035),
    dark ? const Color(0x0DFFFFFF) : const Color(0xB3FFFFFF),
    Adwaita(dark).card,
  );
  Color get track => _ink.withValues(alpha: 0.1);
  Color get hover => _ink.withValues(alpha: _pick(0.06, 0.04, 0.06));

  double get groupRadius => _pick(8, 4, 12);
  double get hairlineWidth => _pick(0.5, 1, 1);

  /// How far the lines between the rows of a group are indented.
  double get hairlineInset => _pick(12, 0, 0);

  /// The space inside a row of a group.
  EdgeInsets get rowPadding => _pick(
    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  /// A group's outline and fill.
  BoxDecoration get groupDecoration => look == DesktopLook.linux
      ? adwaitaCard(Adwaita(dark))
      : BoxDecoration(
          color: groupFill,
          borderRadius: BorderRadius.circular(groupRadius),
          border: Border.all(color: hairline, width: hairlineWidth),
        );

  String get fontFamily => _pick('.AppleSystemUIFont', 'Segoe UI Variable Text', adwaitaFont);

  TextStyle _text(double size, FontWeight weight, Color color) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: _pick(null, const ['Segoe UI'], adwaitaFontFallback),
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.25,
    letterSpacing: 0,
    decoration: TextDecoration.none,
  );

  /// The size of body text; the other sizes follow each system's type scale.
  double get _body => _pick(13, 14, 15);
  double get _small => _pick(11, 12, 12);
  FontWeight get _strong => _pick(FontWeight.w600, FontWeight.w600, FontWeight.w700);

  TextStyle get largeTitle => _text(_pick(26, 28, 28), _pick(FontWeight.w700, FontWeight.w600, FontWeight.w800), label);
  TextStyle get title => _text(_pick(17, 20, 20), _pick(FontWeight.w600, FontWeight.w600, FontWeight.w800), label);
  TextStyle get headline => _text(_body, _strong, label);
  TextStyle get body => _text(_body, FontWeight.w400, label);
  TextStyle get bodySecondary => _text(_body, FontWeight.w400, secondary);
  TextStyle get caption => _text(_small, FontWeight.w400, secondary);
  TextStyle get sectionHeader => _text(_small, _strong, secondary);
  TextStyle get number =>
      _text(_body, FontWeight.w500, label).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  bool operator ==(Object other) =>
      other is DesktopStyle && other.look == look && other.dark == dark && other.accent == accent;

  @override
  int get hashCode => Object.hash(look, dark, accent);
}

/// Hands the [DesktopStyle] of a window to the widgets in it.
class DesktopTheme extends InheritedWidget {
  const DesktopTheme({super.key, required this.style, required super.child});
  final DesktopStyle style;

  @override
  bool updateShouldNotify(DesktopTheme old) => old.style != style;
}

/// A rounded box that groups rows, as in the settings of each system.
class GroupBox extends StatelessWidget {
  const GroupBox({super.key, required this.children, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    return Container(
      padding: padding,
      decoration: style.groupDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: style.hairlineWidth,
                margin: EdgeInsets.only(left: style.hairlineInset),
                color: style.hairline,
              ),
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
    // A Mac marks the selected row with the accent colour, GNOME with a
    // quiet fill that leaves the text as it is.
    final mac = style.look == DesktopLook.mac;
    final onSelected = mac ? const Color(0xFFFFFFFF) : style.label;
    final ink = selected ? onSelected : (widget.complete ? style.secondary : style.label);
    final iconInk = mac ? style.accent : ink;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: mac ? 28 : 34,
          margin: EdgeInsets.symmetric(vertical: mac ? 0.5 : 1),
          padding: EdgeInsets.symmetric(horizontal: mac ? 8 : 10),
          decoration: BoxDecoration(
            color: selected ? (mac ? style.accent : style.track) : (_hover ? style.hover : null),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              AppIcon(widget.icon, size: mac ? 15 : 16, color: selected ? onSelected : iconInk),
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
                  child: Icon(style.icons.here, size: mac ? 11 : 13, color: selected ? onSelected : style.accent),
                ),
              if (widget.complete)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    style.icons.check,
                    size: mac ? 12 : 14,
                    color: selected && mac ? onSelected : style.tertiary,
                  ),
                )
              else if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    widget.trailing!,
                    style: style.number.copyWith(color: selected && mac ? onSelected : style.secondary, fontSize: 12),
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
