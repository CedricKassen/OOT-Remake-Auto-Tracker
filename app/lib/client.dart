import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:oot_tracker/oot_tracker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LinkStatus { searching, connecting, live, offline }

/// A tracker server found on the local network.
class FoundServer {
  FoundServer(this.name, this.host, this.port);
  final String name;
  final String host;
  final int port;
}

/// Talks to the tracker server: finds it, keeps a WebSocket open for live
/// state, caches the last state for offline viewing and sends manual input.
class TrackerClient extends ChangeNotifier {
  TrackerClient(this._prefs) {
    autoDiscover = _prefs.getBool('autoDiscover') ?? true;
    host = _prefs.getString('host') ?? '';
    port = _prefs.getInt('port') ?? 7437;
    token = _prefs.getString('token') ?? '';
    spoilerFree = _prefs.getBool('spoilerFree') ?? true;
    final cachedMaps = _prefs.getString('maps');
    if (cachedMaps != null) {
      try {
        maps = MapIndex.fromJson(jsonDecode(cachedMaps) as Json);
      } catch (_) {
        // Ignore an unreadable cache; it is fetched again.
      }
    }
    final cached = _prefs.getString('state');
    if (cached != null) {
      try {
        state = TrackerState.fromJson(jsonDecode(cached) as Json);
      } catch (_) {
        // A cache from an older version: ignore it.
      }
    }
  }

  final SharedPreferences _prefs;

  late bool autoDiscover;
  late String host;
  late int port;
  late String token;
  late bool spoilerFree;

  TrackerState? state;
  Uint8List? screenshot;

  /// The game maps the server offers; null or empty if it has none.
  MapIndex? maps;

  /// Where downloaded map images are kept. Set before use to override.
  Directory? mapCacheDir;
  final Map<String, Future<File?>> _mapFiles = {};
  LinkStatus status = LinkStatus.offline;
  String? lastError;
  final List<FoundServer> found = [];

  WebSocket? _socket;
  Timer? _retry;
  nsd.Discovery? _discovery;
  String? _screenshotOf;
  int _generation = 0;
  bool _disposed = false;

  /// The server currently used: the configured one, or the first one found.
  (String, int)? get _target {
    if (!autoDiscover) return host.isEmpty ? null : (host, port);
    return found.isEmpty ? null : (found.first.host, found.first.port);
  }

  String get targetLabel {
    final t = _target;
    return t == null ? '' : '${t.$1}:${t.$2}';
  }

  Future<void> start() async {
    unawaited(_startDiscovery());
    _connect();
  }

  Future<void> _startDiscovery() async {
    try {
      final discovery = await nsd.startDiscovery('_oottracker._tcp', ipLookupType: nsd.IpLookupType.v4);
      _discovery = discovery;
      discovery.addListener(() {
        found
          ..clear()
          ..addAll([
            for (final s in discovery.services)
              if (s.port != null && (s.addresses?.isNotEmpty == true || s.host != null))
                FoundServer(
                  s.name ?? 'OoT Tracker',
                  s.addresses?.isNotEmpty == true ? s.addresses!.first.address : s.host!,
                  s.port!,
                ),
          ]);
        notifyListeners();
        if (autoDiscover && _socket == null) _connect();
      });
    } catch (e) {
      lastError = 'Network discovery is unavailable: $e';
      notifyListeners();
    }
  }

