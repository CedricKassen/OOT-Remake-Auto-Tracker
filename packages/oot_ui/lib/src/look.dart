import 'dart:io';

/// Which desktop a window is drawn for.
enum DesktopLook {
  /// macOS, with macos_ui.
  mac,

  /// Windows 11 (Fluent), with fluent_ui.
  windows,

  /// GNOME (Adwaita), see `adwaita.dart`.
  linux;

  /// The look of the system this runs on.
  static DesktopLook get platform => Platform.isMacOS
      ? mac
      : Platform.isWindows
      ? windows
      : linux;
}
