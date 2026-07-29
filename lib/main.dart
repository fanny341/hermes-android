import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/connection_manager.dart';
import 'core/services/termux_discovery.dart';
import 'core/screens/session_list_screen.dart';
import 'core/utils/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = ConnectionManager(prefs);
  runApp(HermesApp(connManager: connManager));
}

class HermesApp extends StatefulWidget {
  final ConnectionManager connManager;
  const HermesApp({required this.connManager, super.key});

  @override
  State<HermesApp> createState() => HermesAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString('theme_mode') ?? 'system';
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString('theme_mode', value);
  }
}

class HermesAppState extends State<HermesApp> {
  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return MaterialApp(
      title: 'Hermes Agent',
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A1A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.black,
        ),
      ),
      home: HomeScreen(connManager: widget.connManager),
    );
  }
}

/// Brand header used across screens.
class HermesHeader extends StatelessWidget {
  final String? subtitle;
  const HermesHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4AF37), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HERMES',
            style: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFD4AF37),
              letterSpacing: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ConnectionManager connManager;
  const HomeScreen({required this.connManager, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedConnection> _connections = [];
  bool _autoNavigated = false;
  bool _quickSetupShown = false;
  static const String _lastConnectionKey = 'last_connection_id';

  void _refresh() {
    setState(() => _connections = widget.connManager.getConnections());
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    } else if (!_quickSetupShown && _connections.isEmpty) {
      _quickSetupShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showQuickSetup();
      });
    }
  }

  /// Auto-navigate to the last used connection on app start.
  void _maybeAutoNavigate() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;
    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToSessions(conn);
    });
  }

  /// One-tap quick connect to the default/saved connection.
  void _quickConnect() {
    if (_connections.isEmpty) {
      _showQuickSetup();
      return;
    }
    // Use the first (or last-used) connection
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    final conn = lastId != null
        ? _connections.where((c) => c.id == lastId).firstOrNull
        : null;
    _navigateToSessions(conn ?? _connections.first);
  }

  /// First-time quick setup dialog — pre-filled with Termux defaults.
  void _showQuickSetup() {
    final labelCtrl = TextEditingController(text: 'Local Termux');
    final hostCtrl = TextEditingController(text: '127.0.0.1');
    final portCtrl = TextEditingController(text: '8642');
    final apiKeyCtrl = TextEditingController(text: 'xsLpZpZC9SmDOiVepaxC2ATqRhyqaYp55gLkxLOXt8U');
    final dashUserCtrl = TextEditingController(text: 'admin');
    final dashPassCtrl = TextEditingController(text: 'admin');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Setup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Connect to Hermes on this device.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label', hintText: 'My Hermes'),
              ),
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(labelText: 'Host', hintText: '127.0.0.1'),
              ),
              TextField(
                controller: portCtrl,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: apiKeyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              const SizedBox(height: 8),
              const Text('Dashboard (optional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              TextField(
                controller: dashUserCtrl,
                decoration: const InputDecoration(labelText: 'Username', hintText: 'admin'),
              ),
              TextField(
                controller: dashPassCtrl,
                decoration: const InputDecoration(labelText: 'Password', hintText: 'admin'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim().isEmpty ? 'Local Termux' : labelCtrl.text.trim();
              final host = hostCtrl.text.trim().isEmpty ? '127.0.0.1' : hostCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 8642;
              final apiKey = apiKeyCtrl.text.trim().isEmpty ? 'xsLpZpZC9SmDOiVepaxC2ATqRhyqaYp55gLkxLOXt8U' : apiKeyCtrl.text.trim();
              final dashUser = dashUserCtrl.text.trim().isEmpty ? null : dashUserCtrl.text.trim();
              final dashPass = dashPassCtrl.text.trim().isEmpty ? null : dashPassCtrl.text.trim();
              widget.connManager.saveConnection(
                label, host, port, apiKey,
                dashboardUsername: dashUser,
                dashboardPassword: dashPass,
              );
              _refresh();
              Navigator.pop(ctx);
              // Navigate to the newly created connection (first in list after refresh)
              final saved = widget.connManager.getConnections().isNotEmpty
                  ? widget.connManager.getConnections().first
                  : null;
              if (saved != null && mounted) {
                widget.connManager.prefs.setString(_lastConnectionKey, saved.id);
                _navigateToSessions(saved);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _navigateToSessions(SavedConnection conn) {
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SessionListScreen(connection: conn)),
    );
  }

  void _showAddDialog() => _showConnectionDialog();

  void _showScanDialog() {
    List<DiscoveredServer> found = [];
    String status = 'Starting…';
    bool scanning = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Start scan once
          if (scanning && found.isEmpty && status == 'Starting…') {
            scanning = false;
            final candidateKeys = _connections
                .map((c) => c.apiKey)
                .where((k) => k.isNotEmpty)
                .toList();
            TermuxDiscovery.scan(
              candidateKeys: candidateKeys,
              onProgress: (msg, count) {
                if (!ctx.mounted) return;
                setDialogState(() => status = msg);
              },
            ).then((results) {
              if (!ctx.mounted) return;
              setDialogState(() {
                found = results;
                status = 'Done — ${results.length} found';
                scanning = false;
              });
            });
          }

          return AlertDialog(
            title: const Text('Auto-Discover Hermes'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (found.isEmpty && status != 'Done — 0 found')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (found.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(Icons.wifi_off, size: 40, color: Colors.grey[500]),
                          const SizedBox(height: 8),
                          Text(
                            'No Hermes servers found on the local network.\n'
                            'Make sure the Hermes API server is running\n'
                            '(hermes gateway run) and on the same WiFi.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: found.length,
                        itemBuilder: (_, i) {
                          final s = found[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.router,
                                color: Color(0xFFD4AF37),
                                size: 20,
                              ),
                              title: Text(
                                s.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${s.host}:${s.port} • v${s.version}'
                                '${s.apiKey != null ? " • key ✓" : " • no key"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.grey[600],
                                ),
                              ),
                              trailing: s.apiKey != null
                                  ? const Icon(Icons.add_circle, color: Colors.green)
                                  : const Icon(Icons.key, color: Colors.orange),
                              onTap: () {
                                // Pre-fill the add dialog with discovered data
                                Navigator.pop(ctx);
                                _showConnectionDialog(
                                  discovered: s,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditConnectionDialog(SavedConnection conn) {
    _showConnectionDialog(existing: conn);
  }

  void _showConnectionDialog({SavedConnection? existing, DiscoveredServer? discovered}) {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        initialConnection: existing,
        discovered: discovered,
        onSave:
            (
              label,
              host,
              port,
              apiKey, {
              gatewayPrefix,
              dashboardPrefix,
              dashboardProxied = false,
              dashboardPort,
              dashboardUsername,
              dashboardPassword,
            }) {
              if (existing == null) {
                widget.connManager.saveConnection(
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              } else {
                widget.connManager.updateConnection(
                  existing.id,
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              }
              _refresh();
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: GoogleFonts.cinzel(
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    'No connections',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Quick Connect card
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Card(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                    child: ListTile(
                      leading: const Icon(Icons.wifi, color: Color(0xFFD4AF37)),
                      title: const Text('Quick Connect',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Tap to auto-connect to ${_connections.length} saved server${_connections.length > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _quickConnect,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (Responsive.isTablet(context)) {
                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.gridColumns(context),
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _connections.length,
                          itemBuilder: (_, i) =>
                              _buildConnectionCard(_connections[i]),
                        );
                      }
                      return ListView.builder(
                        itemCount: _connections.length,
                        itemBuilder: (_, i) =>
                            _buildConnectionCard(_connections[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'scan',
            tooltip: 'Auto-Discover Hermes Servers',
            onPressed: _showScanDialog,
            mini: true,
            child: const Icon(Icons.wifi_find),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            tooltip: 'Add Connection',
            onPressed: _showAddDialog,
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: Icon(
          Icons.dns,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(conn.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${conn.host}:${conn.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showEditConnectionDialog(conn),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: () {
                widget.connManager.deleteConnection(conn.id);
                _refresh();
              },
              tooltip: 'Delete',
            ),
          ],
        ),
        onTap: () => _navigateToSessions(conn),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final SavedConnection? initialConnection;
  final DiscoveredServer? discovered;
  final void Function(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
  })
  onSave;
  const _AddDialog({required this.onSave, this.initialConnection, this.discovered});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _apiKey;
  late final TextEditingController _gatewayPrefix;
  late final TextEditingController _dashboardPrefix;
  late final TextEditingController _dashPort;
  late final TextEditingController _dashUser;
  late final TextEditingController _dashPass;
  late bool _showDashboard;
  late bool _dashboardProxied;
  bool _validating = false;
  String? _error;

  bool get _isEditing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();
    final conn = widget.initialConnection;
    final disc = widget.discovered;
    _label = TextEditingController(text: conn?.label ?? disc?.label ?? 'Home');
    _host = TextEditingController(
      text: conn == null
          ? (disc != null
              ? (disc.useHttps ? 'https://${disc.host}' : disc.host)
              : '')
          : conn.useHttps
          ? 'https://${conn.host}'
          : conn.host,
    );
    _port = TextEditingController(
      text: (conn?.port ?? disc?.port ?? 8642).toString(),
    );
    _apiKey = TextEditingController(text: conn?.apiKey ?? disc?.apiKey ?? '');
    _gatewayPrefix = TextEditingController(text: conn?.gatewayPrefix ?? '');
    _dashboardPrefix = TextEditingController(text: conn?.dashboardPrefix ?? '');
    _dashPort = TextEditingController(
      text: conn?.dashboardPortOverride?.toString() ?? '',
    );
    _dashUser = TextEditingController(text: conn?.dashboardUsername ?? '');
    _dashPass = TextEditingController(text: conn?.dashboardPassword ?? '');
    _dashboardProxied = conn?.dashboardProxied ?? false;
    _showDashboard =
        conn?.gatewayPrefix?.isNotEmpty == true ||
        conn?.dashboardPrefix?.isNotEmpty == true ||
        conn?.dashboardPortOverride != null ||
        conn?.dashboardUsername?.isNotEmpty == true ||
        conn?.dashboardPassword?.isNotEmpty == true ||
        _dashboardProxied;
  }

  Future<void> _validateAndSave() async {
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8642;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

    if (label.isEmpty || host.isEmpty || port <= 0) return;

    setState(() {
      _validating = true;
      _error = null;
    });

    try {
      final normalized = SavedConnection.normalizeHostAndPort(host, port);
      final baseUrl = SavedConnection(
        id: '',
        label: '',
        host: normalized.host,
        port: normalized.port,
        apiKey: '',
        useHttps: normalized.useHttps,
      ).baseUrl;
      final client = ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pathPrefix: gatewayPrefix,
      );
      final ok = await client.healthCheck();
      client.close();

      if (!mounted) return;

      if (!ok) {
        setState(() {
          _error = apiKey.isEmpty
              ? 'Server requires an API key. Enter your API_SERVER_KEY.'
              : 'Invalid API key. Server returned 401.';
          _validating = false;
        });
        return;
      }

      final dashPortText = _dashPort.text.trim();
      final dashUser = _dashUser.text.trim();
      final dashPass = _dashPass.text.trim();
      final dashPort = dashPortText.isEmpty ? null : int.tryParse(dashPortText);

      // If the user supplied any dashboard details, validate them before saving
      // (parity with the Dashboard Login dialog). The gateway is already known
      // good at this point.
      if (dashPortText.isNotEmpty ||
          dashUser.isNotEmpty ||
          dashPass.isNotEmpty ||
          dashboardPrefix.isNotEmpty ||
          _dashboardProxied) {
        final dashClient = DashboardClient(
          host: normalized.host,
          port: SavedConnection(
            id: '',
            label: '',
            host: normalized.host,
            port: normalized.port,
            apiKey: '',
            useHttps: normalized.useHttps,
            dashboardPortOverride: dashPort,
          ).dashboardPort,
          useHttps: normalized.useHttps,
          pathPrefix: dashboardPrefix,
          proxied: _dashboardProxied,
          username: dashUser.isEmpty ? null : dashUser,
          password: dashPass.isEmpty ? null : dashPass,
        );
        try {
          await dashClient.getModelInfo();
        } catch (_) {
          dashClient.close();
          if (!mounted) return;
          setState(() {
            _error =
                'Gateway connected, but the dashboard could not be reached or '
                'authenticated. Check the dashboard details, or clear them to skip.';
            _validating = false;
            _showDashboard = true;
          });
          return;
        }
        dashClient.close();
        if (!mounted) return;
      }

      widget.onSave(
        label,
        host,
        port,
        apiKey,
        gatewayPrefix: gatewayPrefix.isEmpty ? null : gatewayPrefix,
        dashboardPrefix: dashboardPrefix.isEmpty ? null : dashboardPrefix,
        dashboardProxied: _dashboardProxied,
        dashboardPort: dashPort,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach $host:$port. Check the host and port.';
        _validating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit Gateway Connection' : 'Add Gateway Connection',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText:
                    '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net',
              ),
              keyboardType: TextInputType.text,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8642 (API Server)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'API_SERVER_KEY from ~/.hermes/.env',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _validating
                  ? null
                  : () => setState(() => _showDashboard = !_showDashboard),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showDashboard ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Custom proxy and dashboard details',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDashboard) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _gatewayPrefix,
                decoration: const InputDecoration(
                  labelText: 'Gateway path prefix',
                  hintText:
                      'e.g. /profile/peter (proxy path before /api/ and /v1/)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashboardPrefix,
                decoration: const InputDecoration(
                  labelText: 'Dashboard path prefix',
                  hintText: 'e.g. /dashboard (proxy path before /api/)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _dashboardProxied,
                contentPadding: EdgeInsets.zero,
                title: const Text('Dashboard behind proxy'),
                subtitle: const Text(
                  'Nginx injects auth — app sends clean requests',
                ),
                onChanged: (v) => setState(() => _dashboardProxied = v),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Optional. For the Memory/Cron/Skills/Settings tabs. Leave '
                  'blank to use the default dashboard port (9119) with no login.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              TextField(
                controller: _dashPort,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Port',
                  hintText: 'Leave blank for default (9119)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashUser,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Username (optional)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashPass,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Password (optional)',
                ),
                obscureText: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validating ? null : _validateAndSave,
          child: _validating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save Changes' : 'Connect'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    _gatewayPrefix.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    super.dispose();
  }
}
