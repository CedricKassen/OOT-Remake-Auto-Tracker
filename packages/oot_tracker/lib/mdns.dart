/// A small DNS-SD over multicast DNS implementation: enough to announce the
/// tracker server on the local network and to find it, on systems that have
/// no Bonjour service to do it for us.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The service type the tracker server is announced as.
const String trackerServiceType = '_oottracker._tcp';

const int _port = 5353;
final InternetAddress _group = InternetAddress('224.0.0.251');

const int _typeA = 1, _typePtr = 12, _typeTxt = 16, _typeSrv = 33, _typeAny = 255;

/// One resource record of a DNS message.
class DnsRecord {
  DnsRecord(this.name, this.type, this.ttl, this.data, {this.target, this.port, this.address});
  final String name;
  final int type;
  final int ttl;
  final Uint8List data;

  /// The name a PTR or SRV record points at.
  final String? target;

  /// The port of an SRV record.
  final int? port;

  /// The address of an A record.
  final InternetAddress? address;
}

/// A question of a DNS message; [unicast] asks for a direct reply.
typedef DnsQuestion = ({String name, int type, bool unicast});

/// A parsed DNS message.
class DnsMessage {
  DnsMessage(this.isResponse, this.questions, this.records);
  final bool isResponse;
  final List<DnsQuestion> questions;
  final List<DnsRecord> records;

  /// Parses [bytes]; returns null for anything malformed.
  static DnsMessage? parse(Uint8List bytes) {
    try {
      return _Reader(bytes).message();
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }
}

class _Reader {
  _Reader(this.bytes) : view = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData view;
  int at = 0;

  int u8() => bytes[at++];
  int u16() => view.getUint16((at += 2) - 2);
  int u32() => view.getUint32((at += 4) - 4);

  /// Reads a possibly compressed name starting at [at].
  String name() {
    final labels = <String>[];
    var pos = at;
    int? resume;
    for (var jumps = 0; ; ) {
      final length = bytes[pos];
      if (length == 0) {
        pos++;
        break;
      }
      if (length & 0xC0 == 0xC0) {
        if (++jumps > 32) throw const FormatException('Pointer loop');
        resume ??= pos + 2;
        pos = ((length & 0x3F) << 8) | bytes[pos + 1];
        continue;
      }
      if (length > 63) throw const FormatException('Bad label');
      labels.add(utf8.decode(bytes.sublist(pos + 1, pos + 1 + length), allowMalformed: true));
      pos += 1 + length;
    }
    at = resume ?? pos;
    return labels.join('.');
  }

  DnsMessage message() {
    u16(); // id
    final flags = u16();
    final counts = [u16(), u16(), u16(), u16()];
    final questions = <DnsQuestion>[];
    for (var i = 0; i < counts[0]; i++) {
      final n = name();
      final type = u16();
      final klass = u16();
      questions.add((name: n, type: type, unicast: klass & 0x8000 != 0));
    }
    final records = <DnsRecord>[];
    for (var i = 0; i < counts[1] + counts[2] + counts[3]; i++) {
      final n = name();
      final type = u16();
      u16(); // class
      final ttl = u32();
      final length = u16();
      final start = at;
      final data = bytes.sublist(start, start + length);
      String? target;
      int? port;
      InternetAddress? address;
      if (type == _typePtr) {
        target = name();
      } else if (type == _typeSrv) {
        at += 4;
        port = u16();
        target = name();
      } else if (type == _typeA && length == 4) {
        address = InternetAddress.fromRawAddress(data);
      }
      at = start + length;
      records.add(DnsRecord(n, type, ttl, data, target: target, port: port, address: address));
    }
    return DnsMessage(flags & 0x8000 != 0, questions, records);
  }
}

class _Writer {
  final BytesBuilder _out = BytesBuilder();

  void u16(int v) => _out.add([(v >> 8) & 0xFF, v & 0xFF]);
  void u32(int v) => _out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

  static Uint8List encodeName(String name) {
    final out = BytesBuilder();
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final bytes = utf8.encode(label);
      out
        ..addByte(bytes.length > 63 ? 63 : bytes.length)
        ..add(bytes.length > 63 ? bytes.sublist(0, 63) : bytes);
    }
    out.addByte(0);
    return out.takeBytes();
  }

  void name(String name) => _out.add(encodeName(name));

  void header({required bool response, int questions = 0, int answers = 0, int additional = 0}) {
    u16(0);
    u16(response ? 0x8400 : 0);
    u16(questions);
    u16(answers);
    u16(0);
    u16(additional);
  }

  void record(String n, int type, int ttl, List<int> data, {bool flush = false}) {
    name(n);
    u16(type);
    u16(flush ? 0x8001 : 1);
    u32(ttl);
    u16(data.length);
    _out.add(data);
  }

  Uint8List bytes() => _out.takeBytes();
}

