import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'service.dart';

/// The HTTP and WebSocket API (v1) in front of a [TrackerService].
///
///   GET    /api/v1/health          liveness, no token needed
///   GET    /api/v1/state           full tracker state (JSON)
///   GET    /api/v1/ws              WebSocket: state on connect and on change
///   GET    /api/v1/screenshot      JPEG of the current slot
///   PUT    /api/v1/manual/{id}     tick a manual check
///   DELETE /api/v1/manual/{id}     untick it
///   POST   /api/v1/anonymous/{area}/{category}?delta=±n
///                                  count a find without naming the check
///   GET    /api/v1/maps            index of the map images (maps.json)
///   GET    /api/v1/maps/{file}     one map image (PNG)
///   GET    /api/v1/fields[?all=1]  raw save fields, for research
///   POST   /api/v1/reload          re-read the game data files
class ApiServer {
  ApiServer(this.service, {this.token, this.onShow});

  final TrackerService service;

  /// When set, requests need `Authorization: Bearer <token>` or `?token=`.
  final String? token;

  /// Called when another copy of the server app on this computer asks the
  /// running one to show its window.
  final void Function()? onShow;
  final Set<WebSocket> _sockets = {};
  HttpServer? _server;
  StreamSubscription<String>? _subscription;

  int get port => _server!.port;

  /// How many apps are connected right now.
  int get clients => _sockets.length;

  Future<void> start(InternetAddress address, int port) async {
    _server = await HttpServer.bind(address, port);
    _subscription = service.changes.listen((json) {
      for (final socket in _sockets) {
        socket.add(json);
      }
    });
    _server!.listen((request) async {
      try {
        await _handle(request);
      } catch (e, stack) {
        stderr.writeln('Request failed: $e\n$stack');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {
          // The connection is already gone.
        }
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    for (final socket in _sockets.toList()) {
      await socket.close(WebSocketStatus.goingAway);
    }
    await _server?.close(force: true);
  }

  bool _authorized(HttpRequest request) {
    if (token == null) return true;
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    return header == 'Bearer $token' || request.uri.queryParameters['token'] == token;
  }

  Future<void> _send(HttpRequest request, int status, Object? body, {ContentType? type}) {
    final response = request.response..statusCode = status;
    if (body is List<int>) {
      response.headers.contentType = type ?? ContentType.binary;
      response.add(body);
    } else if (body is String) {
      response.headers.contentType = type ?? ContentType.json;
      response.add(utf8.encode(body));
    } else if (body != null) {
      response.headers.contentType = ContentType.json;
      response.add(utf8.encode(jsonEncode(body)));
    }
    return response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (path == '/api/v1/health') {
      return _send(request, 200, {'ok': true, 'name': 'oot-tracker', 'api': 1});
    }
    if (path == '/api/v1/show' && method == 'POST' && onShow != null) {
      if (request.connectionInfo?.remoteAddress.isLoopback != true) return _send(request, 403, {'error': 'Local only'});
      onShow!();
      return _send(request, 200, {'ok': true});
    }
    if (!_authorized(request)) return _send(request, 401, {'error': 'Token required'});

    if (path == '/api/v1/ws') {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        return _send(request, 400, {'error': 'WebSocket upgrade expected'});
      }
      final socket = await WebSocketTransformer.upgrade(request)
        ..pingInterval = const Duration(seconds: 20);
      _sockets.add(socket);
      socket.add(service.stateJson);
      socket.listen((_) {}, onDone: () => _sockets.remove(socket), onError: (_) => _sockets.remove(socket));
      return;
    }
    if (path == '/api/v1/state' && method == 'GET') {
      return _send(request, 200, service.stateJson);
    }
    if (path == '/api/v1/screenshot' && method == 'GET') {
      final image = service.screenshot;
      return image == null
          ? _send(request, 404, {'error': 'No screenshot'})
          : _send(request, 200, image, type: ContentType('image', 'jpeg'));
    }
    // Map artwork is extracted from the user's own game (by default into
    // data/local/maps) and only ever served from that folder.
    const maps = '/api/v1/maps';
    if (path == maps && method == 'GET') {
      return _send(request, 200, service.mapsJson());
    }
    if (path.startsWith('$maps/') && method == 'GET') {
      final name = path.substring(maps.length + 1);
      final file = File('${service.mapsDir}/$name');
      if (!RegExp(r'^[A-Za-z0-9_.-]+\.png$').hasMatch(name) || !file.existsSync()) {
        return _send(request, 404, {'error': 'No such map'});
      }
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=3600');
      return _send(request, 200, file.readAsBytesSync(), type: ContentType('image', 'png'));
    }
    if (path == '/api/v1/fields' && method == 'GET') {
      return _send(request, 200, service.fields(all: request.uri.queryParameters.containsKey('all')));
    }
    if (path == '/api/v1/reload' && method == 'POST') {
      service.reloadData();
      return _send(request, 200, {'ok': true});
    }
    const manual = '/api/v1/manual/';
    if (path.startsWith(manual) && (method == 'PUT' || method == 'DELETE')) {
      final id = Uri.decodeComponent(path.substring(manual.length));
      if (id.isEmpty) return _send(request, 400, {'error': 'Check id expected'});
      service.tick(id, method == 'PUT');
      return _send(request, 200, {'ok': true});
    }
    const anonymous = '/api/v1/anonymous/';
    if (path.startsWith(anonymous) && method == 'POST') {
      final parts = path.substring(anonymous.length).split('/');
      final delta = int.tryParse(request.uri.queryParameters['delta'] ?? '');
      if (parts.length != 2 || delta == null) {
        return _send(request, 400, {'error': 'Expected /anonymous/{area}/{category}?delta=±n'});
      }
      service.addAnonymous(parts[0], parts[1], delta);
      return _send(request, 200, {'ok': true});
    }
    return _send(request, 404, {'error': 'Not found'});
  }
}
