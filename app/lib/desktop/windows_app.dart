import 'package:fluent_ui/fluent_ui.dart';

import '../client.dart';
import '../widgets.dart';
import 'shell.dart';
import 'style.dart';

/// The Windows app in the Windows 11 look: a navigation pane with every
/// area, and a page with its commands in the header.
class WindowsApp extends StatelessWidget {
  const WindowsApp({super.key, required this.client});
  final TrackerClient client;

  FluentThemeData _theme(Brightness brightness) => FluentThemeData(
    brightness: brightness,
    accentColor: Colors.blue,
    // Windows 11's interface font; Windows 10 falls back to Segoe UI.
    fontFamily: 'Segoe UI Variable Text',
  );

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: FluentApp(
        title: 'OoT Tracker',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
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

class _WindowState extends DesktopShellState<_Window> {
  /// What a pane item shows at its right edge.
  Widget? _trailing(NavEntry e, DesktopStyle style) {
    if (!e.here && !e.complete && e.missing == null) return null;
    // Kept clear of the pane's scroll bar.
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (e.here) Icon(style.icons.here, size: 12, color: style.accent),
          if (e.here) const SizedBox(width: 8),
          if (e.complete)
            Icon(style.icons.check, size: 12, color: style.tertiary)
          else if (e.missing != null)
            Text('${e.missing}', style: style.caption),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    resolve(context);
    final theme = FluentTheme.of(context);
    final style = DesktopStyle(
      look: DesktopLook.windows,
      dark: theme.brightness == Brightness.dark,
      accent: theme.accentColor.defaultBrushFor(theme.brightness),
    );
    final (statusColor, statusText) = status;
    final nav = entries(style.icons);
    // Pane items are selected by their position among the items that can be.
    final ids = [
      for (final e in nav)
        if (!e.isHeader) e.id!,
      'settings',
    ];
    final index = ids.indexOf(selected);

    final commands = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: statusDetail,
          child: StatusBadge(color: statusColor, text: statusText),
        ),
        if (canShowMap) ...[
          const SizedBox(width: 12),
          Tooltip(
            message: 'Show this area on the map',
            child: IconButton(icon: Icon(style.icons.map, size: 16), onPressed: showOnMap),
          ),
        ],
        if (canFilter) ...[
          const SizedBox(width: 8),
          ToggleButton(
            checked: missingOnly,
            onChanged: (_) => toggleMissingOnly(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(missingOnly ? style.icons.filterActive : style.icons.filter, size: 14),
                const SizedBox(width: 8),
                const Text('Missing only'),
              ],
            ),
          ),
        ],
      ],
    );

    return DesktopTheme(
      style: style,
      child: NavigationView(
        pane: NavigationPane(
          selected: index < 0 ? null : index,
          onChanged: (i) => select(ids[i]),
          size: const NavigationPaneSize(openWidth: 290),
          items: [
            for (final e in nav)
              if (e.isHeader)
                PaneItemHeader(header: Text(e.label))
              else
                PaneItem(
                  key: ValueKey(e.id),
                  icon: AppIcon(e.icon!, size: 16),
                  title: Text(e.label),
                  trailing: _trailing(e, style),
                  body: const SizedBox.shrink(),
                ),
          ],
          footerItems: [
            PaneItem(
              key: const ValueKey('settings'),
              icon: Icon(style.icons.settings, size: 16),
              title: const Text('Settings'),
              body: const SizedBox.shrink(),
            ),
          ],
        ),
        paneBodyBuilder: (item, body) => ScaffoldPage(
          padding: const EdgeInsets.only(top: 20),
          header: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: PageHeader(title: Text(title), commandBar: commands),
          ),
          content: content(style, material: sharedWidgetTheme(style)),
        ),
      ),
    );
  }
}
