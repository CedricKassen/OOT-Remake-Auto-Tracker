import 'package:material_ui/material_ui.dart';
import 'package:oot_ui/oot_ui.dart';

import '../client.dart';
import '../widgets.dart';
import 'shell.dart';
import 'style.dart';

/// The Linux app in the GNOME look: a sidebar with every area, a flat bar
/// with the page's title and actions, and the content in boxed lists. The
/// window's own header bar comes from GTK (`linux/runner`).
class LinuxApp extends StatelessWidget {
  const LinuxApp({super.key, required this.client});
  final TrackerClient client;

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: MaterialApp(
        title: 'OoT Tracker',
        debugShowCheckedModeBanner: false,
        theme: adwaitaTheme(Brightness.light),
        darkTheme: adwaitaTheme(Brightness.dark),
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
    final a = Adwaita.of(context);
    final style = DesktopStyle(look: DesktopLook.linux, dark: a.dark, accent: a.accent);
    final (statusColor, statusText) = status;
    // A toggled button stays pressed in.
    final pressed = IconButton.styleFrom(backgroundColor: a.shade(0.15));

    final sidebar = Container(
      width: 270,
      decoration: BoxDecoration(
        color: a.sidebar,
        border: Border(right: BorderSide(color: a.shade(0.07))),
      ),
      child: ListView(
        padding: const EdgeInsets.all(6),
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
    );

    final bar = SizedBox(
      height: 47,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: NavigationToolbar(
          middle: Text(title, style: style.headline, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: statusDetail,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: StatusBadge(color: statusColor, text: statusText),
                ),
              ),
              if (canShowMap)
                IconButton(tooltip: 'Show this area on the map', icon: Icon(style.icons.map), onPressed: showOnMap),
              if (canFilter)
                IconButton(
                  tooltip: missingOnly ? 'Showing missing entries only' : 'Show missing entries only',
                  icon: Icon(style.icons.filter),
                  style: missingOnly ? pressed : null,
                  onPressed: toggleMissingOnly,
                ),
              IconButton(
                tooltip: 'Settings',
                icon: Icon(style.icons.settings),
                style: selected == 'settings' ? pressed : null,
                onPressed: () => select('settings'),
              ),
            ],
          ),
        ),
      ),
    );

    return DesktopTheme(
      style: style,
      child: Scaffold(
        body: Row(
          children: [
            sidebar,
            Expanded(
              child: Column(
                children: [
                  bar,
                  Expanded(child: content(style)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
