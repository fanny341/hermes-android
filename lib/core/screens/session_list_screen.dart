import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connection_manager.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'memory_screen.dart';
import 'cron_screen.dart';
import 'skills_screen.dart';
import 'toolsets_screen.dart';
import 'runs_screen.dart';

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  const SessionListScreen({required this.connection, super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late final ApiClient _client;
  List<Session> _sessions = [];
  bool _loading = true;
  String? _error;
  bool _healthOk = false;
  final Set<String> _deletingSessionIds = {};
  Session? _selectedSession; // for master-detail layout

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    final ok = await _client.healthCheck();
    setState(() => _healthOk = ok);
    if (ok) _fetchSessions();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await _client.getSessions();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'excluded_session_sources_${widget.connection.id}';
      final excluded = prefs.getStringList(key) ?? [];
      final filtered =
          sessions.where((s) => !excluded.contains(s.source)).toList();
      if (!mounted) return;
      setState(() {
        _sessions = filtered;
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

  Future<void> _confirmDeleteSession(Session session) async {
    final title = session.title.trim().isEmpty
        ? 'Untitled session'
        : session.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'Delete "$title" from the remote Hermes history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSession(session);
    }
  }

  void _showSessionActions(Session session) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('Fork Session'),
              subtitle: const Text(
                'Create a branch from this session',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _forkSession(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteSession(session);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(Session session) {
    final ctrl = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Session name',
            hintText: 'Enter a new name',
          ),
          onSubmitted: (_) async {
            await _doRename(session, ctrl.text.trim(), ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _doRename(session, ctrl.text.trim(), ctx),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _doRename(
    Session session, String newTitle, BuildContext dialogCtx,
  ) async {
    if (newTitle.isEmpty) return;
    try {
      await _client.renameSession(session.id, newTitle);
      if (!context.mounted) return;
      setState(() {
        final idx = _sessions.indexWhere((s) => s.id == session.id);
        if (idx >= 0) {
          _sessions[idx] = Session(
            id: session.id,
            title: newTitle,
            model: session.model,
            source: session.source,
            messageCount: session.messageCount,
            isActive: session.isActive,
            preview: session.preview,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
          );
        }
      });
      Navigator.pop(dialogCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session renamed')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(dialogCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _forkSession(Session session) async {
    try {
      final result = await _client.forkSession(session.id);
      if (!mounted) return;
      final newId = result['id']?.toString() ?? result['session_id']?.toString() ?? '';
      if (newId.isNotEmpty) {
        final forked = Session(
          id: newId,
          title: '${session.title} (fork)',
          model: session.model,
          source: session.source,
          messageCount: 0,
          isActive: true,
          preview: 'Forked from ${session.title}',
          startedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
        );
        setState(() => _sessions.insert(0, forked));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forked → $newId')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fork failed: $e')),
      );
    }
  }

  Future<void> _deleteSession(Session session) async {
    if (_deletingSessionIds.contains(session.id)) return;
    setState(() => _deletingSessionIds.add(session.id));

    try {
      await _client.deleteSession(session.id);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((item) => item.id == session.id);
        _deletingSessionIds.remove(session.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session deleted from remote Hermes.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingSessionIds.remove(session.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete session: $e')));
    }
  }

  void _createNewSession() {
    final sessionId = GatewayChatClient.generateSessionId();
    final session = Session(
      id: sessionId,
      title: 'New Chat',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(connection: widget.connection, session: session),
      ),
    );
  }

  String _formatTime(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }

  void _openScreen(Widget screen) {
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
        actions: [
          if (!_healthOk)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchSessions,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Chat',
        onPressed: _createNewSession,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
      body: _buildMasterBody(),
    );
  }

  /// Body that adapts to master-detail layout on wide screens.
  Widget _buildMasterBody() {
    if (MediaQuery.of(context).size.width < 768 || _selectedSession == null) {
      return _buildBody();
    }
    // Master-detail: session list (left) + chat (right)
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: _buildBody(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ChatScreen(
            connection: widget.connection,
            session: _selectedSession!,
            onBack: () => setState(() => _selectedSession = null),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Brand header in drawer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HERMES',
                    style: GoogleFonts.cinzel(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AF37),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connection.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Memory'),
              onTap: () =>
                  _openScreen(MemoryScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Cron Jobs'),
              onTap: () =>
                  _openScreen(CronScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Skills'),
              onTap: () =>
                  _openScreen(SkillsScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: const Text('Toolsets'),
              onTap: () => _openScreen(
                ToolsetsScreen(connection: widget.connection),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text('Async Runs'),
              onTap: () => _openScreen(
                RunsScreen(connection: widget.connection),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () =>
                  _openScreen(SettingsScreen(connection: widget.connection)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_healthOk) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to ${widget.connection.baseUrl}...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the Gateway API Server is running\n(hermes gateway status)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _checkHealth, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Connection issue',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchSessions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to start a new chat',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          final isDeleting = _deletingSessionIds.contains(session.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              enabled: !isDeleting,
              leading: Icon(
                session.isActive ? Icons.chat : Icons.chat_bubble_outline,
                color: session.isActive ? const Color(0xFFD4AF37) : Colors.grey,
              ),
              trailing: isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              title: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session.messageCount} msgs \u2022 ${session.model} \u2022 ${_formatTime(session.startedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (session.preview.isNotEmpty)
                    Text(
                      session.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    ),
                ],
              ),
              isThreeLine: session.preview.isNotEmpty,
              onLongPress: isDeleting
                  ? null
                  : () => _showSessionActions(session),
              onTap: isDeleting
                  ? null
                  : () {
                      final wide = MediaQuery.of(context).size.width >= 768;
                      if (wide) {
                        setState(() {
                          _selectedSession = session;
                        });
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              connection: widget.connection,
                              session: session,
                            ),
                          ),
                        );
                      }
                    },
            ),
          );
        },
      ),
    );
  }
}
