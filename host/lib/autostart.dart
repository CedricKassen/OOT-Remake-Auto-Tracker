import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;

/// The argument the app is started with at login, so it stays in the tray.
const hiddenArg = '--hidden';

/// Starts the app when the user logs in.
class Autostart {
  Autostart() {
    if (!Platform.isMacOS) {
      launchAtStartup.setup(
        appName: 'OoT Tracker Server',
        // Inside an AppImage the executable sits in a mount that is gone
        // after it quits; the image file itself is what has to be started.
        appPath: Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable,
        args: [hiddenArg],
      );
    }
  }

  // macOS: a launch agent, which also works for an app that is not signed.
  static const _label = 'dev.oottracker.server';

  File get _agent => File(p.join(Platform.environment['HOME'] ?? '', 'Library', 'LaunchAgents', '$_label.plist'));

  static String _xml(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  Future<bool> isEnabled() async {
    try {
      if (!Platform.isMacOS) return await launchAtStartup.isEnabled();
      // Only if it starts this copy of the app, not one that was moved away.
      return _agent.existsSync() && _agent.readAsStringSync().contains(_xml(Platform.resolvedExecutable));
    } on Exception {
      return false;
    }
  }

  Future<void> set(bool enabled) async {
    if (!Platform.isMacOS) {
      enabled ? await launchAtStartup.enable() : await launchAtStartup.disable();
      return;
    }
    if (!enabled) {
      if (_agent.existsSync()) _agent.deleteSync();
      return;
    }
    _agent.parent.createSync(recursive: true);
    _agent.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xml(Platform.resolvedExecutable)}</string>
    <string>$hiddenArg</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
''');
  }
}
