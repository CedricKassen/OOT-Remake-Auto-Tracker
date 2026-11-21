import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show AdaptiveAppBar, AdaptiveScaffold, AdaptiveSegmentedControl, AdaptiveSwitch;
import 'package:cupertino_ui/cupertino_ui.dart';

import '../icons.dart';

/// Colours and text styles of the iOS interface, resolved for light or dark
/// mode from the system colours.
class IosStyle {
  IosStyle.of(BuildContext context)
    : label = CupertinoColors.label.resolveFrom(context),
      secondary = CupertinoColors.secondaryLabel.resolveFrom(context),
      tertiary = CupertinoColors.tertiaryLabel.resolveFrom(context),
      fill = CupertinoColors.systemFill.resolveFrom(context),
      card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
      background = CupertinoColors.systemGroupedBackground.resolveFrom(context),
      accent = CupertinoTheme.of(context).primaryColor,
      _text = CupertinoTheme.of(context).textTheme.textStyle;

  final Color label, secondary, tertiary, fill, card, background, accent;
  final TextStyle _text;

  static const orange = CupertinoColors.systemOrange;

  TextStyle _style(double size, FontWeight weight, Color color) =>
      _text.copyWith(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.2, height: 1.25);

  // Apple's type scale.
  TextStyle get title => _style(22, FontWeight.w700, label);
  TextStyle get headline => _style(17, FontWeight.w600, label);
  TextStyle get body => _style(17, FontWeight.w400, label);
  TextStyle get subhead => _style(15, FontWeight.w400, secondary);
  TextStyle get footnote => _style(13, FontWeight.w400, secondary);
  TextStyle get number => body.copyWith(color: secondary, fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Extra space left and right of the content on wide screens (iPad), so that
/// lists keep a comfortable width.
double iosGutter(BuildContext context) => math.max(0, (MediaQuery.sizeOf(context).width - 760) / 2);

/// Whether the system's own bars and controls can be shown: on an iPhone or
/// iPad. Tests run on the build machine, where the Cupertino widgets that
/// the same controls are on iOS 18 and earlier stand in for them.
final bool iosSystemControls = Platform.isIOS;

/// A page of the iOS app: the system's toolbar with the title, and the back
/// button on pages opened from another, over the grouped background. From
/// iOS 26 on the toolbar is the system's Liquid Glass one.
class IosPage extends StatelessWidget {
  const IosPage({super.key, required this.title, this.subtitle, this.children, this.filling});
  final String title;

  /// Shown small below the title in the bar.
  final Widget? subtitle;

  /// The content, scrolled under the bar.
  final List<Widget>? children;

  /// Shown centred in the space below the bar instead of [children].
  final Widget? filling;

  @override
  Widget build(BuildContext context) {
    final gutter = iosGutter(context);
    final style = IosStyle.of(context);
    final heading = subtitle == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: style.headline),
              subtitle!,
            ],
          );
    final body = CustomScrollView(
      slivers: [
        if (filling != null)
          SliverFillRemaining(hasScrollBody: false, child: SafeArea(child: filling!))
        else
          SliverSafeArea(
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
              sliver: SliverList.list(children: children ?? const []),
            ),
          ),
      ],
    );
    if (!iosSystemControls) {
      return CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(middle: heading ?? Text(title)),
        child: body,
      );
    }
    return AdaptiveScaffold(
      backgroundColor: style.background,
      appBar: AdaptiveAppBar(title: title, titleWidget: heading),
      body: body,
    );
  }
}

/// A list section holding one piece of content that is not a list.
class IosCard extends StatelessWidget {
  const IosCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CupertinoListSection.insetGrouped(
    topMargin: 0,
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    children: [Padding(padding: padding, child: child)],
  );
}

/// Padding of a [CupertinoListTile] whose content is taller than one line.
const iosTilePadding = EdgeInsetsDirectional.fromSTEB(20, 11, 14, 11);

/// Content of a [CupertinoListTile] that may run over several lines; a tile
/// cuts the texts of its title to one line otherwise.
class IosTileBody extends StatelessWidget {
  const IosTileBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(style: DefaultTextStyle.of(context).style, child: child);
}

/// The heading of a list section: an optional icon, a title, a count.
class IosSectionHeader extends StatelessWidget {
  const IosSectionHeader(this.title, {super.key, this.icon, this.iconColor, this.trailing});
  final String title;
  final Object? icon;
  final Color? iconColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    return Row(
      children: [
        if (icon != null) ...[AppIcon(icon!, size: 18, color: iconColor ?? style.secondary), const SizedBox(width: 8)],
        Expanded(child: Text(title, style: style.headline)),
        if (trailing != null) Text(trailing!, style: style.number),
      ],
    );
  }
}

/// Two or three choices next to each other, one of them selected.
class IosSegments<T extends Object> extends StatelessWidget {
  const IosSegments({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SizedBox(
        width: double.infinity,
        child: iosSystemControls
            ? AdaptiveSegmentedControl(
                labels: options.values.toList(),
                selectedIndex: keys.indexOf(value),
                onValueChanged: (i) => onChanged(keys[i]),
              )
            : CupertinoSlidingSegmentedControl<T>(
                groupValue: value,
                onValueChanged: (v) => onChanged(v ?? value),
                children: {
                  for (final e in options.entries)
                    e.key: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(e.value, style: const TextStyle(fontSize: 14)),
                    ),
                },
              ),
      ),
    );
  }
}

/// An on/off switch.
class IosSwitch extends StatelessWidget {
  const IosSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => iosSystemControls
      ? AdaptiveSwitch(value: value, onChanged: onChanged)
      : CupertinoSwitch(value: value, onChanged: onChanged);
}
