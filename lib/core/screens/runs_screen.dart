// Runs screen — submit async agent runs, poll status, view output, stop.
// Uses POST /v1/runs, GET /v1/runs/{id}, POST /v1/runs/{id}/stop.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/connection_manager.dart';

class RunsScreen extends StatefulWidget {
  final SavedConnection connection;
  const RunsScreen({required this.connection, super.key});

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

class _RunEntry {
  final String runId;
  final String prompt;
  String status = 'started';
  String? output;
  String? error;
  final DateTime startedAt;

  _RunEntry({
    required this.runId,
    required this.prompt,
    required this.startedAt,
  });
}

class _RunsScreenState extends State<RunsScreen> {
  late final ApiClient _client;
  final _promptController = TextEditingController();
  final List<_RunEntry> _runs = [];
  bool _submitting = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _promptController.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _submitRun() async {
    final input = _promptController.text.trim();
    if (input.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final result = await _client.submitRun(input: input);
      final runId = result['run_id'] as String? ?? '';
      if (runId.isEmpty) throw Exception('No run_id in response');

      setState(() {
        _runs.insert(0, _RunEntry(
          runId: runId,
          prompt: input,
          startedAt: DateTime.now(),
        ));
        _promptController.clear();
        _submitting = false;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollAll());
  }

  Future<void> _pollAll() async {
    final active = _runs.where((r) =>
        r.status == 'started' || r.status == 'running').toList();
    if (active.isEmpty) {
      _pollTimer?.cancel();
      return;
    }
    for (final run in active) {
      try {
        final data = await _client.getRunStatus(run.runId);
        if (!mounted) return;
        setState(() {
          run.status = data['status'] as String? ?? run.status;
          if (run.status == 'completed') {
            run.output = data['output']?.toString();
          } else if (run.status == 'failed' || run.status == 'error') {
            run.error = data['error']?.toString() ??
                data['output']?.toString() ??
                'Unknown error';
          }
        });
      } catch (_) {}
    }
  }

  Future<void> _stopRun(_RunEntry run) async {
    try {
      await _client.stopRun(run.runId);
      if (!mounted) return;
      setState(() => run.status = 'stopped');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stop failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Async Runs')),
      body: Column(
        children: [
          _buildInput(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                hintText: 'Submit an async agent task',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onSubmitted: (_) => _submitRun(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _submitting ? null : _submitRun,
            icon: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_runs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text('No runs yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Submit a prompt above to start an async agent run.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _runs.length,
      itemBuilder: (_, i) => _buildRunCard(_runs[i]),
    );
  }

  Widget _buildRunCard(_RunEntry run) {
    final isActive = run.status == 'started' || run.status == 'running';
    final color = run.status == 'completed'
        ? Colors.green
        : run.status == 'failed' || run.status == 'error'
            ? Colors.red
            : run.status == 'stopped'
                ? Colors.orange
                : const Color(0xFFD4AF37);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        dense: true,
        leading: isActive
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.circle, color: color, size: 12),
        title: Text(
          run.prompt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${run.status} • ${run.runId.substring(0, 16)}…',
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color),
        ),
        trailing: isActive
            ? IconButton(
                icon: const Icon(Icons.stop, size: 18),
                onPressed: () => _stopRun(run),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (run.output != null && run.output!.isNotEmpty)
                  MarkdownBody(
                    data: run.output!,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 13),
                      code: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (run.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      run.error!,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  )
                else if (isActive)
                  const Text('Running…',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  Text('Status: ${run.status}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
