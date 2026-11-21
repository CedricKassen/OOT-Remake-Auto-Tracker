// Renders the settings window against a real server reading the fixture
// save, in the Mac look and in the Windows/Linux look. Layout overflows and
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
    for (final family in ['Roboto', '.AppleSystemUIFont']) {
      await (FontLoader(family)
            ..addFont(font('Roboto-Regular.ttf'))
            ..addFont(font('Roboto-Medium.ttf')))
          .load();
    }
    // macos_ui asks AppKit for system colours; there is no AppKit here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (call) => Completer<Object?>().future,
    );
  });

  for (final look in ['mac', 'material']) {
    for (final found in [true, false]) {
      testWidgets('settings window: $look, save ${found ? 'found' : 'missing'}', (tester) async {
        mac = look == 'mac';
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
}