Future<RawDatagramSocket> _bind({bool shared = true}) async {
  final socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    shared ? _port : 0,
    reuseAddress: true,
    reusePort: shared && !Platform.isWindows,
  );
  socket
    ..multicastHops = 255
    ..multicastLoopback = true;
  if (shared) {
    // Join on every interface; joining the default one is the fallback.
    var joined = 0;
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        try {
          socket.joinMulticast(_group, interface);
          joined++;
        } on OSError {
          // Not a multicast interface, or already joined.
        } on SocketException {
          // Same.
        }
      }
    } on SocketException {
      // Listing interfaces is not allowed everywhere.
    }
    if (joined == 0) socket.joinMulticast(_group);
  }
  return socket;
}

/// One usable IPv4 address for each network interface.
Future<List<InternetAddress>> _interfaceAddresses() async {
  try {
    return [
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4))
        ?interface.addresses.where((a) => !a.isLoopback && !a.isLinkLocal).firstOrNull,
    ];
  } on SocketException {
    return const [];
  }
}

/// Sends a message to the mDNS group through every interface in
/// [interfaces]. Left alone, the system picks a single interface for
/// multicast, and on a machine with virtual adapters (Hyper-V, WSL, VPN) that
/// is often not the one the home network is on. [message] gets the address
/// of the interface it goes out on, or null when the system has to choose.
void _sendToGroup(
  RawDatagramSocket socket,
  List<InternetAddress> interfaces,
  Uint8List Function(InternetAddress? own) message,
) {
  var sent = 0;
  for (final own in interfaces) {
    try {
      socket.setRawOption(
        RawSocketOption(RawSocketOption.levelIPv4, RawSocketOption.IPv4MulticastInterface, own.rawAddress),
      );
      if (socket.send(message(own), _group, _port) > 0) sent++;
    } on SocketException {
      // This interface cannot send right now.
    } on OSError {
      // Same.
    }
  }
  if (sent > 0) return;
  try {
    socket.send(message(null), _group, _port);
  } on SocketException {
    // No route right now (network down): the next round tries again.
  }
}

/// The local IPv4 addresses that other devices could reach.
Future<List<InternetAddress>> localAddresses() async {
  try {
    return [
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address,
    ];
  } on SocketException {
    return const [];
  }
}

int _commonBits(InternetAddress a, InternetAddress b) {
  final x = a.rawAddress, y = b.rawAddress;
  var bits = 0;
  for (var i = 0; i < 4; i++) {
    final diff = x[i] ^ y[i];
    if (diff == 0) {
      bits += 8;
      continue;
    }
    for (var mask = 0x80; mask != 0 && diff & mask == 0; mask >>= 1) {
      bits++;
    }
    break;
  }
  return bits;
}

/// Announces one service and answers queries for it.
class MdnsResponder {
  MdnsResponder({required this.name, required this.port, this.type = trackerServiceType})
    : _host = 'oot-tracker-${(name.hashCode & 0xFFFFFF).toRadixString(16)}.local';

  /// The instance name shown to users, e.g. "OoT Tracker".
  final String name;
  final String type;
  final int port;
  final String _host;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _events;

  String get _service => '$type.local';
  String get _instance => '$name.$_service';

  Future<void> start() async {
    final socket = _socket = await _bind();
    _events = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var packet = socket.receive(); packet != null; packet = socket.receive()) {
        _onPacket(packet);
      }
    });
    await _announce(120);
    Timer(const Duration(seconds: 1), () {
      if (_socket == socket) _announce(120);
    });
  }

  /// Withdraws the service and closes the socket.
  Future<void> stop() async {
    if (_socket == null) return;
    await _announce(0);
    await _events?.cancel();
    _socket?.close();
    _socket = null;
  }

  Future<void> _announce(int ttl) => _toGroup((own) => _response([?own], ttl));

  /// Sends to the group on every interface, each with its own address.
  Future<void> _toGroup(Uint8List Function(InternetAddress? own) message) async {
    final interfaces = await _interfaceAddresses();
    final socket = _socket;
    if (socket != null) _sendToGroup(socket, interfaces, message);
  }

  Uint8List _response(List<InternetAddress> addresses, int ttl) {
    final srv = BytesBuilder()
      ..add([0, 0, 0, 0, (port >> 8) & 0xFF, port & 0xFF])
      ..add(_Writer.encodeName(_host));
    final txt = utf8.encode('api=1');
    final w = _Writer()
      ..header(response: true, answers: 1, additional: 2 + addresses.length)
      ..record(_service, _typePtr, ttl, _Writer.encodeName(_instance))
      ..record(_instance, _typeSrv, ttl, srv.takeBytes(), flush: true)
      ..record(_instance, _typeTxt, ttl, [txt.length, ...txt], flush: true);
    for (final address in addresses) {
      w.record(_host, _typeA, ttl, address.rawAddress, flush: true);
    }
    return w.bytes();
  }

  Future<void> _onPacket(Datagram packet) async {
    final message = DnsMessage.parse(packet.data);
    if (message == null || message.isResponse) return;
    bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();
    var wanted = false, unicast = packet.port != _port;
    for (final q in message.questions) {
      final hit =
          (same(q.name, _service) && (q.type == _typePtr || q.type == _typeAny)) ||
          same(q.name, _instance) ||
          (same(q.name, _host) && (q.type == _typeA || q.type == _typeAny));
      if (hit) {
        wanted = true;
        unicast = unicast || q.unicast;
      } else if (same(q.name, '_services._dns-sd._udp.local') && q.type == _typePtr) {
        // Service type enumeration ("which kinds of services are there?").
        final w = _Writer()
          ..header(response: true, answers: 1)
          ..record(q.name, _typePtr, 120, _Writer.encodeName(_service));
        final bytes = w.bytes();
        unawaited(_toGroup((_) => bytes));
      }
    }
    if (!wanted) return;
    if (unicast) {
      // Offer the address the asker can most likely reach: the one sharing
      // the longest prefix with its own.
      final addresses = (await localAddresses()).toList()
        ..sort((a, b) => _commonBits(b, packet.address).compareTo(_commonBits(a, packet.address)));
      try {
        _socket?.send(_response(addresses.take(1).toList(), 120), packet.address, packet.port);
      } on SocketException {
        // No route back right now; the asker asks again.
      }
    }
    if (packet.port == _port) await _toGroup((own) => _response([?own], 120));
  }
}

