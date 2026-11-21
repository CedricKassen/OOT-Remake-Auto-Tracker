import 'dart:io';

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' show MacosWindowUtilsConfig;
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'desktop/linux_app.dart';
import 'desktop/mac_app.dart';
import 'desktop/windows_app.dart';
import 'screens/areas.dart';
import 'screens/map.dart';
import 'screens/overview.dart';
import 'screens/settings.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = TrackerClient(await SharedPreferences.getInstance());
  await client.start();
  if (Platform.isMacOS) {
    // A native-looking window: unified toolbar, translucent sidebar.
    await const MacosWindowUtilsConfig().apply();
    runApp(MacApp(client: client));
  } else if (Platform.isWindows) {
    runApp(WindowsApp(client: client));
  } else if (Platform.isLinux) {
    runApp(LinuxApp(client: client));
  } else {
    runApp(TrackerApp(client: client));
  }
}

/// The phone and tablet app. Each desktop system has its own in `desktop/`.
class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key, required this.client});
  final TrackerClient client;

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E8E5A), brightness: brightness),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: MaterialApp(
        title: 'OoT Tracker',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const _Shell(),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  static const _tabs = [
    ('Overview', Icons.dashboard_outlined, Icons.dashboard),
    ('Areas', Icons.list_alt_outlined, Icons.list_alt),
    ('Map', Icons.map_outlined, Icons.map),
    ('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(
      index: _index,
      children: const [OverviewScreen(), AreasScreen(), MapScreen(), SettingsScreen()],
    );
    final (statusColor, statusText) = switch (client.status) {
      LinkStatus.live => (const Color(0xFF5FBF77), 'Live'),
      LinkStatus.connecting => (gold, 'Connecting'),
      LinkStatus.searching => (gold, 'Searching'),
      LinkStatus.offline => (scheme.error, client.state == null ? 'Offline' : 'Offline · last known state'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_index].$1),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: statusColor),
              const SizedBox(width: 6),
              Text(statusText, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final (label, icon, selected) in _tabs)
                      NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final (label, icon, selected) in _tabs)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
              ],
            ),
    );
  }
}
