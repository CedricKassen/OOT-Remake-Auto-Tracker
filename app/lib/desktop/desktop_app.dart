import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ColorScheme, Material, MaterialType, Theme, ThemeData;
import 'package:macos_ui/macos_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../client.dart';
import '../screens/map.dart';
import '../widgets.dart';
import 'panes.dart';
import 'style.dart';

/// The macOS app: a sidebar with every area, a toolbar and one content pane.
class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key, required this.client});
  final TrackerClient client;

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: MacosApp(
        title: 'OoT Tracker',
        debugShowCheckedModeBanner: false,
        theme: MacosThemeData.light(),
        darkTheme: MacosThemeData.dark(),
        home: const _Window(),
      ),
    );
  }
}

class _Window extends StatefulWidget {
  const _Window();

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> {
  /// `overview`, `map`, `settings`, `cat:<category>`, or an area id.
  String _selected = 'overview';
  bool _missingOnly = false;

  /// The area the map pane opens on; null for the world.
  String? _mapArea;

  void _select(String id) => setState(() {
    _selected = id;
    if (id == 'map') _mapArea = null;
  });

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final brightness = MacosTheme.brightnessOf(context);
    final area = state?.areas.where((a) => a.id == _selected).firstOrNull;
    final category = _selected.startsWith('cat:') ? _selected.substring(4) : null;
    if (area == null && category == null && !const ['overview', 'map', 'settings'].contains(_selected)) {
      _selected = 'overview';
    }
    final (statusColor, statusText) = switch (client.status) {
      LinkStatus.live => (const Color(0xFF34C759), 'Live'),
      LinkStatus.connecting => (const Color(0xFFFF9F0A), 'Connecting…'),
      LinkStatus.searching => (const Color(0xFFFF9F0A), 'Looking for server…'),
      LinkStatus.offline => (const Color(0xFFFF453A), client.state == null ? 'Offline' : 'Offline · last known state'),
    };

    final title = switch (_selected) {
      'overview' => 'Overview',
      'map' => 'Map',
      'settings' => 'Settings',
      _ when category != null => categoryName(category),
      _ => area?.name ?? '',
    };

    final Widget pane = switch (_selected) {
      'settings' => const SettingsPane(),
      _ when state == null => const DesktopEmptyState(),
      'overview' => OverviewPane(state: state, onOpenArea: _select),
      'map' => MapScreen(key: ValueKey('map-$_mapArea'), initialArea: _mapArea, onOpenArea: _select),
      _ when category != null => CategoryPane(
        key: ValueKey(_selected),
        state: state,
        category: category,
        missingOnly: _missingOnly,
        onOpenArea: _select,
      ),
      _ => AreaPane(key: ValueKey(_selected), state: state, area: area!, missingOnly: _missingOnly),
    };

    return MacosWindow(
      sidebar: Sidebar(
        minWidth: 230,
        startWidth: 250,
        maxWidth: 340,
        builder: (context, scrollController) =>
            _SidebarList(controller: scrollController, selected: _selected, onSelect: _select),
      ),
      child: MacosScaffold(
        toolBar: ToolBar(
          title: Text(title),
          titleWidth: 320,
          actions: [
            if (area != null && client.maps?.ofArea(area.id).isNotEmpty == true)
              ToolBarIconButton(
                label: 'Map',
                tooltipMessage: 'Show this area on the map',
                icon: const MacosIcon(CupertinoIcons.map),
                showLabel: false,
                onPressed: () => setState(() {
                  _mapArea = area.id;
                  _selected = 'map';
                }),
              ),
            if ((area != null || category != null) && !client.spoilerFree)
              ToolBarIconButton(
                label: 'Missing only',
                tooltipMessage: _missingOnly ? 'Showing missing entries only' : 'Show missing entries only',
                icon: MacosIcon(
                  _missingOnly
                      ? CupertinoIcons.line_horizontal_3_decrease_circle_fill
                      : CupertinoIcons.line_horizontal_3_decrease_circle,
                ),
                showLabel: false,
                onPressed: () => setState(() => _missingOnly = !_missingOnly),
              ),
            CustomToolbarItem(
              tooltipMessage: client.status == LinkStatus.live
                  ? 'Connected to ${client.targetLabel}'
                  : (client.lastError ?? statusText),
              inToolbarBuilder: (context) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(statusText, style: DesktopStyle.of(context).caption),
                  ],
                ),
              ),
            ),
            ToolBarIconButton(
              label: 'Settings',
              tooltipMessage: 'Settings',
              icon: MacosIcon(_selected == 'settings' ? CupertinoIcons.gear_solid : CupertinoIcons.gear),
              showLabel: false,
              onPressed: () => _select('settings'),
            ),
          ],
        ),
        children: [
          ContentArea(
            builder: (context, scrollController) => Theme(
              // Shared widgets (progress rings, the map) read Material colours.
              data: ThemeData(
                brightness: brightness,
                colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E8E5A), brightness: brightness),
                fontFamily: '.AppleSystemUIFont',
              ),
              child: Material(type: MaterialType.transparency, child: pane),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarList extends StatelessWidget {
  const _SidebarList({required this.controller, required this.selected, required this.onSelect});
  final ScrollController controller;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final state = ClientScope.of(context).state;
    final here = state?.save?.area;
    final areas = [
      for (final a in state?.areas ?? const <AreaState>[])
        if (a.progress.total > 0) a,
    ];

    Widget areaRow(AreaState a) => SidebarRow(
      icon: areaIcon(a),
      label: a.name,
      selected: selected == a.id,
      here: a.id == here,
      trailing: a.progress.missing == 0 ? null : '${a.progress.missing}',
      complete: a.progress.missing == 0,
      onTap: () => onSelect(a.id),
    );

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      children: [
        SidebarRow(
          icon: CupertinoIcons.chart_pie,
          label: 'Overview',
          selected: selected == 'overview',
          onTap: () => onSelect('overview'),
        ),
        SidebarRow(icon: CupertinoIcons.map, label: 'Map', selected: selected == 'map', onTap: () => onSelect('map')),
        if (state != null && state.byCategory.isNotEmpty) const SidebarHeader('Categories'),
        for (final e in state?.byCategory.entries ?? const <MapEntry<String, Progress>>[])
          SidebarRow(
            icon: CategoryStyle.of(e.key).icon,
            label: categoryName(e.key),
            selected: selected == 'cat:${e.key}',
            trailing: e.value.missing == 0 ? null : '${e.value.missing}',
            complete: e.value.missing == 0,
            onTap: () => onSelect('cat:${e.key}'),
          ),
        if (areas.any((a) => a.kind != 'dungeon')) const SidebarHeader('Hyrule'),
        for (final a in areas)
          if (a.kind != 'dungeon') areaRow(a),
        if (areas.any((a) => a.kind == 'dungeon')) const SidebarHeader('Dungeons'),
        for (final a in areas)
          if (a.kind == 'dungeon') areaRow(a),
      ],
    );
  }
}