/// A service found by [MdnsBrowser].
typedef MdnsService = ({String name, String host, int port});

/// Looks for services of one type on the local network.
class MdnsBrowser {
  MdnsBrowser({this.type = trackerServiceType, required this.onChange});

  final String type;

  /// Called with the current list whenever it changes.
  final void Function(List<MdnsService> services) onChange;

  /// Listens on the mDNS port for what is announced to everyone.
  RawDatagramSocket? _shared;

  /// Asks from a port of its own and gets direct replies. That also works
  /// where the mDNS port is taken exclusively, or where a firewall (Windows)
  /// lets no multicast through to this program but does let replies in.
  RawDatagramSocket? _direct;
  final List<StreamSubscription<RawSocketEvent>> _events = [];
  Timer? _timer;
  bool _running = false;
  int _round = 0;
  final Map<String, ({MdnsService service, DateTime seen})> _found = {};

  String get _service => '$type.local';

  Future<void> start() async {
    SocketException? failure;
    try {
      _shared = await _bind();
    } on SocketException catch (e) {
      failure = e;
    }
    try {
      _direct = await _bind(shared: false);
    } on SocketException catch (e) {
      failure = e;
    }
    if (_shared == null && _direct == null) throw failure!;
    for (final socket in [?_shared, ?_direct]) {
      _events.add(
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          for (var packet = socket.receive(); packet != null; packet = socket.receive()) {
            _onPacket(packet);
          }
        }),
      );
    }
    _running = true;
    unawaited(_query());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    for (final events in _events) {
      events.cancel();
    }
    _events.clear();
    _shared?.close();
    _direct?.close();
    _shared = _direct = null;
  }

  Uint8List _question({required bool unicast}) {
    final w = _Writer()
      ..header(response: false, questions: 1)
      ..name(_service)
      ..u16(_typePtr)
      ..u16(unicast ? 0x8001 : 1);
    return w.bytes();
  }

  Future<void> _query() async {
    final interfaces = await _interfaceAddresses();
    if (!_running) return;
    final shared = _shared, direct = _direct;
    if (shared != null) _sendToGroup(shared, interfaces, (_) => _question(unicast: false));
    if (direct != null) _sendToGroup(direct, interfaces, (_) => _question(unicast: true));
    // Forget servers that stopped answering.
    final limit = DateTime.now().subtract(const Duration(seconds: 45));
    final before = _found.length;
    _found.removeWhere((_, entry) => entry.seen.isBefore(limit));
    if (_found.length != before) _notify();
    // Ask quickly at first, then every ten seconds.
    final delay = _round < 3 ? Duration(seconds: 1 << _round) : const Duration(seconds: 10);
    _round++;
    _timer = Timer(delay, _query);
  }

  void _notify() => onChange([for (final entry in _found.values) entry.service]);

  void _onPacket(Datagram packet) {
    final message = DnsMessage.parse(packet.data);
    if (message == null || !message.isResponse) return;
    final suffix = '.${_service.toLowerCase()}';
    var changed = false;
    for (final record in message.records) {
      if (record.type != _typeSrv || !record.name.toLowerCase().endsWith(suffix)) continue;
      final key = record.name.toLowerCase();
      if (record.ttl == 0) {
        changed = _found.remove(key) != null || changed;
        continue;
      }
      // Prefer the address the record names; the sender's is the fallback
      // and is right whenever a machine announces itself.
      final address = message.records
          .where((r) => r.type == _typeA && r.name.toLowerCase() == record.target?.toLowerCase())
          .map((r) => r.address)
          .firstOrNull;
      final service = (
        name: record.name.substring(0, record.name.length - suffix.length),
        host: (address ?? packet.address).address,
        port: record.port!,
      );
      // A server on several networks answers once for each. Stay with the
      // address in use for as long as it keeps being confirmed.
      final known = _found[key];
      final now = DateTime.now();
      if (known != null &&
          known.service.port == service.port &&
          known.service.host != service.host &&
          now.difference(known.seen) < const Duration(seconds: 25)) {
        continue;
      }
      changed = changed || known?.service != service;
      _found[key] = (service: service, seen: now);
    }
    if (changed) _notify();
  }
}
