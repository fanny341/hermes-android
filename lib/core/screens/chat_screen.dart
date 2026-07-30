// Chat screen with real-time streaming via REST API.
// Uses REST endpoints: POST /api/sessions/{id}/chat and
// GET /api/sessions/{id}/messages.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/connection_manager.dart';
import 'settings_screen.dart';
import '../utils/message_content.dart';
import '../utils/responsive.dart';

class ChatScreen extends StatefulWidget {
  /// Per-session text field drafts (persisted in memory).
  static final Map<String, String> sessionDrafts = {};

  /// IDs of sessions currently streaming a response.
  static final Set<String> streamingSessions = {};

  final SavedConnection connection;
  final Session session;
  final VoidCallback? onBack; // optional: called in master-detail to return to list

  const ChatScreen({
    required this.connection,
    required this.session,
    this.onBack,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _toolMessages = [];
  bool _loading = true;
  String? _error;
  late final ApiClient _client;

  // Chat sending state
  final _textController = TextEditingController();
  bool _sending = false;
  bool _streaming = false;
  bool _thinking = false; // true while waiting for first token
  GatewayChatClient? _activeChatClient;

  // Background reconnect
  bool _wasBackgrounded = false;
  String? _retryMessage;
  bool _showRetryBanner = false;
  String? _lastSentMessage;

  // Model info from dashboard
  DashboardClient? _dashboardClient;
  int? _modelContextLength;
  List<String> _availableProviders = [];
  Map<String, List<Map<String, dynamic>>> _providerModels = {};
  String _selectedProvider = '';
  String _selectedModel = '';

  // Plan mode toggle
  bool _planMode = false;

  // Voice input / spoken replies
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechAvailable = false;
  bool _listening = false;
  bool _voiceReplyEnabled = true;
  bool _awaitingVoiceReply = false;
  String? _voiceStatus;
  String? _sttLocaleId;

  // Verbose mode
  bool _verboseMode = false;

  // Scroll management
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
    _fetchMessages();
    _loadVerboseMode();
    _initVoice();
    WidgetsBinding.instance.addObserver(this);
    _initModelInfo();
    // Restore draft text if available
    final saved = ChatScreen.sessionDrafts[widget.session.id];
    if (saved != null && saved.isNotEmpty) {
      _textController.text = saved;
    }
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    ChatScreen.sessionDrafts[widget.session.id] = _textController.text;
  }

  Future<void> _initModelInfo() async {
    _dashboardClient = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? '',
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
    );
    try {
      final results = await Future.wait([
        _dashboardClient!.getModelInfo(),
        _dashboardClient!.getModelOptions(),
      ]);
      final info = results[0];
      final options = results[1];
      if (mounted) {
        setState(() {
          _modelContextLength = info['effective_context_length'] as int?;
          _selectedProvider = (info['provider'] as String?) ?? '';
          _selectedModel = (info['model'] as String?) ?? '';
          _parseModelOptions(options);
        });
      }
    } catch (_) {
      // Non-critical — info bar falls back to just the model name
    }
  }

