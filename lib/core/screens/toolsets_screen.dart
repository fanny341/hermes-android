// Toolsets screen — list all Hermes toolsets with enabled/configured status.
// Uses the native API server endpoint GET /v1/toolsets (no dashboard needed).
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';

class ToolsetsScreen extends StatefulWidget {
  final SavedConnection connection;
  const ToolsetsScreen({required this.connection, super.key});

  @override
  State<ToolsetsScreen> createState() => _ToolsetsScreenState();
}

class _ToolsetsScreenState extends State<ToolsetsScreen> {
  late final ApiClient _client;
  List<Map<String, dynamic>> _toolsets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final toolsets = await _client.getToolsets();
      if (!mounted) return;
      setState(() {
        _toolsets = toolsets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount =
        _toolsets.where((t) => t['enabled'] == true).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Toolsets ($enabledCount/${_toolsets.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load toolsets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_toolsets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_outlined, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No toolsets found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'The agent has no tool capabilities configured.\n'
              'Enable toolsets via the dashboard or CLI.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _toolsets.length,
        itemBuilder: (_, i) {
          final ts = _toolsets[i];
          final name = ts['name'] as String? ?? 'unknown';
          final label = ts['label'] as String? ?? name;
          final desc = ts['description'] as String? ?? '';
          final enabled = ts['enabled'] as bool? ?? false;
          final configured = ts['configured'] as bool? ?? false;
          final tools = (ts['tools'] as List?)
                  ?.map((t) => t.toString())
                  .toList() ??
              [];

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              dense: true,
              leading: Icon(
                enabled
                    ? Icons.check_circle
                    : (configured ? Icons.pause_circle : Icons.block),
                color: enabled
                    ? Colors.green
                    : (configured ? Colors.orange : Colors.grey),
                size: 20,
              ),
              title: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '$name • ${tools.length} tool${tools.length == 1 ? "" : "s"}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey[600],
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (desc.isNotEmpty) ...[
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tools
                            .map(
                              (t) => Chip(
                                label: Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
