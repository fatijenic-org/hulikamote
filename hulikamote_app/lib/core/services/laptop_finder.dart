import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'cloud_portal_api.dart';
import 'portal_api.dart';

/// What the laptop tells the phone when it is found (backend: routers/pair.py). Public values only: the laptop's address and,
/// when the cloud is set up, the project address with its public "anon" key. No secret ever comes this way.
class PairInfo {
  const PairInfo({required this.address, this.cloudReady = false, this.cloudUrl = '', this.cloudAnonKey = ''});

  /// `192.168.68.109:8000`: the address that answered.
  final String address;
  final bool cloudReady;
  final String cloudUrl;
  final String cloudAnonKey;

  /// Null when [json] is not what a HULI-KAMOTE laptop answers.
  static PairInfo? fromJson(Map<String, dynamic> json, String answeredAt) {
    if (json['app'] != 'huli-kamote') return null;
    final ready = json['cloud_ready'] == true;
    return PairInfo(
      address: answeredAt,
      cloudReady: ready,
      cloudUrl: ready ? (json['cloud_url'] as String? ?? '') : '',
      cloudAnonKey: ready ? (json['cloud_anon_key'] as String? ?? '') : '',
    );
  }
}

/// How "Connect" went.
class ConnectResult {
  const ConnectResult({required this.ok, required this.message, this.online = false});

  final bool ok;

  /// True when the phone now uses the cloud, false when it uses the laptop on this Wi-Fi.
  final bool online;
  final String message;
}

/// "Connect": the phone looks for the laptop by itself (no address typed) and picks the right way in.
/// It looks at the networks the phone is on: the laptop it knew last time, the USB / emulator links, then every address of the
/// phone's own Wi-Fi, hotspot or tethering range (a quick look at port 8000). Nothing is changed on any network.
class LaptopFinder {
  LaptopFinder({
    Future<List<String>> Function()? phoneAddresses,
    Future<PairInfo?> Function(String host, int port)? probe,
    this.port = AppConfig.defaultPort,
    this.batch = 64,
  })  : _phoneAddresses = phoneAddresses ?? _readPhoneAddresses,
        _probe = probe ?? _probeHost;

  final Future<List<String>> Function() _phoneAddresses;
  final Future<PairInfo?> Function(String host, int port) _probe;
  final int port;

  /// How many addresses are looked at at the same time.
  final int batch;

  static const _openTimeout = Duration(milliseconds: 600);
  static const _askTimeout = Duration(seconds: 3);

  /// The phone's own private IPv4 addresses (Wi-Fi, hotspot, tethering). Mobile data is left out.
  static Future<List<String>> _readPhoneAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && isPrivate(a.address)) a.address
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool isPrivate(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.contains(null)) return false;
    return p[0] == 10 || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) || (p[0] == 192 && p[1] == 168);
  }

  static Future<PairInfo?> _probeHost(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: _openTimeout);
      socket.destroy();
    } catch (_) {
      return null;
    }
    try {
      final r = await http.get(Uri.parse('http://$host:$port/pair/config')).timeout(_askTimeout);
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body);
      return body is Map ? PairInfo.fromJson(Map<String, dynamic>.from(body), '$host:$port') : null;
    } catch (_) {
      return null;
    }
  }

  /// Where to look, in this order, without repeats: the laptop known from last time, the USB / emulator links, the usual
  /// gateway of each of the phone's networks (a laptop that shares its hotspot is the gateway), then the rest of the range.
  Future<List<String>> candidates({String lastKnown = ''}) async {
    final own = await _phoneAddresses();
    final prefixes = <String>{for (final ip in own) ip.substring(0, ip.lastIndexOf('.'))};
    final ordered = <String>[
      if (lastKnown.isNotEmpty) lastKnown,
      '127.0.0.1',
      '10.0.2.2',
      for (final p in prefixes) '$p.1',
      for (final p in prefixes)
        for (var n = 2; n <= 254; n++) '$p.$n',
    ];
    final seen = <String>{...own};
    return [
      for (final h in ordered)
        if (seen.add(h)) h
    ];
  }

  /// The first laptop that answers, or null.
  Future<PairInfo?> find({String lastKnownHost = ''}) async {
    final hosts = await candidates(lastKnown: lastKnownHost);
    for (var i = 0; i < hosts.length; i += batch) {
      final answers = await Future.wait(hosts.skip(i).take(batch).map((h) => _probe(h, port)));
      for (final info in answers) {
        if (info != null) return info;
      }
    }
    return null;
  }

  /// Find the laptop and set the phone up: the cloud when the laptop has it ready and this phone can reach it, else the laptop
  /// on this Wi-Fi. Saves what it learned in [AppConfig]. [checkCloud] is replaceable for tests.
  Future<ConnectResult> connect({Future<void> Function(String url, String anonKey)? checkCloud, bool preferCloud = true}) async {
    final last = AppConfig.address.split(':').first;
    final info = await find(lastKnownHost: last);
    if (info == null) {
      return const ConnectResult(
        ok: false,
        message: 'No laptop found. Check: 1) the backend is running on the laptop, 2) this phone is on the same Wi-Fi '
            '(or the laptop\'s hotspot), 3) press Connect again. You can also type the address below.',
      );
    }
    await AppConfig.save(info.address);
    if (preferCloud && info.cloudReady && await AppConfig.saveCloud(info.cloudUrl, info.cloudAnonKey)) {
      try {
        await (checkCloud ?? CloudPortalApi.checkProject)(info.cloudUrl, info.cloudAnonKey);
        await AppConfig.setMode('online');
        return const ConnectResult(ok: true, online: true, message: 'Connected through the cloud. It works anywhere there is internet.');
      } on PortalException {
        // this phone has no internet right now: use the laptop on the same Wi-Fi
      }
    }
    await AppConfig.setMode('lan');
    return ConnectResult(
      ok: true,
      message: info.cloudReady && preferCloud
          ? 'Connected to the laptop on this Wi-Fi (no internet on this phone, so not through the cloud).'
          : 'Connected to the laptop on this Wi-Fi. No internet needed.',
    );
  }
}
