import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:ootd/runner.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'autostart.dart';
import 'controller.dart';
import 'window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final stateDir = defaultStateDir();

  // Opening the app a second time shows the window of the one in the tray.
  final port = ServerConfig.load(p.join(stateDir, 'server.json')).port;
  if (await showRunningInstance(port)) exit(0);

  await windowManager.ensureInitialized();
  await unpackData(p.join(stateDir, 'data'));

  final shell = _Shell();
  final controller = HostController(stateDir: stateDir, autostart: Autostart(), onShow: shell.show);
  shell.controller = controller;
  // Stay in the tray when started at login; show the window otherwise.
  final hidden = args.contains(hiddenArg) && !controller.firstRun;

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(500, 720),
      minimumSize: Size(440, 480),
      center: true,
      title: 'OoT Tracker Server',
      skipTaskbar: false,
    ),
    () => windowManager.setPreventClose(true),
  );
  // The tray icon first: macOS only gives a menu-bar icon to an app that is
  // (still) a regular one with a Dock icon, which hiding the window ends.
  await shell.start();
  hidden ? await shell.hide() : await shell.show();
  runApp(HostApp(controller: controller, onQuit: shell.quit));
  await controller.start();
}

/// The tray icon and the window's life cycle.
class _Shell with TrayListener, WindowListener {
  late HostController controller;
  String _status = '';

  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows
          ? 'assets/tray.ico'
          : Platform.isMacOS
          ? 'assets/tray_template.png'
          : 'assets/tray.png',
      isTemplate: true,
    );
    controller.addListener(_updateTray);
    await _updateTray();
  }

  Future<void> _updateTray() async {
    final status = controller.summary;
    if (status == _status) return;
    _status = status;
    // Linux has no tooltips for tray icons.
    if (!Platform.isLinux) await trayManager.setToolTip('OoT Tracker Server\n$status');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(label: status, disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'show', label: 'Settings…'),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> show() async {
    // On macOS the Dock icon comes and goes with the window.
    if (Platform.isMacOS) await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) await windowManager.setSkipTaskbar(true);
  }

  Future<void> quit() async {
    await controller.shutdown();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // Closing the window leaves the server running in the tray.
  @override
  void onWindowClose() => hide();

  @override
  void onTrayIconMouseDown() => Platform.isMacOS ? trayManager.popUpContextMenu() : show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') show();
    if (menuItem.key == 'quit') quit();
  }
}
