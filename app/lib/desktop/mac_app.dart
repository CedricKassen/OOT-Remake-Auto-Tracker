import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../client.dart';
import '../widgets.dart';
import 'shell.dart';
import 'style.dart';

/// The macOS app: a sidebar with every area, a toolbar and one content pane.
class MacApp extends StatelessWidget {
  const MacApp({super.key, required this.client});
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

class _WindowState extends DesktopShellState<_Window> {
  @override
  Widget build(BuildContext context) {
    resolve(context);
    final style = DesktopStyle(
      look: DesktopLook.mac,
      dark: MacosTheme.brightnessOf(context) == Brightness.dark,
      accent: MacosTheme.of(context).primaryColor,
    );
    final (statusColor, statusText) = status;

    return DesktopTheme(
      style: style,
      child: MacosWindow(
        sidebar: Sidebar(
          minWidth: 230,
          startWidth: 250,
          maxWidth: 340,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: [
              for (final e in entries(style.icons))
                if (e.isHeader)
                  SidebarHeader(e.label)
                else
                  SidebarRow(
                    icon: e.icon!,
                    label: e.label,
                    selected: selected == e.id,
                    here: e.here,
                    trailing: e.missing?.toString(),
                    complete: e.complete,
                    onTap: () => select(e.id!),
                  ),
            ],
          ),
        ),
        child: MacosScaffold(
          toolBar: ToolBar(
            title: Text(title),
            titleWidth: 320,
            actions: [
              if (canShowMap)
                ToolBarIconButton(
                  label: 'Map',
                  tooltipMessage: 'Show this area on the map',
                  icon: MacosIcon(style.icons.map),
                  showLabel: false,
                  onPressed: showOnMap,
                ),
              if (canFilter)
                ToolBarIconButton(
                  label: 'Missing only',
                  tooltipMessage: missingOnly ? 'Showing missing entries only' : 'Show missing entries only',
                  icon: MacosIcon(missingOnly ? style.icons.filterActive : style.icons.filter),
                  showLabel: false,
                  onPressed: toggleMissingOnly,
                ),
              CustomToolbarItem(
                tooltipMessage: statusDetail,
                inToolbarBuilder: (context) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: StatusBadge(color: statusColor, text: statusText),
                ),
              ),
              ToolBarIconButton(
                label: 'Settings',
                tooltipMessage: 'Settings',
                icon: MacosIcon(selected == 'settings' ? style.icons.settingsActive : style.icons.settings),
                showLabel: false,
                onPressed: () => select('settings'),
              ),
            ],
          ),
          children: [
            ContentArea(builder: (context, scrollController) => content(style, material: sharedWidgetTheme(style))),
          ],
        ),
      ),
    );
  }
}
