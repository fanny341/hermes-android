/// Termux / local-network auto-discovery for Hermes API servers.
///
/// The Hermes api_server doesn't broadcast itself, so we probe the standard
/// port (8642) on the local subnet. We also try a few common host candidates
/// (gateway IP, termux localhost, etc.) so a phone running Termux+Hermes can
/// be found with zero configuration.
///
/// Strategy:
/// 1. Try 127.0.0.1:8642 (Hermes running on this same device in Termux)
/// 2. Try the subnet broadcast — probe :8642 on every host in the /24
/// 3. Try common LAN gateways (.1, .100, .50, etc.)
///
/// Each probe hits /health (public, no auth) and optionally /v1/models with
/// a candidate key to confirm auth.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredServer {
  final String host;
  final int port;
  final bool useHttps;
  final String? apiKey; // non-null if we found a working key
  final String version;
  final String label;

  const DiscoveredServer({
    required this.host,
    required this.port,
    this.useHttps = false,
    this.apiKey,
    required this.version,
    required this.label,
  });

  @override
  String toString() =>
      'DiscoveredServer($label, $host:$port, v$version, key=${apiKey != null})';
}

typedef DiscoveryProgress = void Function(String message, int found);

class TermuxDiscovery {
  static const int _defaultPort = 8642;
  static const Duration _probeTimeout = Duration(milliseconds: 800);

  /// Scan for Hermes API servers on the local network.
  ///
  /// [candidateKeys] — API keys to try (e.g. previously saved keys, or a
  /// key the user pasted). If a server is found but no key validates, the
  /// server is still returned with apiKey=null.
  ///
  /// [onProgress] — called with status updates during the scan.
  static Future<List<DiscoveredServer>> scan({
    List<String> candidateKeys = const [],
    DiscoveryProgress? onProgress,
  }) async {
    final results = <DiscoveredServer>[];
    final seen = <String>{};

    // 1. Localhost (Termux on same device)
    onProgress?.call('Checking localhost…', results.length);
    final local = await _probe('127.0.0.1', _defaultPort, false, candidateKeys);
    if (local != null) {
      results.add(local);
      seen.add('127.0.0.1:${_defaultPort}');
    }

    // 2. Get local IP to determine subnet
    String? localIp;
    try {
      localIp = await _getLocalIp();
    } catch (_) {}

    if (localIp != null) {
      final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
      onProgress?.call('Scanning $subnet.0/24…', results.length);

      // Probe all 254 hosts in /24 concurrently (with timeout)
      final futures = <Future<DiscoveredServer?>>[];
      for (var i = 1; i <= 254; i++) {
        final host = '$subnet.$i';
        if (seen.contains('$host:$_defaultPort')) continue;
        futures.add(_probe(host, _defaultPort, false, candidateKeys));
      }

      // Wait for all, collect non-null results
      final found = await Future.wait(futures);
      for (final server in found) {
        if (server != null && !seen.contains('${server.host}:${server.port}')) {
          results.add(server);
          seen.add('${server.host}:${server.port}');
          onProgress?.call('Found: ${server.host}:${server.port}', results.length);
        }
      }
    }

    // 3. Common gateway/host candidates
    onProgress?.call('Checking common hosts…', results.length);
    final commonHosts = [
      '10.0.2.2', // Android emulator → host
      '192.168.1.1',
      '192.168.1.100',
      '192.168.0.1',
      '192.168.0.100',
    ];
    for (final host in commonHosts) {
      if (seen.contains('$host:$_defaultPort')) continue;
      final server = await _probe(host, _defaultPort, false, candidateKeys);
      if (server != null) {
        results.add(server);
        seen.add('${server.host}:${server.port}');
      }
    }

    onProgress?.call('Done — ${results.length} found', results.length);
    return results;
  }

  /// Probe a single host:port for a Hermes /health response.
  static Future<DiscoveredServer?> _probe(
    String host,
    int port,
    bool useHttps,
    List<String> candidateKeys,
  ) async {
    final scheme = useHttps ? 'https' : 'http';
    final base = '$scheme://$host:$port';

    try {
      final client = HttpClient();
      client.connectionTimeout = _probeTimeout;

      // Hit /health (public, no auth needed)
      final healthReq = await client.getUrl(Uri.parse('$base/health'));
      final healthRes = await healthReq.close();
      if (healthRes.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await healthRes.transform(utf8.decoder).join();
      client.close();

      Map<String, dynamic>? health;
      try {
        health = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }

      // Confirm it's Hermes
      final platform = health?['platform']?.toString() ?? '';
      if (!platform.contains('hermes')) return null;

      final version = health?['version']?.toString() ?? 'unknown';

      // Try candidate keys to find a working one
      String? workingKey;
      for (final key in candidateKeys) {
        if (key.isEmpty) continue;
        if (await _tryKey(host, port, useHttps, key)) {
          workingKey = key;
          break;
        }
      }

      return DiscoveredServer(
        host: host,
        port: port,
        useHttps: useHttps,
        apiKey: workingKey,
        version: version,
        label: _deriveLabel(host),
      );
    } catch (_) {
      return null;
    }
  }

  /// Test if an API key validates against the server.
  static Future<bool> _tryKey(
    String host,
    int port,
    bool useHttps,
    String apiKey,
  ) async {
    final scheme = useHttps ? 'https' : 'http';
    try {
      final client = HttpClient();
      client.connectionTimeout = _probeTimeout;
      final req = await client.getUrl(
        Uri.parse('$scheme://$host:$port/v1/models'),
      );
      req.headers.set('Authorization', 'Bearer $apiKey');
      final res = await req.close();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get the device's local IP by opening a UDP socket to a public DNS.
  static Future<String> _getLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
          return addr.address;
        }
      }
    }
    throw Exception('No IPv4 address found');
  }

  /// Derive a human-friendly label from the host IP.
  static String _deriveLabel(String host) {
    if (host == '127.0.0.1' || host == 'localhost') return 'This Device';
    if (host == '10.0.2.2') return 'Emulator Host';
    // Use last octet for brevity
    final parts = host.split('.');
    if (parts.length == 4) return 'LAN ${parts.last}';
    return host;
  }
}
