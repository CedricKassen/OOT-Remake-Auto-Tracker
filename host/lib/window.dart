import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:material_ui/material_ui.dart';
import 'package:macos_ui/macos_ui.dart' show MacosTheme, MacosThemeData;
import 'package:oot_save/oot_save.dart';
import 'package:oot_ui/oot_ui.dart';
import 'package:ootd/runner.dart';

import 'controller.dart';
import 'controls.dart';

/// Where the tray icon lives, in the words of each system.
String get trayName => Platform.isMacOS
    ? 'menu bar'
    : Platform.isWindows
    ? 'notification area'
    : 'system tray';

String slotLabel(String id) => id.replaceFirst(RegExp('^slot_0?'), 'Slot ');

class HostApp extends StatelessWidget {
  const HostApp({super.key, required this.controller, required this.onQuit});
  final HostController controller;
  final VoidCallback onQuit;

  ThemeData _theme(Brightness brightness) => desktopLook == DesktopLook.linux
      ? adwaitaTheme(brightness)
      : ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E8E5A), brightness: brightness),
          useMaterial3: true,
          fontFamily: Look.fontFamily,
        );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OoT Tracker Server',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    // The Windows controls bring their own texts, e.g. for a field's menu.
    localizationsDelegates: fluent.FluentLocalizations.localizationsDelegates,
    // The Mac and the Windows controls take their colours from their own
    // themes.
    builder: (context, child) {
      final brightness = Theme.of(context).brightness;
      return switch (desktopLook) {
        DesktopLook.mac => MacosTheme(
          data: brightness == Brightness.dark ? MacosThemeData.dark() : MacosThemeData.light(),
          child: child!,
        ),
        DesktopLook.windows => fluent.FluentTheme(
          data: fluent.FluentThemeData(
            brightness: brightness,
            accentColor: fluent.Colors.blue,
            fontFamily: Look.fontFamily,
          ),
          child: child!,
        ),
        DesktopLook.linux => child!,
      };
    },
    home: SettingsWindow(controller: controller, onQuit: onQuit),
  );
}

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key, required this.controller, required this.onQuit});
  final HostController controller;
  final VoidCallback onQuit;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late final TextEditingController _port, _token;
  String? _portError;
  String? _folderNote;

  HostController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: '${c.config.port}');
    _token = TextEditingController(text: c.config.token ?? '');
  }

  @override
  void dispose() {
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  bool get _networkDirty => _port.text.trim() != '${c.config.port}' || _token.text.trim() != (c.config.token ?? '');

  void _change(void Function(ServerConfig config) edit) {
    final next = c.config.copy();
    edit(next);
    c.apply(next);
  }

  void _applyNetwork() {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _portError = 'The port must be a number between 1024 and 65535.');
      return;
    }
    setState(() => _portError = null);
    _change((config) {
      config.port = port;
      config.token = _token.text.trim().isEmpty ? null : _token.text.trim();
    });
  }

  Future<void> _extractFromFile() async {
    final file = await openFile(
      confirmButtonText: 'Read maps',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Game image (RomFS.img)', extensions: ['img']),
      ],
    );
    if (file != null) await c.extractMaps(file.path);
  }

  Future<void> _extractFromFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Read maps');
    if (path != null) await c.extractMaps(path);
  }

  Future<void> _chooseMapsFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Choose', initialDirectory: c.config.mapsDir);
    if (path == null || !mounted) return;
    _change((config) => config.mapsDir = path);
  }

  Future<void> _chooseFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Choose', initialDirectory: c.config.saveDir ?? c.saveDir);
    if (path == null || !mounted) return;
    setState(
      () => _folderNote = SaveLocator.resolve(path) == null
          ? 'No save was found in that folder yet. The server keeps looking there.'
          : null,
    );
    _change((config) {
      config.saveDir = path;
      config.slot = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final look = Look.of(context);
      final config = c.config;
      final slot = c.slot;
      final slotIds = {...c.slotIds, if (config.slot != null) config.slot!}.toList()..sort();
      final problem = !c.starting && !c.running;
      final statusColor = c.starting
          ? const Color(0xFFFF9F0A)
          : problem
          ? const Color(0xFFFF453A)
          : c.saveDir == null
          ? const Color(0xFFFF9F0A)
          : const Color(0xFF34C759);
      final addresses = c.addresses.isEmpty ? 'No network connection' : c.addresses.join('  ·  ');

      return Scaffold(
        backgroundColor: look.window,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          children: [
            Group(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 10),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.summary, style: look.title),
                            const SizedBox(height: 4),
                            Text(
                              problem
                                  ? 'Change the port below, or quit the other program that uses it.'
                                  : c.saveDir == null
                                  ? (config.saveDir == null
                                        ? 'Start the game and save once, or choose the save folder below.'
                                        : 'Nothing found in the chosen folder yet.')
                                  : slot == null
                                  ? 'Reading the save…'
                                  : '${slotLabel(slot.id)}, saved ${slot.time?.toString().split('.').first.replaceFirst('T', ' ') ?? 'at an unknown time'}',
                              style: look.caption,
                            ),
                            if (c.runner.advertiseError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(c.runner.advertiseError!, style: look.caption),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const GroupHeader('Save game'),
            Group(
              children: [
                SettingRow(
                  title: config.saveDir == null ? 'Find the save automatically' : 'Save folder',
                  detail:
                      _folderNote ??
                      (config.saveDir ??
                          (c.saveDir == null
                              ? 'Looks where the PC port and known emulators keep their saves.'
                              : 'Found: ${c.saveDir}')),
                  below: Row(
                    children: [
                      ActionButton('Choose folder…', onPressed: _chooseFolder),
                      if (config.saveDir != null) ...[
                        const SizedBox(width: 8),
                        ActionButton(
                          'Find automatically',
                          onPressed: () {
                            setState(() => _folderNote = null);
                            _change((config) {
                              config.saveDir = null;
                              config.slot = null;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                SettingRow(
                  title: 'Save slot',
                  detail: config.slot == null ? 'Follows the slot you saved last.' : null,
                  control: Choice<String>(
                    value: config.slot ?? '',
                    options: {'': 'Most recent', for (final id in slotIds) id: slotLabel(id)},
                    onChanged: (id) => _change((config) => config.slot = id.isEmpty ? null : id),
                  ),
                ),
              ],
            ),
            const GroupHeader('Maps'),
            Group(
              children: [
                SettingRow(
                  title: c.mapCount == 0 ? 'No map pictures' : '${c.mapCount} map pictures',
                  detail: c.extracting
                      ? c.extractProgress
                      : c.extractResult ??
                            (c.mapCount == 0
                                ? 'The apps show a drawn diagram until the maps are read from your own copy of '
                                      'the game: the RomFS.img file of the PC port, or a folder with the unpacked '
                                      'game files.'
                                : 'Read from your copy of the game.'),
                  detailColor: c.extractFailed && !c.extracting ? look.scheme.error : null,
                  below: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionButton(
                        c.mapCount == 0 ? 'Read from game file…' : 'Read again from game file…',
                        primary: c.mapCount == 0,
                        onPressed: c.extracting ? null : _extractFromFile,
                      ),
                      ActionButton('From a folder…', onPressed: c.extracting ? null : _extractFromFolder),
                    ],
                  ),
                ),
                SettingRow(
                  title: 'Maps folder',
                  detail: c.mapsDir,
                  below: Row(
                    children: [
                      ActionButton('Choose folder…', onPressed: c.extracting ? null : _chooseMapsFolder),
                      if (config.mapsDir != null) ...[
                        const SizedBox(width: 8),
                        ActionButton(
                          'Use default folder',
                          onPressed: c.extracting ? null : () => _change((config) => config.mapsDir = null),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const GroupHeader('Network'),
            Group(
              children: [
                SettingRow(
                  title: 'Let apps find this computer',
                  detail: 'The tracker apps on your network then connect on their own.',
                  control: Toggle(value: config.advertise, onChanged: (v) => _change((config) => config.advertise = v)),
                ),
                SettingRow(
                  title: 'Address for manual setup',
                  detail: 'If an app does not find the server, enter this in its settings.',
                  below: SelectableText('$addresses\nPort ${config.port}', style: look.body),
                ),
                SettingRow(
                  title: 'Port',
                  detail: _portError,
                  detailColor: look.scheme.error,
                  control: Field(
                    controller: _port,
                    width: 90,
                    number: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _applyNetwork(),
                  ),
                ),
                SettingRow(
                  title: 'Access token',
                  detail: 'Optional. Apps then need the same token to connect.',
                  control: Field(
                    controller: _token,
                    width: 170,
                    obscure: true,
                    hint: 'None',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _applyNetwork(),
                  ),
                ),
                if (_networkDirty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ActionButton('Apply', primary: true, onPressed: _applyNetwork),
                    ),
                  ),
              ],
            ),
            const GroupHeader('General'),
            Group(
              children: [
                SettingRow(
                  title: 'Start when I log in',
                  detail: c.autostartError ?? 'Starts quietly in the $trayName.',
                  control: Toggle(value: c.autostartEnabled, onChanged: c.setAutostart),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Closing this window keeps the server running. '
                    'Open it again from the icon in the $trayName.',
                    style: look.caption,
                  ),
                ),
                const SizedBox(width: 12),
                ActionButton('Quit server', onPressed: widget.onQuit),
              ],
            ),
          ],
        ),
      );
    },
  );
}
