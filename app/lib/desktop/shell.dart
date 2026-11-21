import 'package:flutter/material.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../client.dart';
import '../screens/map.dart';
import '../widgets.dart';
import 'panes.dart';
import 'style.dart';

/// One line of the sidebar: a destination, or a heading above a few of them.
class NavEntry {
  const NavEntry(
    String this.id, {
    required Object this.icon,
    required this.label,
    this.missing,
    this.complete = false,
    this.here = false,
  });
  const NavEntry.header(this.label) : id = null, icon = null, missing = null, complete = false, here = false;

  /// What [DesktopShellState.select] takes; null for a heading.
  final String? id;

  /// An [IconData] or a [Glyph].
  final Object? icon;
  final String label;

  /// How many are still missing there, if any.
  final int? missing;

  /// Nothing left to collect.
  final bool complete;

  /// The player is here right now.
  final bool here;

  bool get isHeader => id == null;
}

/// What the desktop windows of all systems share: what is selected, the
/// sidebar's entries and the pane that goes with the selection. Each system's
/// window draws its own chrome around these.
abstract class DesktopShellState<T extends StatefulWidget> extends State<T> {
  /// `overview`, `map`, `settings`, `cat:<category>`, or an area id.
  String selected = 'overview';
  bool missingOnly = false;

  /// The area the map pane opens on; null for the world.
  String? _mapArea;

  late TrackerClient client;
  TrackerState? state;

  /// The selected area or category, if the selection is one.
  AreaState? area;
  String? category;

  void select(String id) => setState(() {
    selected = id;
    if (id == 'map') _mapArea = null;
  });

  void toggleMissingOnly() => setState(() => missingOnly = !missingOnly);

  /// Opens the map on the selected area.
  void showOnMap() => setState(() {
    _mapArea = area?.id;
    selected = 'map';
  });

  /// Reads the client and works out what the selection refers to. Call first
  /// in `build`.
  void resolve(BuildContext context) {
    client = ClientScope.of(context);
    state = client.state;
    area = state?.areas.where((a) => a.id == selected).firstOrNull;
    category = selected.startsWith('cat:') ? selected.substring(4) : null;
    if (area == null && category == null && !const ['overview', 'map', 'settings'].contains(selected)) {
      selected = 'overview';
    }
  }

  String get title => switch (selected) {
    'overview' => 'Overview',
    'map' => 'Map',
    'settings' => 'Settings',
    _ when category != null => categoryName(category!),
    _ => area?.name ?? '',
  };

  /// The connection to the server, as a colour and a few words.
  (Color, String) get status => switch (client.status) {
    LinkStatus.live => (const Color(0xFF34C759), 'Live'),
    LinkStatus.connecting => (const Color(0xFFFF9F0A), 'Connecting…'),
    LinkStatus.searching => (const Color(0xFFFF9F0A), 'Looking for server…'),
    LinkStatus.offline => (const Color(0xFFFF453A), client.state == null ? 'Offline' : 'Offline · last known state'),
  };

  String get statusDetail =>
      client.status == LinkStatus.live ? 'Connected to ${client.targetLabel}' : (client.lastError ?? status.$2);

  /// Whether the selected area has a map to jump to.
  bool get canShowMap => area != null && client.maps?.ofArea(area!.id).isNotEmpty == true;

  /// Whether "missing only" applies to what is shown.
  bool get canFilter => (area != null || category != null) && !client.spoilerFree;

  /// The sidebar from top to bottom. Settings is not in it; every system has
  /// its own place for that.
  List<NavEntry> entries(DesktopIcons icons) {
    final state = this.state;
    final here = state?.save?.area;
    final areas = [
      for (final a in state?.areas ?? const <AreaState>[])
        if (a.progress.total > 0) a,
    ];
    NavEntry areaEntry(AreaState a) => NavEntry(
      a.id,
      icon: areaIcon(a),
      label: a.name,
      missing: a.progress.missing == 0 ? null : a.progress.missing,
      complete: a.progress.missing == 0,
      here: a.id == here,
    );
    return [
      NavEntry('overview', icon: icons.overview, label: 'Overview'),
      NavEntry('map', icon: icons.map, label: 'Map'),
      if (state != null && state.byCategory.isNotEmpty) const NavEntry.header('Categories'),
      for (final e in state?.byCategory.entries ?? const <MapEntry<String, Progress>>[])
        NavEntry(
          'cat:${e.key}',
          icon: CategoryStyle.of(e.key).icon,
          label: categoryName(e.key),
          missing: e.value.missing == 0 ? null : e.value.missing,
          complete: e.value.missing == 0,
        ),
      if (areas.any((a) => a.kind != 'dungeon')) const NavEntry.header('Hyrule'),
      for (final a in areas)
        if (a.kind != 'dungeon') areaEntry(a),
      if (areas.any((a) => a.kind == 'dungeon')) const NavEntry.header('Dungeons'),
      for (final a in areas)
        if (a.kind == 'dungeon') areaEntry(a),
    ];
  }

  /// The pane for the selection, in [style]. The widgets shared with the
  /// phone interface (progress rings, the map) read Material colours; they
  /// get [material], or the theme around this window when that is null.
  Widget content(DesktopStyle style, {ThemeData? material}) {
    final state = this.state;
    final category = this.category;
    final Widget pane = switch (selected) {
      'settings' => const SettingsPane(),
      _ when state == null => const DesktopEmptyState(),
      'overview' => OverviewPane(state: state, onOpenArea: select),
      'map' => MapScreen(key: ValueKey('map-$_mapArea'), initialArea: _mapArea, onOpenArea: select),
      _ when category != null => CategoryPane(
        key: ValueKey(selected),
        state: state,
        category: category,
        missingOnly: missingOnly,
        onOpenArea: select,
      ),
      _ => AreaPane(key: ValueKey(selected), state: state, area: area!, missingOnly: missingOnly),
    };
    final child = DesktopTheme(
      style: style,
      child: Material(type: MaterialType.transparency, child: pane),
    );
    return material == null ? child : Theme(data: material, child: child);
  }
}

/// The Material theme for the shared widgets on systems whose window is not
/// a Material one.
ThemeData sharedWidgetTheme(DesktopStyle style) {
  final brightness = style.dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E8E5A), brightness: brightness),
    fontFamily: style.fontFamily,
  );
}

/// The connection status as a coloured dot and a few words.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: DesktopStyle.of(context).caption),
    ],
  );
}
