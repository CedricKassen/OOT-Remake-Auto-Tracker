import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart'
    show ColorScheme, DefaultMaterialLocalizations, Material, MaterialType, NoSplash, Theme, ThemeData;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show
        AdaptiveBottomNavigationBar,
        AdaptiveNavigationDestination,
        AdaptiveScaffold,
        AdaptiveToolbarHost,
        PlatformInfo;

import '../client.dart';
import '../screens/map.dart';
import '../widgets.dart';
import 'pages.dart';
import 'style.dart';

/// The iPhone and iPad app: the system's tab bar, pages with large titles,
/// grouped lists. Android has the Material one in `main.dart`.
class IosApp extends StatelessWidget {
  const IosApp({super.key, required this.client});
  final TrackerClient client;

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: CupertinoApp(
        title: 'OoT Tracker',
        debugShowCheckedModeBanner: false,
        // The map is shared with the other interfaces and built from
        // Material widgets, which ask for their own texts and colours.
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        builder: (context, child) {
          final brightness = CupertinoTheme.brightnessOf(context);
          return Theme(
            data: ThemeData(
              brightness: brightness,
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E8E5A), brightness: brightness),
              fontFamily: CupertinoTheme.of(context).textTheme.textStyle.fontFamily,
              splashFactory: NoSplash.splashFactory,
            ),
            // The package with the system's bars still builds on the
            // Cupertino library inside Flutter; the bridge hands it our theme
            // and texts. The host keeps one toolbar above all pages, which
            // slide under it.
            child: CupertinoTheme(
              // Spelled out: the system's controls take light or dark from
              // the theme and do not look at the device themselves.
              data: CupertinoTheme.of(context).copyWith(brightness: brightness),
              // ignore: deprecated_member_use
              child: CupertinoUiCompatibilityBridge(
                child: iosSystemControls ? AdaptiveToolbarHost(child: child!) : child!,
              ),
            ),
          );
        },
        home: const _Tabs(),
      ),
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  // Label, SF Symbol (plain and selected) and the icons standing in for
  // them before iOS 26.
  static const _tabs = [
    ('Overview', 'chart.pie', 'chart.pie.fill', CupertinoIcons.chart_pie, CupertinoIcons.chart_pie_fill),
    ('Areas', 'list.bullet', 'list.bullet', CupertinoIcons.list_bullet, CupertinoIcons.list_bullet),
    ('Map', 'map', 'map.fill', CupertinoIcons.map, CupertinoIcons.map_fill),
    ('Settings', 'gearshape', 'gearshape.fill', CupertinoIcons.gear, CupertinoIcons.gear_solid),
  ];

  int _index = 0;

  // Every tab keeps its own stack of pages; a tab is built when first shown.
  final _navigators = [for (final _ in _tabs) GlobalKey<NavigatorState>()];
  final _opened = {0};

  void _select(int index) {
    if (index == _index) {
      // The current tab again: back to its first page.
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _index = index;
      _opened.add(index);
    });
  }

  Widget _page(int index) => switch (index) {
    0 => const IosOverviewPage(),
    1 => const IosAreasPage(),
    2 => const _MapPage(),
    _ => const IosSettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          if (_opened.contains(i))
            CupertinoTabView(
              navigatorKey: _navigators[i],
              // Names the back button of the pages opened from this tab.
              defaultTitle: _tabs[i].$1,
              builder: (context) => _page(i),
            )
          else
            const SizedBox.shrink(),
      ],
    );
    if (!iosSystemControls) {
      return Column(
        children: [
          Expanded(child: pages),
          CupertinoTabBar(
            currentIndex: _index,
            onTap: _select,
            items: [
              for (final (label, _, _, icon, selected) in _tabs)
                BottomNavigationBarItem(icon: Icon(icon), activeIcon: Icon(selected), label: label),
            ],
          ),
        ],
      );
    }
    // The system's own tab bar: Liquid Glass from iOS 26 on, the classic bar
    // before. The pages run under it.
    final glass = PlatformInfo.isIOS26OrHigher();
    return AdaptiveScaffold(
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _index,
        onTap: _select,
        items: [
          for (final (label, symbol, selectedSymbol, icon, selectedIcon) in _tabs)
            AdaptiveNavigationDestination(
              label: label,
              icon: glass ? symbol : icon,
              selectedIcon: glass ? selectedSymbol : selectedIcon,
            ),
        ],
      ),
      body: pages,
    );
  }
}

class _MapPage extends StatelessWidget {
  const _MapPage();

  @override
  Widget build(BuildContext context) {
    final state = ClientScope.of(context).state;
    return CupertinoPageScaffold(
      // No bar on top: the map has the whole screen and runs on under the
      // tab bar.
      child: SafeArea(
        bottom: false,
        child: state == null
            ? const IosEmptyState()
            : Material(
                type: MaterialType.transparency,
                child: MapScreen(onOpenArea: (id) => openIosArea(context, id)),
              ),
      ),
    );
  }
}
