// Renders the settings window against a real server reading the fixture
// save, in the looks of macOS, Windows and GNOME. Layout overflows and
// build errors fail the test. Set OOT_SHOTS=<folder> to also write PNGs.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oot_tracker_host/autostart.dart';
import 'package:oot_tracker_host/controller.dart';
import 'package:oot_tracker_host/controls.dart';
import 'package:oot_tracker_host/window.dart';
import 'package:ootd/runner.dart';

class _NoAutostart extends Autostart {
  bool enabled = false;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> set(bool value) async => enabled = value;
}

void main() {
  final shots = Platform.environment['OOT_SHOTS'];
  final boundary = GlobalKey();

  setUpAll(() async {
    final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    Future<ByteData> font(String name) async => ByteData.sublistView(await File('$dir/$name').readAsBytes());
    // Roboto stands in for the interface fonts of macOS, Windows and GNOME.
    for (final family in ['Roboto', '.AppleSystemUIFont', 'Segoe UI Variable Text', 'Segoe UI', 'Adwaita Sans']) {
      await (FontLoader(family)
            ..addFont(font('Roboto-Regular.ttf'))
            ..addFont(font('Roboto-Medium.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')..addFont(font('MaterialIcons-Regular.otf'))).load();
    for (final icons in ['FluentIcons', 'SegoeIcons']) {
      await (FontLoader(
        'packages/fluent_ui/$icons',
      )..addFont(rootBundle.load('packages/fluent_ui/fonts/$icons.ttf'))).load();
    }
    // macos_ui asks AppKit for system colours; there is no AppKit here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (call) => Completer<Object?>().future,
    );
  });

  for (final system in DesktopLook.values) {
    final look = system.name;
    for (final found in [true, false]) {
      testWidgets('settings window: $look, save ${found ? 'found' : 'missing'}', (tester) async {
        desktopLook = system;
        addTearDown(() => desktopLook = DesktopLook.platform);
        tester.view
          ..physicalSize = const Size(500, 720)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final state = Directory.systemTemp.createTempSync('oot-host-test');
        addTearDown(() => state.deleteSync(recursive: true));
        final data = Directory('${state.path}/data')..createSync();
        for (final name in dataFiles) {
          File('../data/$name').copySync('${data.path}/$name');
        }
        final controller = HostController(stateDir: state.path, autostart: _NoAutostart(), onShow: () {});
        // Port 0: any free port, and nothing announced on the network.
        controller.config = ServerConfig(
          saveDir: found ? '../fixtures/save' : '${state.path}/nowhere',
          port: 0,
          bind: '127.0.0.1',
          advertise: false,
        );
        await tester.runAsync(controller.start);
        addTearDown(() => tester.runAsync(controller.shutdown));
        expect(controller.running, isTrue);
        expect(controller.saveDir != null, found);

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: HostApp(controller: controller, onQuit: () {}),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Running'), findsOneWidget);
        // The map extraction is offered in every look.
        expect(find.text('No map pictures'), findsOneWidget);
        expect(find.text('Read from game file…'), findsOneWidget);
        expect(find.text('From a folder…'), findsOneWidget);

        Future<void> shot(String name) async {
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

        await shot('host-$look-${found ? 'found' : 'missing'}-top');
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Start when I log in'), findsOneWidget);
        await shot('host-$look-${found ? 'found' : 'missing'}-bottom');
      });
    }
  }

  // OOT_GAME_FILES=<RomFS.img or folder>: reads the maps from the real game
  // the way the "Read from game file" button does.
  final game = Platform.environment['OOT_GAME_FILES'];
  testWidgets('reads the maps from the game', skip: game == null, (tester) async {
    final state = Directory.systemTemp.createTempSync('oot-host-test');
    addTearDown(() => state.deleteSync(recursive: true));
    final data = Directory('${state.path}/data')..createSync();
    for (final name in dataFiles) {
      File('../data/$name').copySync('${data.path}/$name');
    }
    final controller = HostController(stateDir: state.path, autostart: _NoAutostart(), onShow: () {});
    controller.config = ServerConfig(saveDir: '../fixtures/save', port: 0, bind: '127.0.0.1', advertise: false);
    await tester.runAsync(() async {
      await controller.start();
      expect(controller.mapCount, 0);
      final progress = <String>[];
      controller.addListener(() => progress.add(controller.extractProgress));
      await controller.extractMaps(game!);
      expect(controller.extractFailed, isFalse, reason: controller.extractResult);
      expect(controller.extractResult, startsWith('Saved 64 map pictures.'));
      expect(controller.mapCount, 64);
      expect(controller.running, isTrue);
      expect(progress.toSet().length, greaterThan(10));
      // And a wrong folder says so instead of throwing.
      await controller.extractMaps(state.path);
      expect(controller.extractFailed, isTrue);
      expect(controller.extractResult, contains('No game files'));
      await controller.shutdown();
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
