import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ai_markdown_content.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/services/event_contributors_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../events/event_detail_screen.dart';
import '../tickets/ticket_details_screen.dart';
import '../home/home_tab_controller.dart';

/// Nuru AI Assistant, matching /nuru_chat_ui.png mockup.
/// Streams from the supabase nuru-chat edge function and renders rich
/// cards (contribution progress, ticket lists, tables, inline prompts)
/// embedded in the assistant text as ```nuru-card:<kind>``` fenced blocks.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  static const _endpoint =
      'https://lmfprculxhspqxppscbn.supabase.co/functions/v1/nuru-chat';
  static const _lightBars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarDividerColor: Colors.transparent,
  );
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _sending = false;
  String? _attachedName;

  final List<_Msg> _messages = [];

  static const _quickActions = <_QuickAction>[
    _QuickAction('assets/icons/trending-up-icon.svg', 'Track my\ncontribution',
        'Show my contribution progress', 'contributions'),
    _QuickAction('assets/icons/ticket-icon.svg', 'Find my\ntickets',
        'Show my recent tickets', 'tickets'),
    _QuickAction('assets/icons/wallet-icon.svg', 'Help with\npayments',
        'I need help with a payment issue'),
    _QuickAction('assets/icons/event-calendar-check-icon.svg', 'Event\nsupport',
        'I need help with an event'),
  ];

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: AppColors.surface,
      systemNavigationBarContrastEnforced: false,
    ));
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _setLightSystemBars();
    _ctrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  void _setLightSystemBars() => SystemChrome.setSystemUIOverlayStyle(_lightBars);

  Future<void> _send([String? prompt]) async {
    var text = (prompt ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;

    if (_attachedName != null) {
      text = '$text\n\n[Attached image: $_attachedName]';
    }

    _ctrl.clear();
    setState(() {
      _sending = true;
      _attachedName = null;
      _messages.add(_Msg(role: 'user', content: text, time: DateTime.now()));
      _messages.add(_Msg(role: 'assistant', content: '', time: DateTime.now()));
    });
    _scrollToBottom();

    String assistantText = '';
    try {
      final token = await SecureTokenStorage.getToken();
      final req = http.Request('POST', Uri.parse(_endpoint))
        ..headers['Content-Type'] = 'application/json';
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.body = jsonEncode({
        'messages': _messages
            .where((m) => m.content.isNotEmpty && m.role != 'card')
            .map((m) => {'role': m.role, 'content': m.content})
            .toList(),
      });

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception('AI service unavailable');
      }

      await for (final line
          in streamed.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        try {
          final decoded = jsonDecode(payload) as Map<String, dynamic>;
          final choices = decoded['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices.first as Map<String, dynamic>)['delta'];
            if (delta is Map && delta['content'] is String) {
              assistantText += delta['content'] as String;
              if (mounted) {
                setState(() {
                  _messages[_messages.length - 1] =
                      _Msg(role: 'assistant', content: assistantText, time: DateTime.now());
                });
                _scrollToBottom();
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] = _Msg(
            role: 'assistant',
            content: "I couldn't reach Nuru AI right now. Please try again in a moment.",
            time: DateTime.now(),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
      _inputFocus.requestFocus();
    }
  }

  Future<void> _runQuickAction(_QuickAction q) async {
    if (_sending) return;
    if (q.kind == 'tickets') {
      await _showTicketsDirectly(q.prompt);
      return;
    }
    if (q.kind == 'contributions') {
      await _showContributionsDirectly(q.prompt);
      return;
    }
    _send(q.prompt);
  }

  Future<void> _showTicketsDirectly(String prompt) async {
    _ctrl.clear();
    final now = DateTime.now();
    setState(() {
      _sending = true;
      _messages.add(_Msg(role: 'user', content: prompt, time: now));
      _messages.add(_Msg(role: 'assistant', content: '', time: DateTime.now()));
    });
    _scrollToBottom();
    try {
      final res = await TicketingService.getMyTickets(limit: 10);
      final data = res['data'];
      final tickets = data is Map
          ? List<dynamic>.from(data['tickets'] ?? const [])
          : (data is List ? data : const <dynamic>[]);
      if (res['success'] == true && tickets.isNotEmpty) {
        final grouped = _groupTicketsForCard(tickets);
        final content = 'Here are your recent tickets:' +
            _localCardBlock('tickets_list', {'items': grouped, 'tickets': tickets});
        if (mounted) {
          setState(() => _messages[_messages.length - 1] =
              _Msg(role: 'assistant', content: content, time: DateTime.now()));
        }
      } else {
        if (mounted) {
          setState(() => _messages[_messages.length - 1] = _Msg(
                role: 'assistant',
                content: "You don't have any tickets yet.",
                time: DateTime.now(),
              ));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages[_messages.length - 1] = _Msg(
              role: 'assistant',
              content: 'I could not load your tickets right now. Please try again shortly.',
              time: DateTime.now(),
            ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
      _inputFocus.requestFocus();
    }
  }

  Future<void> _showContributionsDirectly(String prompt) async {
    _ctrl.clear();
    setState(() {
      _sending = true;
      _messages.add(_Msg(role: 'user', content: prompt, time: DateTime.now()));
      _messages.add(_Msg(role: 'assistant', content: '', time: DateTime.now()));
    });
    _scrollToBottom();
    try {
      final res = await EventContributorsService.getMyContributions();
      final data = res['data'];
      final items = data is Map
          ? List<dynamic>.from(data['events'] ?? data['items'] ?? const [])
          : (data is List ? data : const <dynamic>[]);
      if (res['success'] == true && items.isNotEmpty) {
        final row = Map<String, dynamic>.from(items.first as Map);
        final pledged = (row['pledge_amount'] ?? row['pledged_amount'] ?? row['amount_pledged'] ?? 0) as num;
        final paid = (row['total_paid'] ?? row['paid_amount'] ?? row['amount_paid'] ?? 0) as num;
        final pct = pledged > 0 ? ((paid / pledged) * 100).clamp(0, 100).round() : 0;
        final content = 'Here is your contribution:' +
            _localCardBlock('contribution_progress', {
              'event_id': row['event_id'] ?? (row['event'] is Map ? row['event']['id'] : null),
              'event_name': row['event_name'] ?? row['event_title'] ?? (row['event'] is Map ? row['event']['title'] : 'Event'),
              'paid': paid,
              'pledged': pledged,
              'percent': pct,
              'currency': row['currency'] ?? 'TZS',
            });
        if (mounted) {
          setState(() => _messages[_messages.length - 1] =
              _Msg(role: 'assistant', content: content, time: DateTime.now()));
        }
      } else {
        if (mounted) {
          setState(() => _messages[_messages.length - 1] = _Msg(
                role: 'assistant',
                content: "You don't have any contribution records yet.",
                time: DateTime.now(),
              ));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages[_messages.length - 1] = _Msg(
              role: 'assistant',
              content: 'I could not load your contributions right now. Please try again shortly.',
              time: DateTime.now(),
            ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
      _inputFocus.requestFocus();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _localCardBlock(String kind, Map<String, dynamic> payload) =>
      '\n\n```nuru-card:$kind\n${jsonEncode(payload)}\n```\n';

  List<Map<String, dynamic>> _groupTicketsForCard(List<dynamic> tickets) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final raw in tickets) {
      if (raw is! Map) continue;
      final t = Map<String, dynamic>.from(raw);
      final ev = t['event'] is Map ? Map<String, dynamic>.from(t['event'] as Map) : <String, dynamic>{};
      final eventId = (t['event_id'] ?? ev['id'] ?? t['id']).toString();
      final item = grouped.putIfAbsent(eventId, () => {
            'event_id': eventId,
            'event_name': ev['name'] ?? ev['title'] ?? t['event_name'] ?? 'Event',
            'date': ev['start_date'] ?? t['event_date'] ?? t['start_date'],
            'time': ev['start_time'] ?? t['event_time'],
            'location': ev['location'] ?? t['location'],
            'count': 0,
            'tickets': <Map<String, dynamic>>[],
          });
      item['count'] = (item['count'] as int) + ((t['quantity'] as num?)?.toInt() ?? 1);
      (item['tickets'] as List<Map<String, dynamic>>).add(t);
    }
    return grouped.values.toList();
  }

  TextStyle _f({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.3,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: letterSpacing);

  Widget _svg(String asset, {double size = 22, Color? color}) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color ?? AppColors.primary, BlendMode.srcIn),
      );

  @override
  Widget build(BuildContext context) {
    _setLightSystemBars();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _lightBars,
      child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(
        title: context.tr('ai_assistant'),
        actions: [
          IconButton(
            tooltip: 'Privacy & Security',
            onPressed: _showSecuritySheet,
            splashRadius: 22,
            icon: _svg('assets/icons/shield-icon.svg', size: 22),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                _welcomeCard(),
                const SizedBox(height: 14),
                _quickActionsRow(),
                const SizedBox(height: 18),
                if (_messages.isNotEmpty) _todayLabel(),
                ..._buildMessages(),
                if (_sending && _messages.isNotEmpty && _messages.last.content.isEmpty)
                  _typingBubble(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _composer(),
        ],
      ),
      ),
    );
  }

  // ─── Welcome ─────────────────────────────────────────────────
  Widget _welcomeCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Center(child: _svg('assets/icons/sparkle-icon.svg', size: 28)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Hi, I'm Nuru AI.",
                    style: _f(size: 17, weight: FontWeight.w800, height: 1.2)),
                Text('How can I help today?',
                    style: _f(size: 17, weight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 6),
                Text(
                  'I can help you with contributions, payments, events, tickets, and more.',
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.4),
                ),
              ]),
            ),
          ],
        ),
      );

  Widget _quickActionsRow() => SizedBox(
        height: 88,
        child: Row(
          children: [
            for (int i = 0; i < _quickActions.length; i++) ...[
              Expanded(child: _quickTile(_quickActions[i])),
              if (i < _quickActions.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _quickTile(_QuickAction q) => GestureDetector(
        onTap: () => _runQuickAction(q),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _svg(q.asset, size: 20),
              const SizedBox(height: 6),
              Text(q.label,
                  style: _f(size: 10, weight: FontWeight.w600, height: 1.2),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );

  Widget _todayLabel() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'Today ${DateFormat.jm().format(DateTime.now())}',
            style: _f(size: 11, color: AppColors.textTertiary, weight: FontWeight.w600),
          ),
        ),
      );

  // ─── Messages ────────────────────────────────────────────────
  List<Widget> _buildMessages() {
    final out = <Widget>[];
    for (final m in _messages) {
      if (m.content.isEmpty && m.role == 'assistant' && m == _messages.last) continue;
      if (m.role == 'user') {
        out.add(_userBubble(m));
      } else {
        out.addAll(_assistantBlocks(m));
      }
    }
    return out;
  }

  Widget _userBubble(_Msg m) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(2),
                  ),
                ),
                child: SelectableText(m.content,
                    style: _f(size: 13, color: AppColors.textPrimary, height: 1.45)),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(DateFormat.jm().format(m.time),
                    style: _f(size: 10, color: AppColors.textTertiary)),
                const SizedBox(width: 4),
                _svg('assets/icons/double-check-icon.svg', size: 12),
              ]),
            ],
          ),
        ),
      );

  List<Widget> _assistantBlocks(_Msg m) {
    final blocks = _parseAssistantContent(m.content);
    final widgets = <Widget>[];
    for (final b in blocks) {
      Widget child;
      if (b.kind == 'text') {
        child = AiMarkdownContent(
          content: b.text,
          textColor: AppColors.textPrimary,
          accentColor: AppColors.primary,
          fontSize: 13,
          lineHeight: 1.45,
        );
      } else {
        child = _renderCard(b.kind, b.payload ?? const {});
      }
      widgets.add(_assistantWrap(child));
    }
    if (widgets.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 44, bottom: 10),
        child: Text(DateFormat.jm().format(m.time),
            style: _f(size: 10, color: AppColors.textTertiary)),
      ));
    }
    return widgets;
  }

  Widget _assistantWrap(Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(child: _svg('assets/icons/sparkle-icon.svg', size: 16)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: child,
            ),
          ),
        ]),
      );

  Widget _typingBubble() => _assistantWrap(
        Row(mainAxisSize: MainAxisSize.min, children: [
          _dot(0),
          const SizedBox(width: 4),
          _dot(150),
          const SizedBox(width: 4),
          _dot(300),
        ]),
      );

  Widget _dot(int delayMs) => _PulseDot(delayMs: delayMs, color: AppColors.primary);

  // ─── Card rendering ──────────────────────────────────────────
  Widget _renderCard(String kind, Map<String, dynamic> p) {
    switch (kind) {
      case 'contribution_progress':
        return _contributionCard(p);
      case 'tickets_list':
        return _ticketsCard(p);
      case 'events_list':
        return _eventsCard(p);
      case 'results_list':
        return _resultsListCard(p);
      case 'input_prompt':
        return _inputPromptCard(p);
      case 'multi_input_prompt':
        return _multiInputPromptCard(p);
      case 'confirm_action':
        return _confirmCard(p);
      case 'table':
        return _tableCard(p);
      default:
        return Text('Unsupported card: $kind', style: _f(size: 12));
    }
  }

  Widget _contributionCard(Map<String, dynamic> p) {
    final paid = (p['paid'] as num?)?.toInt() ?? 0;
    final pledged = (p['pledged'] as num?)?.toInt() ?? 0;
    final pct = (p['percent'] as num?)?.toInt() ??
        (pledged > 0 ? ((paid / pledged) * 100).round() : 0);
    final currency = p['currency']?.toString() ?? 'TZS';
    final eventName = p['event_name']?.toString() ?? 'Event';
    final fmt = NumberFormat('#,###');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eventName, style: _f(size: 12, weight: FontWeight.w700, color: AppColors.textTertiary)),
      const SizedBox(height: 6),
      Text("You've paid $currency ${fmt.format(paid)} of your $currency ${fmt.format(pledged)} pledge.",
          style: _f(size: 13, height: 1.45)),
      const SizedBox(height: 10),
        Row(children: [
        Text("That's ", style: _f(size: 13)),
        Text('$pct% complete',
            style: _f(size: 13, weight: FontWeight.w800, color: AppColors.primary)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$pct%',
            style: _f(size: 12, weight: FontWeight.w800, color: AppColors.primary)),
      ]),
      const SizedBox(height: 10),
      const Divider(height: 1),
      const SizedBox(height: 8),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HomeTabController.openMyContributions();
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: Row(children: [
          Expanded(
            child: Text('View Contribution Details',
                style: _f(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
          ),
          _svg('assets/icons/chevron-right-icon.svg', size: 18),
        ]),
      ),
    ]);
  }

  Widget _ticketsCard(Map<String, dynamic> p) {
    final items = (p['items'] as List?) ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final raw in items) ...[
        _ticketRow(Map<String, dynamic>.from(raw as Map)),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 4),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HomeTabController.openTickets();
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: Row(children: [
          Expanded(
            child: Text('View All Tickets',
                style: _f(size: 13, weight: FontWeight.w700, color: AppColors.primary)),
          ),
          _svg('assets/icons/chevron-right-icon.svg', size: 18),
        ]),
      ),
    ]);
  }

  Widget _ticketRow(Map<String, dynamic> t) {
    final name = t['event_name']?.toString() ?? 'Event';
    final dateRaw = t['date']?.toString();
    String dateStr = '';
    if (dateRaw != null) {
      try {
        final dt = DateTime.parse(dateRaw).toLocal();
        dateStr = '${DateFormat('d MMM yyyy').format(dt)}  •  ${DateFormat.jm().format(dt)}';
      } catch (_) {
        dateStr = dateRaw;
      }
    }
    final ticketsList = (t['tickets'] as List?) ?? const [];
    final count = (t['count'] as num?)?.toInt() ?? ticketsList.length;
    void openTicket() {
      if (ticketsList.length == 1 && ticketsList.first is Map) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TicketDetailsScreen(
              ticket: Map<String, dynamic>.from(ticketsList.first as Map),
            ),
          ),
        );
      } else {
        HomeTabController.openTickets();
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: openTicket,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: _svg('assets/icons/ticket-icon.svg', size: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: _f(size: 12, weight: FontWeight.w700)),
              if (dateStr.isNotEmpty)
                Text(dateStr, style: _f(size: 10, color: AppColors.textTertiary)),
            ]),
          ),
          Text('$count Ticket${count == 1 ? '' : 's'}',
              style: _f(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(width: 4),
          _svg('assets/icons/chevron-right-icon.svg', size: 16),
        ]),
      ),
    );
  }

  Widget _eventsCard(Map<String, dynamic> p) {
    final items = (p['items'] as List?) ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your Nuru events', style: _f(size: 13, weight: FontWeight.w800)),
      const SizedBox(height: 10),
      for (final raw in items.take(8)) ...[
        _eventRow(Map<String, dynamic>.from(raw as Map)),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _eventRow(Map<String, dynamic> e) {
    final id = e['id']?.toString() ?? '';
    final name = e['title']?.toString() ?? 'Event';
    final role = e['role']?.toString() ?? 'Event';
    final dateRaw = e['start_date']?.toString();
    final time = e['start_time']?.toString();
    final location = e['location']?.toString();
    var dateStr = '';
    if (dateRaw != null && dateRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateRaw).toLocal();
        dateStr = DateFormat('d MMM yyyy').format(dt);
      } catch (_) {
        dateStr = dateRaw;
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: id.isEmpty
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(
                    eventId: id,
                    initialData: e,
                    knownRole: role.toLowerCase().contains('organiser') ? 'creator' : null,
                  ),
                ),
              ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: _svg('assets/icons/event-calendar-check-icon.svg', size: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: _f(size: 12.5, weight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                [dateStr, time, location].where((v) => v != null && v.toString().isNotEmpty).join('  •  '),
                style: _f(size: 10.5, color: AppColors.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(role, style: _f(size: 10.5, weight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(width: 4),
          _svg('assets/icons/chevron-right-icon.svg', size: 16),
        ]),
      ),
    );
  }

  Widget _resultsListCard(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? 'Nuru results';
    final icon = p['icon']?.toString() ?? 'event';
    final items = (p['items'] as List?) ?? const [];
    final iconAsset = switch (icon) {
      'service' => 'assets/icons/package-icon.svg',
      'person' => 'assets/icons/user-icon.svg',
      _ => 'assets/icons/event-calendar-check-icon.svg',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: _f(size: 13, weight: FontWeight.w800)),
      const SizedBox(height: 10),
      for (final raw in items.take(8)) ...[
        _resultRow(Map<String, dynamic>.from(raw as Map), iconAsset),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _resultRow(Map<String, dynamic> item, String iconAsset) {
    final title = item['title']?.toString() ?? 'Nuru result';
    final subtitle = item['subtitle']?.toString() ?? '';
    final meta = item['meta']?.toString() ?? '';
    final badge = item['badge']?.toString();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: _svg(iconAsset, size: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _f(size: 12.5, weight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: _f(size: 11, weight: FontWeight.w700, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(meta, style: _f(size: 10.5, color: AppColors.textTertiary), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        if (badge != null && badge.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(badge, style: _f(size: 10.5, weight: FontWeight.w800, color: AppColors.primary)),
        ],
      ]),
    );
  }

  Widget _inputPromptCard(Map<String, dynamic> p) {
    final label = p['label']?.toString() ?? 'Please provide a value';
    final field = p['field']?.toString() ?? 'value';
    final placeholder = p['placeholder']?.toString() ?? '';
    final type = p['input_type']?.toString() ?? 'text';
    final controller = TextEditingController();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _f(size: 13, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: type == 'number' || type == 'phone'
                ? TextInputType.number
                : (type == 'email' ? TextInputType.emailAddress : TextInputType.text),
            decoration: InputDecoration(
              hintText: placeholder.isEmpty ? 'Type your answer…' : placeholder,
              hintStyle: _f(size: 13, color: AppColors.textHint),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: _f(size: 13),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              _send('$field: $v');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: _svg('assets/icons/send-icon.svg', size: 18, color: Colors.white),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _multiInputPromptCard(Map<String, dynamic> p) {
    final title = p['title']?.toString();
    final submitLabel = p['submit_label']?.toString() ?? 'Continue';
    final fields = (p['fields'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final controllers = <String, TextEditingController>{};
    final selections = <String, String?>{};
    for (final f in fields) {
      final key = f['field']?.toString() ?? 'value';
      if ((f['input_type']?.toString() ?? 'text') == 'choice') {
        selections[key] = f['default']?.toString();
      } else {
        controllers[key] = TextEditingController(text: f['default']?.toString() ?? '');
      }
    }
    return StatefulBuilder(builder: (context, setLocalState) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null && title.isNotEmpty) ...[
          Text(title, style: _f(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 10),
        ],
        for (final f in fields) ...[
          _multiInputField(f, controllers, selections, setLocalState),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final parts = <String>[];
              for (final f in fields) {
                final key = f['field']?.toString() ?? 'value';
                final label = f['label']?.toString() ?? key;
                final required = f['required'] == true;
                String? v;
                if ((f['input_type']?.toString() ?? 'text') == 'choice') {
                  v = selections[key];
                } else {
                  v = controllers[key]?.text.trim();
                }
                if (v == null || v.isEmpty) {
                  if (required) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label is required')),
                    );
                    return;
                  }
                  continue;
                }
                parts.add('$label: $v');
              }
              if (parts.isEmpty) return;
              _send(parts.join('\n'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(submitLabel,
                style: _f(size: 13, weight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]);
    });
  }

  Widget _multiInputField(
    Map<String, dynamic> f,
    Map<String, TextEditingController> controllers,
    Map<String, String?> selections,
    void Function(void Function()) setLocalState,
  ) {
    final key = f['field']?.toString() ?? 'value';
    final label = f['label']?.toString() ?? 'Value';
    final type = f['input_type']?.toString() ?? 'text';
    final placeholder = f['placeholder']?.toString() ?? '';
    final required = f['required'] == true;
    final labelWidget = RichText(
      text: TextSpan(style: _f(size: 12, weight: FontWeight.w700), children: [
        TextSpan(text: label),
        if (required)
          TextSpan(text: ' *', style: _f(size: 12, weight: FontWeight.w700, color: AppColors.primary)),
      ]),
    );

    if (type == 'choice') {
      final options = (f['options'] as List? ?? const []).map((e) => e.toString()).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        labelWidget,
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final opt in options)
              GestureDetector(
                onTap: () => setLocalState(() => selections[key] = opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selections[key] == opt ? AppColors.primary : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selections[key] == opt
                          ? AppColors.primary
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Text(opt,
                      style: _f(
                        size: 12,
                        weight: FontWeight.w700,
                        color: selections[key] == opt ? Colors.white : AppColors.textPrimary,
                      )),
                ),
              ),
          ],
        ),
      ]);
    }

    final keyboard = type == 'number'
        ? TextInputType.number
        : (type == 'phone'
            ? TextInputType.phone
            : (type == 'email'
                ? TextInputType.emailAddress
                : (type == 'date' ? TextInputType.datetime : TextInputType.text)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      labelWidget,
      const SizedBox(height: 6),
      TextField(
        controller: controllers[key],
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: placeholder.isEmpty ? 'Type here…' : placeholder,
          hintStyle: _f(size: 12.5, color: AppColors.textHint),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: _f(size: 13),
      ),
    ]);
  }

  Widget _confirmCard(Map<String, dynamic> p) {
    final question = p['question']?.toString() ?? 'Are you sure?';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(question, style: _f(size: 13, weight: FontWeight.w700)),
      const SizedBox(height: 10),
      Row(children: [
        OutlinedButton(
          onPressed: () => _send('No, cancel.'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.borderLight),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('No', style: _f(size: 12, weight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => _send('Yes, please proceed.'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Yes',
              style: _f(size: 12, weight: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    ]);
  }

  Widget _tableCard(Map<String, dynamic> p) {
    final title = p['title']?.toString();
    final headers = (p['headers'] as List? ?? []).map((e) => e.toString()).toList();
    final rows = (p['rows'] as List? ?? [])
        .map<List<String>>((r) => (r as List).map((e) => e.toString()).toList())
        .toList();
    if (headers.isEmpty) return const SizedBox.shrink();

    bool looksNumeric(String v) {
      final t = v.trim().replaceAll(',', '').replaceAll(RegExp(r'[A-Za-z\s%₹€TZSKshUSDtzs\$]'), '');
      return t.isNotEmpty && double.tryParse(t) != null;
    }

    final numericCols = List<bool>.generate(headers.length, (i) {
      int n = 0, total = 0;
      for (final r in rows) {
        if (i < r.length && r[i].isNotEmpty) {
          total++;
          if (looksNumeric(r[i])) n++;
        }
      }
      return total > 0 && n / total >= 0.6;
    });

    // Measure-friendly widths: first column gets more room, numeric
    // columns hug their content, others stretch evenly.
    final screenW = MediaQuery.of(context).size.width;
    final maxTableW = screenW - 72;
    final firstColW = (maxTableW * 0.42).clamp(140.0, 220.0);
    final otherColCount = headers.length - 1;
    final remaining = maxTableW - firstColW;
    final otherColW = otherColCount > 0
        ? (remaining / otherColCount).clamp(96.0, 180.0)
        : 0.0;
    double widthFor(int i) => i == 0 ? firstColW : otherColW;

    Widget cell(String text,
        {required int colIndex,
        bool header = false,
        bool right = false,
        bool stripe = false}) {
      return Container(
        width: widthFor(colIndex),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text.isEmpty ? '-' : text,
          style: _f(
            size: header ? 11 : 12.5,
            weight: header ? FontWeight.w700 : FontWeight.w500,
            color: header
                ? AppColors.textSecondary
                : (text.isEmpty
                    ? AppColors.textSecondary.withOpacity(0.5)
                    : AppColors.textPrimary),
            height: 1.4,
            letterSpacing: header ? 0.4 : 0,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null && title.isNotEmpty) ...[
        Text(title, style: _f(size: 13.5, weight: FontWeight.w800)),
        const SizedBox(height: 10),
      ],
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft.withOpacity(0.45),
                    border: Border(
                      bottom: BorderSide(
                          color: AppColors.borderLight, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (int i = 0; i < headers.length; i++)
                        cell(headers[i].toUpperCase(),
                            colIndex: i,
                            header: true,
                            right: numericCols[i]),
                    ],
                  ),
                ),
                for (int r = 0; r < rows.length; r++)
                  Container(
                    decoration: BoxDecoration(
                      color: r.isOdd
                          ? AppColors.background.withOpacity(0.6)
                          : AppColors.surface,
                      border: Border(
                        bottom: r == rows.length - 1
                            ? BorderSide.none
                            : BorderSide(
                                color: AppColors.borderLight
                                    .withOpacity(0.6),
                                width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (int i = 0; i < headers.length; i++)
                          cell(i < rows[r].length ? rows[r][i] : '',
                              colIndex: i,
                              right: numericCols[i],
                              stripe: r.isOdd),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  // ─── Composer ────────────────────────────────────────────────
  // Borderless on focus / typing, only a soft surface tile so nothing
  // competes with the message itself.
  Widget _composer() {
    final hasText = _ctrl.text.trim().isNotEmpty;
    final canSend = hasText && !_sending;
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachedName != null) _attachmentChip(),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: AppColors.primary.withOpacity(0.45), width: 1.2),
              ),
              padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _showAttachmentSheet,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      child: _svg('assets/icons/attach-icon.svg',
                          size: 22, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _inputFocus,
                      style: _f(size: 14),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: 'Ask Nuru AI anything...',
                        hintStyle: _f(size: 14, color: AppColors.textHint),
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!hasText)
                    GestureDetector(
                      onTap: _showVoiceSheet,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _svg('assets/icons/microphone-icon.svg',
                              size: 18, color: AppColors.primary),
                        ),
                      ),
                    ),
                  if (!hasText) const SizedBox(width: 6),
                  GestureDetector(
                    onTap: canSend ? _send : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: canSend ? AppColors.primary : AppColors.borderLight,
                        shape: BoxShape.circle,
                        boxShadow: canSend
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : const [],
                      ),
                      child: Center(
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: _svg('assets/icons/send-icon.svg',
                                    size: 18,
                                    color: canSend ? Colors.white : AppColors.textHint),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _attachmentChip() => Container(
        margin: const EdgeInsets.only(bottom: 8, left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _svg('assets/icons/attach-icon.svg', size: 12, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(_attachedName!,
              style: _f(size: 11, weight: FontWeight.w600, color: AppColors.primary)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _attachedName = null),
            child: Icon(Icons.close, size: 14, color: AppColors.primary),
          ),
        ]),
      );

  // ─── Action handlers ─────────────────────────────────────────
  void _showSecuritySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: _svg('assets/icons/shield-icon.svg', size: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Privacy & Security',
                      style: _f(size: 16, weight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 14),
              _securityRow('End-to-end encryption',
                  'Every message you send to Nuru AI is sent over TLS and never used to train external models.'),
              const SizedBox(height: 12),
              _securityRow('Personal data is gated',
                  'Nuru AI can only see your contributions, tickets and events when you are signed in to this device.'),
              const SizedBox(height: 12),
              _securityRow('Public info needs no login',
                  'You can ask about vendors, event types and prices without signing in.'),
              const SizedBox(height: 12),
              _securityRow('You stay in control',
                  'Long-press any reply to copy, report or remove it from this conversation.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityRow(String title, String body) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: _f(size: 13, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(body,
                  style: _f(size: 12, color: AppColors.textSecondary, height: 1.5)),
            ]),
          ),
        ],
      );

  void _showAttachmentSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _svg('assets/icons/attach-icon.svg',
                    size: 26, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text('Attachments are on the way',
                style: _f(size: 15, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Soon you will be able to share photos, receipts and screenshots with Nuru AI for richer context. For now, type your question and we will reply instantly.',
              textAlign: TextAlign.center,
              style: _f(size: 12, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _inputFocus.requestFocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Type instead',
                    style: _f(size: 13, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: src,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      final name = file.name;
      setState(() => _attachedName = name);
      if (mounted) {
        AppSnackbar.success(context, 'Attached "$name". Add a question and send.');
        _inputFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Could not attach image.');
    }
  }

  void _showVoiceSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _svg('assets/icons/microphone-icon.svg',
                    size: 28, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text('Voice questions are on the way',
                style: _f(size: 15, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Soon you will be able to talk to Nuru AI in English or Kiswahili. For now, type your question and we will reply instantly.',
              textAlign: TextAlign.center,
              style: _f(size: 12, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _inputFocus.requestFocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Type instead',
                    style: _f(size: 13, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Models ──────────────────────────────────────────────────
class _Msg {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime time;
  _Msg({required this.role, required this.content, required this.time});
}

class _QuickAction {
  final String asset;
  final String label;
  final String prompt;
  final String? kind;
  const _QuickAction(this.asset, this.label, this.prompt, [this.kind]);
}

class _Block {
  final String kind; // 'text' | card kind
  final String text; // for text blocks
  final Map<String, dynamic>? payload;
  const _Block.text(this.text)
      : kind = 'text',
        payload = null;
  const _Block.card(this.kind, this.payload) : text = '';
}

/// Parse assistant text and split into text blocks + card blocks.
/// Cards are emitted as ```nuru-card:<kind>\n<json>\n```.
List<_Block> _parseAssistantContent(String content) {
  final out = <_Block>[];
  final re = RegExp(r'```nuru-card:([a-z_]+)\s*\n([\s\S]*?)\n```', multiLine: true);
  int last = 0;
  for (final m in re.allMatches(content)) {
    if (m.start > last) {
      final txt = content.substring(last, m.start).trim();
      if (txt.isNotEmpty) out.add(_Block.text(txt));
    }
    final kind = m.group(1) ?? '';
    final raw = m.group(2) ?? '{}';
    Map<String, dynamic> payload = {};
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    out.add(_Block.card(kind, payload));
    last = m.end;
  }
  if (last < content.length) {
    final tail = content.substring(last).trim();
    if (tail.isNotEmpty) out.add(_Block.text(tail));
  }
  if (out.isEmpty && content.trim().isNotEmpty) {
    out.add(_Block.text(content.trim()));
  }
  return out;
}

class _PulseDot extends StatefulWidget {
  final int delayMs;
  final Color color;
  const _PulseDot({required this.delayMs, required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
