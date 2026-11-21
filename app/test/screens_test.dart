// Renders every screen from a recorded server state at phone and desktop
// sizes, in both spoiler modes. Layout overflows and build errors fail the
// test. Set OOT_SHOTS=<folder> to also write a PNG of each screen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart' show MacosIcon;
import 'package:oot_tracker/oot_tracker.dart';
import 'package:oot_tracker_app/client.dart';
import 'package:oot_tracker_app/desktop/linux_app.dart';
import 'package:oot_tracker_app/desktop/mac_app.dart';
import 'package:oot_tracker_app/desktop/windows_app.dart';
import 'package:oot_tracker_app/main.dart';
import 'package:oot_tracker_app/screens/area_detail.dart';
import 'package:oot_tracker_app/screens/map.dart';
import 'package:oot_tracker_app/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async => ByteData.sublistView(await File('$dir/$name').readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(font('Roboto-Regular.ttf'))
        ..addFont(font('Roboto-Medium.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(font('MaterialIcons-Regular.otf'))).load();
  // Stand-ins for the interface fonts of macOS, Windows and GNOME.
  for (final family in ['.AppleSystemUIFont', 'Segoe UI Variable Text', 'Segoe UI', 'Adwaita Sans']) {
    await (FontLoader(family)
          ..addFont(font('Roboto-Regular.ttf'))
          ..addFont(font('Roboto-Medium.ttf')))
        .load();
  }
  for (final icons in ['FluentIcons', 'SegoeIcons']) {
    await (FontLoader(
      'packages/fluent_ui/$icons',
    )..addFont(rootBundle.load('packages/fluent_ui/fonts/$icons.ttf'))).load();
  }
  await (FontLoader(
    'packages/cupertino_icons/CupertinoIcons',
  )..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
}

void main() {
  final shots = Platform.environment['OOT_SHOTS'];
  final boundary = GlobalKey();

  setUpAll(() async {
    await loadFonts();
    // macos_ui asks AppKit for system colours. There is no AppKit here, so
    // the question stays open and its built-in defaults are used.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (call) => Completer<Object?>().future,
    );
  });

  Future<TrackerClient> client({required bool spoilerFree}) async {
    SharedPreferences.setMockInitialValues({
      'state': File('test/state.json').readAsStringSync(),
      'spoilerFree': spoilerFree,
    });
    final c = TrackerClient(await SharedPreferences.getInstance());
    // The game maps exist only where they were extracted from the user's own
    // game (data/local, not in version control); without them the drawn
    // diagram is tested instead.
    final maps = Directory('../data/local/maps');
    if (maps.existsSync() && File('../data/maps.json').existsSync()) {
      c
        ..mapCacheDir = maps
        ..maps = MapIndex.fromJson(jsonDecode(File('../data/maps.json').readAsStringSync()) as Json);
    }
    return c;
  }

  /// Decodes the map pictures of [areas] (and the world) into the image
  /// cache. Decoding needs real time, which widgets under test do not get,
  /// so it has to happen before they are built.
  Future<void> warmMaps(WidgetTester tester, TrackerClient c, [List<String> areas = const []]) async {
    final index = c.maps;
    if (index == null) return;
    final maps = [?index.world, for (final area in areas) ...index.ofArea(area)];
    await tester.runAsync(() async {
      for (final map in maps) {
        final done = Completer<void>();
        FileImage(File('${c.mapCacheDir!.path}/${map.file}'))
            .resolve(ImageConfiguration.empty)
            .addListener(ImageStreamListener((_, _) => done.complete(), onError: (e, _) => done.completeError(e)));
        await done.future;
      }
    });
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    // A second frame, for content that appears once a future has completed.
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    if (shots == null) return;
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final spoilerFree in [true, false]) {
    final mode = spoilerFree ? 'spoilerfree' : 'spoilers';

    testWidgets('phone screens render: $mode', (tester) async {
      tester.view
        ..physicalSize = const Size(400, 860)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await client(spoilerFree: spoilerFree);
      await warmMaps(tester, c);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: TrackerApp(client: c),
        ),
      );
      await shot(tester, 'phone-$mode-overview');
      // A category tile opens the list of that category across all areas.
      await tester.tap(find.text('Heart Pieces'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700)); // page transition
      await shot(tester, 'phone-$mode-category');
      expect(find.byType(CategoryDetailScreen), findsOneWidget);
      if (spoilerFree) expectNoSpoilers(c, 'gerudo_valley');
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      for (final tab in ['Areas', 'Map', 'Settings']) {
        await tester.tap(find.text(tab).last);
        await shot(tester, 'phone-$mode-${tab.toLowerCase()}');
      }
      // An area with many entries of several categories.
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ClientScope(
            client: c,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorSchemeSeed: const Color(0xFF3E8E5A), brightness: Brightness.dark),
              home: const AreaDetailScreen(areaId: 'gerudo_valley'),
            ),
          ),
        ),
      );
      await shot(tester, 'phone-$mode-area');
      if (spoilerFree) expectNoSpoilers(c, 'gerudo_valley');
    });

    testWidgets('area maps render: $mode', (tester) async {
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await client(spoilerFree: spoilerFree);
      if (c.maps == null) return;
      await warmMaps(tester, c, ['gerudo_valley', 'spirit_temple', 'kokiri_forest']);
      for (final area in ['gerudo_valley', 'spirit_temple', 'kokiri_forest']) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ClientScope(
              client: c,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(colorSchemeSeed: const Color(0xFF3E8E5A), brightness: Brightness.dark),
                home: Scaffold(
                  body: MapScreen(key: ValueKey(area), initialArea: area),
                ),
              ),
            ),
          ),
        );
        await shot(tester, 'map-$mode-$area');
        // Pins are spoilers: none may be drawn in spoiler-free mode.
        final pins = find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').endsWith('(missing)'));
        expect(pins, spoilerFree ? findsNothing : findsWidgets, reason: area);
      }
    });

    testWidgets('macOS panes render: $mode', (tester) async {
      tester.view
        ..physicalSize = const Size(1120, 740)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await client(spoilerFree: spoilerFree);
      await warmMaps(tester, c);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MacApp(client: c),
        ),
      );
      await shot(tester, 'desktop-$mode-overview');
      // Settings sits in the toolbar, next to the connection status.
      await tester.tap(find.byWidgetPredicate((w) => w is MacosIcon && w.icon == CupertinoIcons.gear));
      await shot(tester, 'desktop-$mode-settings');
      for (final row in ['Map', 'Heart Pieces', 'Gerudo Valley']) {
        await tapSidebar(tester, row);
        await shot(tester, 'desktop-$mode-${row.toLowerCase().replaceAll(' ', '-')}');
        if (spoilerFree && row != 'Map') expectNoSpoilers(c, 'gerudo_valley');
      }
      // macos_ui schedules zero-length timers while laying out; let them run
      // while the window is still mounted.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    // The Windows and GNOME looks, one in light and one in dark mode each.
    for (final system in ['windows', 'linux']) {
      testWidgets('$system panes render: $mode', (tester) async {
        tester.view
          ..physicalSize = const Size(1280, 720)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.platformBrightnessTestValue = spoilerFree ? Brightness.light : Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final c = await client(spoilerFree: spoilerFree);
        await warmMaps(tester, c);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: system == 'windows' ? WindowsApp(client: c) : LinuxApp(client: c),
          ),
        );
        await shot(tester, '$system-$mode-overview');
        // Settings is the last item of the navigation pane on Windows and a
        // button in the bar on GNOME.
        await tester.tap(system == 'windows' ? find.text('Settings', findRichText: true) : find.byTooltip('Settings'));
        await shot(tester, '$system-$mode-settings');
        expect(find.text('Spoiler-free mode'), findsOneWidget);
        for (final row in ['Map', 'Heart Pieces', 'Gerudo Valley']) {
          await tapSidebar(tester, row);
          await shot(tester, '$system-$mode-${row.toLowerCase().replaceAll(' ', '-')}');
          if (spoilerFree && row != 'Map') expectNoSpoilers(c, 'gerudo_valley');
        }
        expect(find.textContaining('collected'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
    }
  }
}

/// Taps the sidebar row called [label], scrolling the sidebar to it first.
Future<void> tapSidebar(WidgetTester tester, String label) async {
  final sidebar = find.byType(Scrollable).first;
  final rows = find.descendant(of: sidebar, matching: find.text(label, findRichText: true));
  // Rows far down the list are only built once they are scrolled near.
  for (var i = 0; i < 40 && rows.evaluate().isEmpty; i++) {
    await tester.drag(sidebar, const Offset(0, -200));
    await tester.pump();
  }
  final row = rows.first;
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.tap(row);
}

/// Counts only: no title of a missing check of [area] may be on screen.
void expectNoSpoilers(TrackerClient c, String area) {
  final missing = c.state!.checks.where((k) => !k.done && k.def.area == area);
  expect(missing, isNotEmpty);
  for (final check in missing) {
    expect(find.textContaining(check.def.title), findsNothing, reason: check.def.id);
  }
}