  void _parseModelOptions(Map<String, dynamic> options) {
    final providers = options['providers'] as List<dynamic>? ?? [];
    _availableProviders = [];
    _providerModels = {};
    for (final p in providers) {
      if (p is! Map<String, dynamic>) continue;
      final pMap = p;
      final providerId =
          (pMap['slug'] as String?) ?? (pMap['id'] as String?) ?? '';
      final rawModels = pMap['models'] as List<dynamic>? ?? [];
      if (providerId.isEmpty || rawModels.isEmpty) continue;
      _availableProviders.add(providerId);
      _providerModels[providerId] = rawModels
          .map((m) {
            if (m is String) return {'id': m, 'name': m};
            if (m is Map<String, dynamic>) return m;
            return <String, dynamic>{};
          })
          .where((m) => m['id'] != null && (m['id'] as String).isNotEmpty)
          .toList();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wasBackgrounded && _streaming) {
        _retryMessage = _lastSentMessage;
        // Auto-retry immediately without waiting for user tap
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _retryMessage != null) {
            final msg = _retryMessage!;
            _retryMessage = null;
            _textController.text = msg;
            _sendMessage();
          }
        });
      }
      _wasBackgrounded = false;
    }
  }

  Future<void> _loadVerboseMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _verboseMode = prefs.getBool('verbose_mode') ?? false);
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
    // Don't abort active stream — let it complete in background so the
    // server saves the response. Messages reload via _fetchMessages()
    // when the user reopens this session.
    _activeChatClient = null;
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _client.close();
    ChatScreen.streamingSessions.remove(widget.session.id);
    super.dispose();
  }

  Future<void> _initVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceName = prefs.getString('voice_name');
      final voiceLocale = prefs.getString('voice_locale');

      if (voiceName != null && voiceName.isNotEmpty) {
        if (voiceName == voiceLocale) {
          await _flutterTts.setLanguage(voiceName);
        } else {
          await _flutterTts.setVoice({
            'name': voiceName,
            'locale': voiceLocale ?? '',
          });
        }
        _sttLocaleId = voiceLocale?.replaceAll('-', '_');
      } else {
        _sttLocaleId = null;
      }
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      final available = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _voiceStatus = available ? null : 'Speech recognition is unavailable';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _voiceStatus = 'Voice setup failed: $e';
      });
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    final listening = status == 'listening';
    setState(() {
      _listening = listening;
      if (!listening && status == 'done') {
        _voiceStatus = null;
      }
    });
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceStatus = error.errorMsg;
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_streaming || _sending || _loading) return;
    if (_listening) {
      await _speechToText.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      await _initVoice();
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _voiceStatus ?? 'Speech recognition is unavailable',
              ),
            ),
          );
        }
        return;
      }
    }

    await _flutterTts.stop();
    if (!mounted) return;
    setState(() => _voiceStatus = 'Listening…');
    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: _sttLocaleId,
      ),
      onResult: _handleSpeechResult,
    );
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final recognised = result.recognizedWords.trim();
    if (recognised.isEmpty || !mounted) return;
    setState(() {
      _textController.text = recognised;
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
    });
    if (result.finalResult) {
      _sendMessage(speakResponse: true);
    }
  }

  Future<void> _speakAssistantText(String text) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty || !_voiceReplyEnabled) return;
    await _flutterTts.stop();
    await _flutterTts.speak(spokenText);
  }

  Future<void> _fetchMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final messages = await _client.getMessages(widget.session.id);
      if (!mounted) return;
      _extractToolMessages(messages);
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        setState(() {
          _messages = [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = errStr;
        _loading = false;
      });
    }
  }

  void _extractToolMessages(List<Map<String, dynamic>> messages) {
    _toolMessages.clear();
    for (final msg in messages) {
      if (!isToolResultMessage(msg)) continue;

      final name =
          (msg['name'] as String?) ??
          (msg['tool_name'] as String?) ??
          (msg['toolCallName'] as String?) ??
          '';
      final toolCallId = (msg['tool_call_id'] as String?) ?? '';
      final content = messageContentToText(msg['content']);

      String toolName = name.isNotEmpty ? name : '';
      if (toolName.isEmpty && content.isNotEmpty) {
        final match = RegExp(r'source="([^"]+)"').firstMatch(content);
        if (match != null) toolName = match.group(1)!;
      }
      if (toolName.isEmpty) toolName = 'tool';

      final emoji = _toolEmoji(toolName);
      _toolMessages.add({
        'role': 'tool_progress',
        'content': '$emoji $toolName — done',
        'toolCallId': toolCallId,
        'status': 'completed',
        'tool': toolName,
      });
    }
  }

  String _toolEmoji(String toolName) {
    switch (toolName) {
      case 'browser_navigate':
      case 'browser_console':
      case 'browser':
        return '🌐';
      case 'read_file':
      case 'read':
        return '📄';
      case 'write_file':
      case 'write':
        return '✏️';
      case 'search':
      case 'google_search':
        return '🔍';
      case 'execute':
      case 'shell':
        return '💻';
      case 'think':
      case 'reasoning':
        return '🧠';
      default:
        return '🔧';
    }
  }

  /// Send message via SSE streaming (Gateway API Server).
  Future<void> _sendMessage({bool speakResponse = false}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_sending || _streaming) return;

    _textController.text = '';
    _lastSentMessage = text;
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;

    // Build conversation history for SSE request
    final history = <Map<String, dynamic>>[];
    if (_planMode) {
      history.add({
        'role': 'system',
        'content': 'You are in PLAN MODE. Before answering, first create a '
            'clear step-by-step plan. Think through the problem methodically '
            'and show your reasoning step by step, then provide the final answer.',
      });
    }
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      history.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
    }

    setState(() {
      _sending = true;
      _streaming = true;
      _thinking = true;
      ChatScreen.streamingSessions.add(widget.session.id);
      _messages.add({'role': 'user', 'content': text});
      // Insert a placeholder streaming message
      _messages.add({'role': 'assistant', 'content': ''});
      // Cap message history to prevent memory bloat
      if (_messages.length > 200) {
        final systemMsgs = _messages.where((m) => m['role'] == 'system').toList();
        final recentMsgs = _messages.reversed
            .take(200 - systemMsgs.length)
            .toList()
            .reversed
            .toList();
        _messages = [...systemMsgs, ...recentMsgs];
      }
    });

    // Accumulate tokens into the streaming placeholder
    final client = GatewayChatClient(_client);
    _activeChatClient = client;
    await client.sendMessageStreaming(
      message: text,
      sessionId: widget.session.id,
      history: history,
      tools: _planMode ? [] : null,
      onToken: (token) {
        if (!mounted) return;
        setState(() {
          _thinking = false;
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.last['content'] =
                (_messages.last['content'] as String) + token;
          }
        });
      },
      onToolProgress: (progress) {
        if (!mounted) return;
        _upsertToolProgress(progress);
      },
      onDone: () async {
        if (!mounted) return;
        setState(() => _thinking = false);
        // Refresh messages to get the final server-side state
        try {
          final messages = await _client.getMessages(widget.session.id);
          if (!mounted) return;
          _extractToolMessages(messages);
          setState(() {
            _messages = messages;
            _streaming = false;
            _sending = false;
          });
          ChatScreen.streamingSessions.remove(widget.session.id);
          if (_awaitingVoiceReply) {
            _awaitingVoiceReply = false;
            final assistant = messages.reversed.firstWhere(
              (message) => message['role'] == 'assistant',
              orElse: () => const <String, dynamic>{},
            );
            final assistantText = assistant['content']?.toString();
            if (assistantText != null) {
              await _speakAssistantText(assistantText);
            }
          }
        } catch (e) {
          setState(() {
            _streaming = false;
            _sending = false;
          });
          ChatScreen.streamingSessions.remove(widget.session.id);
        }
      },
      onError: (error) {
        if (!mounted) return;
        // If the stream was lost due to app backgrounding, show retry
        if (_retryMessage != null) {
          setState(() {
            _streaming = false;
            _sending = false;
            _thinking = false;
            _showRetryBanner = true;
          });
          ChatScreen.streamingSessions.remove(widget.session.id);
          return;
        }
        // Remove the placeholder assistant message
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
        _handleSendError(text, error);
      },
    );
  }

  void _regenerateLast() {
    if (_messages.isEmpty || _streaming) return;
    // Find the last user message
    Map<String, dynamic>? lastUserMsg;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'user') {
        lastUserMsg = _messages[i];
        break;
      }
    }
    if (lastUserMsg == null) return;
    // Remove the last assistant message (if any)
    if (_messages.last['role'] == 'assistant') {
      setState(() => _messages.removeLast());
    }
    // Re-send from the last user message
    final text = messageContentToText(lastUserMsg['content']);
    _textController.text = text;
    _sendMessage();
  }

  void _handleSendError(String text, Object e) {
    setState(() {
      _sending = false;
      _streaming = false;
      _thinking = false;
      _error = 'Send failed: $e';
      if (_messages.isNotEmpty &&
          _messages.last['role'] == 'user' &&
          _messages.last['content'] == text) {
        _messages.removeLast();
      }
    });
    ChatScreen.streamingSessions.remove(widget.session.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _upsertToolProgress(Map<String, dynamic> progress) {
    final toolCallId =
        progress['toolCallId']?.toString() ??
        progress['tool_call_id']?.toString() ??
        progress['id']?.toString() ??
        '';
    final tool = progress['tool']?.toString() ?? 'tool';
    final status = progress['status']?.toString() ?? 'running';
    final emoji = progress['emoji']?.toString() ?? '🔧';
    final label = progress['label']?.toString();
    final display = label == null || label.isEmpty ? tool : label;
    final done = status == 'completed' || status == 'finished';
    final content = done
        ? '$emoji $display — done'
        : '$emoji $display — $status';

    setState(() {
      final idx = toolCallId.isEmpty
          ? -1
          : _toolMessages.indexWhere((m) => m['toolCallId'] == toolCallId);
      final payload = {
        'role': 'tool_progress',
        'content': content,
        'toolCallId': toolCallId,
        'status': status,
        'tool': tool,
      };
      if (idx >= 0) {
        _toolMessages[idx] = payload;
      } else {
        _toolMessages.add(payload);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
        title: Text(
          widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Plan mode toggle
          IconButton(
            icon: Icon(
              _planMode ? Icons.psychology : Icons.psychology_outlined,
              color: _planMode ? const Color(0xFFD4AF37) : null,
            ),
            onPressed: () => setState(() => _planMode = !_planMode),
            tooltip: _planMode ? 'Plan mode ON' : 'Plan mode OFF',
          ),
          if (_streaming)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () {
                _activeChatClient?.abort();
                setState(() {
                  _sending = false;
                  _streaming = false;
                  _thinking = false;
                });
                ChatScreen.streamingSessions.remove(widget.session.id);
              },
              tooltip: 'Stop generating',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _fetchMessages,
              tooltip: 'Refresh',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'verbose') {
                final prefs = await SharedPreferences.getInstance();
                final newVal = !_verboseMode;
                await prefs.setBool('verbose_mode', newVal);
                setState(() => _verboseMode = newVal);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'verbose',
                child: Row(
                  children: [
                    Checkbox(
                      value: _verboseMode,
                      onChanged: null,
                    ),
                    const Text('Debug metadata'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Loading bar — visible only during streaming
          if (_streaming)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          // Retry banner when connection was lost due to backgrounding
          if (_showRetryBanner)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: Colors.orange.shade50,
              leading: const Icon(Icons.wifi_off, color: Colors.orange),
              content: const Text('Connection was interrupted.'),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _showRetryBanner = false);
                    if (_retryMessage != null) {
                      final msg = _retryMessage!;
                      _retryMessage = null;
                      _textController.text = msg;
                      _sendMessage();
                    }
                  },
                  child: const Text('RETRY'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showRetryBanner = false;
                      _retryMessage = null;
                    });
                  },
                  child: const Text('DISMISS'),
                ),
              ],
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.isTablet(context) ? 800 : double.infinity,
                ),
                child: Column(
                  children: [
                    // Inline error banner for send errors (messages still visible)
                    if (_error != null && _messages.isNotEmpty)
                      MaterialBanner(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: const Icon(Icons.warning_amber, color: Colors.orange),
                        content: Text(_error!, style: const TextStyle(fontSize: 13)),
                        backgroundColor: Colors.orange.withValues(alpha: 0.12),
                        actions: [
                          TextButton(
                            onPressed: () => setState(() => _error = null),
                            child: const Text('DISMISS'),
                          ),
                        ],
                      ),
                      Expanded(
                      child: _buildBody(),
                      ),
                      // Session info bar — above input, always visible while typing
                      _buildSessionInfoBar(),
                      _buildInputBar(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionInfoBar() {
    // Show newly selected model if set, otherwise fall back to session default
    final model = _selectedModel.isNotEmpty ? _selectedModel : widget.session.model;
    final msgCount = _messages.length;
    final tokens = _messages.fold<int>(0, (sum, m) {
      final c = m['content'];
      if (c is String) return sum + c.length ~/ 4;
      return sum;
    });
    final ctxLimit = _modelContextLength;
    final ctxText = ctxLimit != null
        ? '~${tokens}k / ${ctxLimit ~/ 1000}K'
        : '~${tokens}k';

    // Respect the app's text color (dark/light theme)
    final textColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey.shade700;
    final mutedColor = textColor.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: () => _showModelPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.model_training, size: 12, color: mutedColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                model,
                style: TextStyle(fontSize: 11, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.message, size: 11, color: mutedColor),
            const SizedBox(width: 2),
            Text('$msgCount',
                style: TextStyle(fontSize: 10, color: textColor)),
            const SizedBox(width: 8),
            Icon(Icons.token, size: 11, color: mutedColor),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                ctxText,
                style: TextStyle(fontSize: 10, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 13, color: mutedColor),
          ],
        ),
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    if (_availableProviders.isEmpty) {
      // Fallback: open Settings if no model data loaded yet
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsScreen(connection: widget.connection),
        ),
      );
      return;
    }
    String tempProvider = _selectedProvider;
    String tempModel = _selectedModel;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Change Model'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Provider dropdown
                DropdownButton<String>(
                  value: _availableProviders.contains(tempProvider)
                      ? tempProvider
                      : (_availableProviders.isNotEmpty
                          ? _availableProviders.first
                          : null),
                  isExpanded: true,
                  underline: const SizedBox(),
                  hint: const Text('Select provider'),
                  items: _availableProviders.map((p) {
                    return DropdownMenuItem(value: p, child: Text(p));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDState(() {
                        tempProvider = val;
                        final models = _providerModels[val] ?? [];
                        if (models.isNotEmpty) {
                          tempModel = models.first['id'] as String;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                // Model dropdown
                DropdownButton<String>(
                  value: _providerModels[tempProvider]
                          ?.any((m) => m['id'] == tempModel) ==
                      true
                      ? tempModel
                      : null,
                  isExpanded: true,
                  underline: const SizedBox(),
                  hint: const Text('Select model'),
                  items: (_providerModels[tempProvider] ?? [])
                      .map((m) => DropdownMenuItem(
                            value: m['id'] as String,
                            child: Text(m['name'] as String? ?? m['id'] as String),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDState(() => tempModel = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () async {
                if (tempProvider.isEmpty || tempModel.isEmpty) return;
                final dialogCtx = context;
                try {
                  await _dashboardClient!.setModel(
                    'main',
                    tempProvider,
                    tempModel,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  // Update local state immediately
                  if (mounted) {
                    setState(() {
                      _selectedProvider = tempProvider;
                      _selectedModel = tempModel;
                    });
                  }
                  // Refresh model info from dashboard (non-blocking for UI)
                  _initModelInfo();
                } catch (e) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
              child: const Text('APPLY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.1)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                enabled: !_loading && !_streaming,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: Icon(_listening ? Icons.mic_off : Icons.mic),
              color: _listening ? Theme.of(context).colorScheme.error : null,
              onPressed: (!_loading && !_streaming && !_sending)
                  ? _toggleVoiceInput
                  : null,
              tooltip: _listening ? 'Stop listening' : 'Speak to Hermes',
            ),
            IconButton(
              icon: Icon(
                _voiceReplyEnabled ? Icons.volume_up : Icons.volume_off,
              ),
              onPressed: () {
                setState(() => _voiceReplyEnabled = !_voiceReplyEnabled);
                if (!_voiceReplyEnabled) {
                  _flutterTts.stop();
                }
              },
              tooltip: _voiceReplyEnabled
                  ? 'Spoken replies on'
                  : 'Spoken replies off',
            ),
            const SizedBox(width: 4),
            CircleAvatar(
              child: _streaming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: _sendMessage,
                      tooltip: 'Send',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load messages',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchMessages,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Build display list: consecutive tool messages grouped into cards,
    // interleaved with user/assistant bubbles.
    final toolQueue = List<Map<String, dynamic>>.from(_toolMessages);
    final displayMessages = <dynamic>[];
    final currentGroup = <Map<String, dynamic>>[];

    for (final msg in _messages) {
      final role = (msg['role'] as String?) ?? 'assistant';
      if (isToolResultMessage(msg)) {
        if (toolQueue.isNotEmpty) {
          currentGroup.add(toolQueue.removeAt(0));
        }
        continue;
      }
      if (role != 'user' && role != 'assistant') continue;
      final content = stripToolResultText(messageContentToText(msg['content']));
      // Keep empty assistant messages when thinking (streaming placeholder)
      if (content.isEmpty && !(role == 'assistant' && _thinking)) continue;

      if (currentGroup.isNotEmpty) {
        displayMessages.add(currentGroup.toList());
        currentGroup.clear();
      }
      displayMessages.add({...msg, '_display_content': content});
    }
    if (currentGroup.isNotEmpty) {
      displayMessages.add(currentGroup.toList());
    }

    // Show thinking indicator if streaming but no content yet
    if (_thinking) {
      displayMessages.add('__thinking__');
    }

    // Tools from SSE events that arrived during streaming but haven't been
    // matched to server messages yet — show them as a card.
    if (toolQueue.isNotEmpty) {
      displayMessages.add(toolQueue.toList());
    }

    // Reverse for ListView.reverse: true — newest items at index 0 (bottom)
    final reversed = displayMessages.reversed.toList();

    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: reversed.length,
      itemBuilder: (context, index) {
        final item = reversed[index];

        if (item is String && item == '__thinking__') {
          return _buildThinkingIndicator();
        }

        if (item is List<Map<String, dynamic>>) {
          return _ToolProgressCard(items: item, verbose: _verboseMode);
        }

        final msg = item as Map<String, dynamic>;
        final role = (msg['role'] as String?) ?? 'assistant';
        final content =
            (msg['_display_content'] as String?) ??
            stripToolResultText(messageContentToText(msg['content']));
        final isUser = role == 'user';
        final isLastAssistant = index == 0 && role == 'assistant' && !_streaming;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MessageBubble(
              content: content,
              isUser: isUser,
              verbose: _verboseMode,
              metadata: msg,
            ),
            // Regenerate button below the last assistant message
            if (isLastAssistant)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2, bottom: 4),
                child: TextButton.icon(
                  onPressed: _regenerateLast,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Regenerate', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Animated thinking indicator shown while waiting for the first token.
  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Thinking…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool verbose;
  final Map<String, dynamic> metadata;

  const _MessageBubble({
    required this.content,
    required this.isUser,
    this.verbose = false,
    this.metadata = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Bubble colors
    final userBubbleColor = const Color(0xFFD4AF37);
    final assistantBubbleColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFEAEAEA);
    final assistantTextColor = isDark ? Colors.white : Colors.black87;

    // Collect extra metadata for verbose mode
    final List<String> metaLines = [];
    if (verbose) {
      final role = (metadata['role'] as String?) ?? 'unknown';
      metaLines.add('role: $role');
      // Show any extra fields that aren't role/content
      for (final entry in metadata.entries) {
        if (entry.key == 'role' || entry.key == 'content') continue;
        final value = entry.value?.toString() ?? 'null';
        if (value.length > 80) {
          metaLines.add('${entry.key}: ${value.substring(0, 80)}…');
        } else {
          metaLines.add('${entry.key}: $value');
        }
      }
    }

    final bubble = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? userBubbleColor : assistantBubbleColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Verbose metadata header
          if (metaLines.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isUser ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: metaLines
                    .map(
                      (line) => Text(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.8)
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          // Message content
          MarkdownBody(
            data: content,
            styleSheet: MarkdownStyleSheet(
              p: (isUser
                  ? theme.textTheme.bodyMedium?.copyWith(color: Colors.white)
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: assistantTextColor,
                    )),
              code: TextStyle(
                backgroundColor: (isUser ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
                fontFamily: 'monospace',
                color: isUser ? Colors.white : null,
              ),
              a: TextStyle(
                color: isUser ? Colors.white70 : theme.colorScheme.primary,
              ),
              h1: isUser
                  ? theme.textTheme.headlineSmall?.copyWith(color: Colors.white)
                  : theme.textTheme.headlineSmall,
              h2: isUser
                  ? theme.textTheme.titleLarge?.copyWith(color: Colors.white)
                  : theme.textTheme.titleLarge,
              h3: isUser
                  ? theme.textTheme.titleMedium?.copyWith(color: Colors.white)
                  : theme.textTheme.titleMedium,
              blockquote: TextStyle(
                color: isUser ? Colors.white60 : Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isUser ? Colors.white38 : theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              em: isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              strong: isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: bubble,
        ),
      ],
    );
  }
}

class _ToolProgressCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool verbose;

  const _ToolProgressCard({required this.items, this.verbose = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEAEAEA);
    final fg = isDark ? Colors.white70 : Colors.black54;

    final active = items.any((item) {
      final status = (item['status'] as String?) ?? '';
      return status != 'completed' && status != 'finished';
    });

    final emojis = items.map((item) {
      final content = (item['content'] as String?) ?? '';
      return content.isNotEmpty
          ? content.substring(0, content.length < 2 ? content.length : 2)
          : '\uD83D\uDD27';
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            active ? '\u23F3' : '\u2705',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 6),
          Text(emojis.join(' '), style: const TextStyle(fontSize: 13)),
          if (active)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}