  void _setStatus(LinkStatus value, [String? error]) {
    if (_disposed) return;
    status = value;
    if (error != null) lastError = error;
    notifyListeners();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _retry?.cancel();
    await _socket?.close();
    _socket = null;
    final target = _target;
    if (target == null) {
      _setStatus(autoDiscover ? LinkStatus.searching : LinkStatus.offline);
      return;
    }
    _setStatus(LinkStatus.connecting);
    try {
      final socket = await WebSocket.connect(
        'ws://${target.$1}:${target.$2}/api/v1/ws',
        headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (generation != _generation || _disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      lastError = null;
      _setStatus(LinkStatus.live);
      unawaited(_loadMaps());
      socket.listen(
        (message) => _onState(message as String),
        onDone: () => _lost(generation, null),
        onError: (Object e) => _lost(generation, '$e'),
        cancelOnError: true,
      );
    } catch (e) {
      _lost(generation, e is TimeoutException ? 'The server did not answer' : '$e');
    }
  }

  void _lost(int generation, String? error) {
    if (generation != _generation || _disposed) return;
    _socket = null;
    _setStatus(LinkStatus.offline, error);
    _retry = Timer(const Duration(seconds: 3), _connect);
  }

  void _onState(String message) {
    try {
      state = TrackerState.fromJson(jsonDecode(message) as Json);
    } catch (e) {
      lastError = 'Unexpected data from the server: $e';
      notifyListeners();
      return;
    }
    _prefs.setString('state', message);
    notifyListeners();
    final key = '${state!.save?.slot}@${state!.save?.savedAt}';
    if (key != _screenshotOf) {
      _screenshotOf = key;
      _loadScreenshot();
    }
  }

  Future<HttpClientResponse?> _request(String method, String path) async {
    final target = _target;
    if (target == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, Uri.parse('http://${target.$1}:${target.$2}$path'));
      if (token.isNotEmpty) request.headers.set('Authorization', 'Bearer $token');
      return await request.close();
    } on IOException catch (e) {
      lastError = '$e';
      notifyListeners();
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _loadScreenshot() async {
    final response = await _request('GET', '/api/v1/screenshot');
    if (response == null) return;
    if (response.statusCode != 200) {
      await response.drain<void>();
      screenshot = null;
    } else {
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      screenshot = builder.takeBytes();
    }
    notifyListeners();
  }

  Future<String?> _text(String path) async {
    final response = await _request('GET', path);
    if (response == null) return null;
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    return utf8.decodeStream(response);
  }

  Future<void> _loadMaps() async {
    final text = await _text('/api/v1/maps');
    if (text == null || text == _prefs.getString('maps')) return;
    try {
      maps = MapIndex.fromJson(jsonDecode(text) as Json);
    } catch (_) {
      return;
    }
    // The pictures may have changed along with the index.
    _mapFiles.clear();
    final dir = await _mapDir();
    if (dir.existsSync() && mapCacheDir == null) dir.deleteSync(recursive: true);
    await _prefs.setString('maps', text);
    notifyListeners();
  }

  Future<Directory> _mapDir() async =>
      mapCacheDir ?? Directory('${(await getApplicationSupportDirectory()).path}/maps');

  /// The image file of a map, downloaded from the server on first use and
  /// kept for offline viewing. Null if it cannot be had right now.
  Future<File?> mapImage(String name) => _mapFiles[name] ??= _fetchMapImage(name).then((file) {
    if (file == null) _mapFiles.remove(name);
    return file;
  });

  Future<File?> _fetchMapImage(String name) async {
    final file = File('${(await _mapDir()).path}/$name');
    if (file.existsSync()) return file;
    final response = await _request('GET', '/api/v1/maps/$name');
    if (response == null) return null;
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    file.parent.createSync(recursive: true);
    final part = File('${file.path}.part')..writeAsBytesSync(builder.takeBytes());
    return part.renameSync(file.path);
  }

  bool get canEdit => status == LinkStatus.live;

  /// Ticks or unticks a manual check. The new state arrives over the socket.
  Future<void> tick(String id, bool done) async {
    final response = await _request(done ? 'PUT' : 'DELETE', '/api/v1/manual/${Uri.encodeComponent(id)}');
    await response?.drain<void>();
  }

  /// Counts a find in [area]/[category] without naming the check.
  Future<void> addAnonymous(String area, String category, int delta) async {
    final response = await _request('POST', '/api/v1/anonymous/$area/$category?delta=$delta');
    await response?.drain<void>();
  }

  void setSpoilerFree(bool value) {
    spoilerFree = value;
    _prefs.setBool('spoilerFree', value);
    notifyListeners();
  }

  void setServer({required bool auto, required String host, required int port, required String token}) {
    autoDiscover = auto;
    this.host = host.trim();
    this.port = port;
    this.token = token.trim();
    _prefs
      ..setBool('autoDiscover', auto)
      ..setString('host', this.host)
      ..setInt('port', port)
      ..setString('token', this.token);
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _socket?.close();
    final discovery = _discovery;
    if (discovery != null) nsd.stopDiscovery(discovery);
    super.dispose();
  }
}
