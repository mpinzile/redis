import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/l10n/l10n_helper.dart';

/// Live Chat screen - matches web LiveChat.tsx using /support/chat/* endpoints
/// Resumes active chat sessions instead of creating new ones each time.
class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _chatId;
  List<Map<String, dynamic>> _messages = [];
  bool _starting = true;
  bool _sending = false;
  bool _ended = false;
  Timer? _pollTimer;

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary, double height = 1.3}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Try to resume an active chat before creating a new one
  Future<void> _initChat() async {
    setState(() => _starting = true);
    try {
      // Check for an existing active chat stored locally
      final prefs = await SharedPreferences.getInstance();
      final savedChatId = prefs.getString('live_chat_session_id');

      if (savedChatId != null && savedChatId.isNotEmpty) {
        // Try to resume by fetching messages from the correct endpoint
        final headers = await _headers();
        final res = await http.get(
          Uri.parse('${ApiService.baseUrl}/support/chat/$savedChatId/messages'),
          headers: headers,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final respData = data['data'] ?? data;
          final status = respData['session_status']?.toString() ?? '';
          if (status != 'ended' && status != 'closed') {
            // Resume this session
            _chatId = savedChatId;
            _messages = [
              {
                'id': 'welcome',
                'content': "Hello! Welcome to Nuru Support. An agent will respond shortly. How can we help you today?",
                'sender': 'system',
                'sent_at': DateTime.now().toIso8601String(),
              },
            ];
            final msgs = respData['messages'];
            if (msgs is List) {
              for (final m in msgs) {
                if (m is! Map) continue;
                _messages.add({
                  'id': m['id']?.toString() ?? '',
                  'content': m['content']?.toString() ?? m['message_text']?.toString() ?? '',
                  'sender': m['sender']?.toString() ?? (m['is_agent'] == true ? 'agent' : (m['is_system'] == true ? 'system' : 'user')),
                  'sender_name': m['sender_name']?.toString(),
                  'sent_at': m['sent_at']?.toString() ?? m['created_at']?.toString() ?? '',
                });
              }
            }
            _startPolling();
            if (mounted) setState(() => _starting = false);
            return;
          } else {
            // Session ended, clear it
            await prefs.remove('live_chat_session_id');
          }
        } else {
          await prefs.remove('live_chat_session_id');
        }
      }

      // No active session - start a new one
      await _startNewChat();
    } catch (_) {
      await _startNewChat();
    }
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _startNewChat() async {
    try {
      final headers = await _headers();
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/support/chat/start'),
        headers: headers,
        body: jsonEncode({'initial_message': 'Hello, I need help.'}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final sessionData = data['data'] ?? data;
        final chatId = sessionData['session_id']?.toString() ??
            sessionData['chat_id']?.toString() ??
            sessionData['id']?.toString();

        if (chatId != null && chatId.isNotEmpty) {
          _chatId = chatId;
          // Save session for resume
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('live_chat_session_id', chatId);

          _messages = [
            {
              'id': 'welcome',
              'content': "Hello! Welcome to Nuru Support. An agent will respond shortly. How can we help you today?",
              'sender': 'system',
              'sent_at': DateTime.now().toIso8601String(),
            }
          ];
          _startPolling();
        }
      }
    } catch (_) {}
  }

  void _parseSessionMessages(Map<String, dynamic> sessionData) {
    final msgs = sessionData['messages'] ?? [];
    _messages = [
      {
        'id': 'welcome',
        'content': "Hello! Welcome to Nuru Support. An agent will respond shortly. How can we help you today?",
        'sender': 'system',
        'sent_at': DateTime.now().toIso8601String(),
      },
    ];
    if (msgs is List) {
      for (final m in msgs) {
        if (m is! Map) continue;
        _messages.add({
          'id': m['id']?.toString() ?? '',
          'content': m['content']?.toString() ?? m['message_text']?.toString() ?? '',
          'sender': m['sender_type'] == 'agent' || m['is_agent'] == true
              ? 'agent'
              : (m['sender_type'] == 'system' || m['is_system'] == true ? 'system' : 'user'),
          'sender_name': m['sender_name']?.toString(),
          'sent_at': m['created_at']?.toString() ?? m['sent_at']?.toString() ?? '',
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchMessages());
  }

  Future<void> _fetchMessages() async {
    if (_chatId == null) return;
    try {
      final headers = await _headers();
      // Use the same /messages endpoint as web, with ?after= for incremental polling
      String url = '${ApiService.baseUrl}/support/chat/$_chatId/messages';
      if (_messages.isNotEmpty) {
        final lastSentAt = _messages.last['sent_at']?.toString() ?? '';
        if (lastSentAt.isNotEmpty) {
          url += '?after=${Uri.encodeComponent(lastSentAt)}';
        }
      }
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = jsonDecode(res.body);
      final respData = data['data'] ?? data;
      final status = respData['session_status']?.toString() ?? '';

      if (status == 'ended' || status == 'closed') {
        _pollTimer?.cancel();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('live_chat_session_id');
        if (mounted) setState(() => _ended = true);
        return;
      }

      final msgs = respData['messages'];
      if (msgs is List && msgs.isNotEmpty && mounted) {
        final existingIds = _messages.map((m) => m['id']?.toString()).toSet();
        final newMsgs = msgs.where((m) => m is Map && !existingIds.contains(m['id']?.toString())).toList();
        if (newMsgs.isNotEmpty) {
          for (final m in newMsgs) {
            if (m is! Map) continue;
            _messages.add({
              'id': m['id']?.toString() ?? '',
              'content': m['content']?.toString() ?? m['message_text']?.toString() ?? '',
              'sender': m['sender']?.toString() ?? (m['is_agent'] == true ? 'agent' : (m['is_system'] == true ? 'system' : 'user')),
              'sender_name': m['sender_name']?.toString(),
              'sent_at': m['sent_at']?.toString() ?? m['created_at']?.toString() ?? '',
            });
          }
          setState(() {});
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _chatId == null || _ended) return;
    _ctrl.clear();

    // Optimistic: show message immediately
    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _messages.add({
        'id': optimisticId,
        'content': text,
        'sender': 'user',
        'sent_at': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();

    try {
      final headers = await _headers();
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/support/chat/$_chatId/message'),
        headers: headers,
        body: jsonEncode({'content': text}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Send message failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('Send message error: $e');
    }
  }

  Future<void> _endChat() async {
    if (_chatId == null) return;
    try {
      final headers = await _headers();
      await http.post(
        Uri.parse('${ApiService.baseUrl}/support/chat/$_chatId/end'),
        headers: headers,
        body: jsonEncode({}),
      );
    } catch (_) {}
    _pollTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('live_chat_session_id');
    if (mounted) setState(() => _ended = true);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Chat', style: _f(size: 16, weight: FontWeight.w700)),
            Text(
              _ended ? 'Chat ended' : 'Support team',
              style: _f(size: 11, color: _ended ? AppColors.textHint : AppColors.success),
            ),
          ],
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 20, height: 20,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
        actions: [
          if (!_ended && _chatId != null)
            IconButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text('End Chat?', style: _f(size: 18, weight: FontWeight.w700)),
                    content: Text('This will close the current support session.', style: _f(size: 14, color: AppColors.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: _f(size: 14, weight: FontWeight.w600, color: AppColors.textSecondary))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('End Chat', style: _f(size: 14, weight: FontWeight.w700, color: AppColors.error))),
                    ],
                  ),
                );
                if (confirm == true) _endChat();
              },
              icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 22),
            ),
        ],
      ),
      body: _starting
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Connecting to support...', style: _f(size: 14, color: AppColors.textTertiary)),
            ]))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _msgBubble(_messages[i]),
                  ),
                ),
                if (_ended)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderLight))),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('This chat has ended', style: _f(size: 13, color: AppColors.textTertiary)),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              setState(() { _ended = false; _starting = true; _messages.clear(); });
                              await _startNewChat();
                              if (mounted) setState(() => _starting = false);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Start New Chat', style: _f(size: 14, weight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ]),
                    ),
                  )
                else
                  _inputBar(),
              ],
            ),
    );
  }

  Widget _msgBubble(Map<String, dynamic> msg) {
    final isUser = msg['sender'] == 'user';
    final isSystem = msg['sender'] == 'system';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isSystem ? AppColors.surfaceVariant : AppColors.primarySoft,
              child: Icon(isSystem ? Icons.support_agent_rounded : Icons.person_rounded, size: 14,
                  color: isSystem ? AppColors.textSecondary : AppColors.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : (isSystem ? AppColors.surfaceVariant : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppColors.borderLight),
              ),
              child: Text(
                msg['content'] ?? '',
                style: _f(size: 13, color: isUser ? Colors.white : AppColors.textPrimary, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Input bar - consistent with messages_screen.dart style
  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderLight, width: 0.5),
              ),
              child: TextField(
                controller: _ctrl,
                style: _f(size: 14),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: _f(size: 14, color: AppColors.textHint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: Center(
                child: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : SvgPicture.asset('assets/icons/send-icon.svg', width: 18, height: 18,
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
