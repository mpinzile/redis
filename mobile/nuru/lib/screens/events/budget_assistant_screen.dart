import '../../core/utils/money_format.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import '../../core/services/report_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/widgets/ai_markdown_content.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/l10n/l10n_helper.dart';
import 'report_preview_screen.dart';

/// AI Budget Assistant - chat-based budget planner matching web BudgetAssistant.
/// Streams responses from the nuru-chat edge function.
class BudgetAssistantScreen extends StatefulWidget {
  final String? eventType;
  final String? eventTypeName;
  final String? eventTitle;
  final String? location;
  final String? expectedGuests;
  final String? budget;
  final String? firstName;
  /// Called when AI generates budget items the user wants to import
  final void Function(List<Map<String, dynamic>> items)? onImportItems;
  /// Called when user wants to save the extracted total as event budget
  final void Function(String total)? onSaveBudget;

  const BudgetAssistantScreen({
    super.key,
    this.eventType,
    this.eventTypeName,
    this.eventTitle,
    this.location,
    this.expectedGuests,
    this.budget,
    this.firstName,
    this.onImportItems,
    this.onSaveBudget,
  });

  @override
  State<BudgetAssistantScreen> createState() => _BudgetAssistantScreenState();
}

class _BudgetAssistantScreenState extends State<BudgetAssistantScreen> {
  static const _endpoint = 'https://lmfprculxhspqxppscbn.supabase.co/functions/v1/nuru-chat';

  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <Map<String, String>>[];
  bool _streaming = false;
  String? _extractedTotal;
  List<Map<String, dynamic>> _extractedItems = [];
  String _generatedBudgetContent = '';
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    // Auto-start conversation
    Future.delayed(const Duration(milliseconds: 300), () => _sendToAI(null));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _systemPrompt() {
    final parts = <String>[];
    if (widget.eventTypeName != null || widget.eventType != null) parts.add('Event type: ${widget.eventTypeName ?? widget.eventType}');
    if (widget.eventTitle != null) parts.add('Event name: ${widget.eventTitle}');
    if (widget.location != null) parts.add('Location: ${widget.location}');
    if (widget.expectedGuests != null) parts.add('Expected guests: ${widget.expectedGuests}');
    if (widget.budget != null) parts.add('Current budget: ${getActiveCurrency()} ${widget.budget}');

    final name = widget.firstName ?? 'there';
    return '''You are the Nuru Budget Assistant - an expert event budget planner for Tanzania.

Your job: Have a SHORT, focused conversation to understand the user's event needs, then generate a detailed budget breakdown.

USER NAME: $name

KNOWN CONTEXT:
${parts.isNotEmpty ? parts.join('\n') : 'No details provided yet.'}

CONVERSATION RULES:
- Greet the user by their first name naturally (e.g. "Hello $name! Let's plan your budget.").
- Ask 2-3 focused questions about what matters most (venue type, catering style, entertainment, decor level, etc.)
- Ask ONE round of questions maximum. After the user responds, generate the budget.
- If the user says "generate" or "go ahead", generate immediately.
- Keep questions SHORT - use bullet points.
- NEVER use emoji icons in your responses.

BUDGET FORMAT (when generating):
- Use a markdown table with columns: Category | Description | Estimated Cost (TZS)
- Include: Venue, Catering, Decor, Entertainment, Photography/Video, Transportation, Attire, Stationery, Miscellaneous, Contingency (10%)
- End with a **TOTAL** row
- After the table, add a brief 2-line tip about where they can save.
- Costs must be realistic for Tanzania in TZS.''';
  }

  Future<void> _sendToAI(String? userMsg) async {
    if (_streaming) return;
    setState(() => _streaming = true);

    if (userMsg != null) {
      _extractedTotal = null;
      _extractedItems = [];
      _generatedBudgetContent = '';
    }

    final apiMessages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt()},
      ..._messages,
    ];
    if (userMsg != null) {
      _messages.add({'role': 'user', 'content': userMsg});
      apiMessages.add({'role': 'user', 'content': userMsg});
    }

    // Add empty assistant message for streaming
    _messages.add({'role': 'assistant', 'content': ''});
    setState(() {});
    _scrollToBottom();

    try {
      final request = http.Request('POST', Uri.parse(_endpoint));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'messages': apiMessages, 'skipTools': true});

      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        _messages.last['content'] = 'Something went wrong. Please try again.';
        setState(() => _streaming = false);
        return;
      }

      final stream = response.stream.transform(utf8.decoder);
      String buffer = '';
      String fullContent = '';

      await for (final chunk in stream) {
        buffer += chunk;
        int idx;
        while ((idx = buffer.indexOf('\n')) != -1) {
          String line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);
          if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
          if (!line.startsWith('data: ')) continue;
          final json = line.substring(6).trim();
          if (json == '[DONE]') break;
          try {
            final parsed = jsonDecode(json);
            if (parsed is Map && parsed['tool_status'] != null) continue;
            final delta = parsed['choices']?[0]?['delta']?['content'];
            if (delta != null && delta is String) {
              fullContent += delta;
              _messages.last['content'] = fullContent;
              setState(() {});
              _scrollToBottom();
            }
          } catch (_) {
            buffer = '$line\n$buffer';
            break;
          }
        }
      }

      // Extract budget total and items
      _extractedTotal = _extractTotal(fullContent);
      _extractedItems = _parseBudgetTable(fullContent);
      _generatedBudgetContent = fullContent;
      setState(() {});
    } catch (_) {
      if (_messages.isNotEmpty && _messages.last['content']?.isEmpty == true) {
        _messages.last['content'] = 'Connection error. Please try again.';
      }
    } finally {
      setState(() => _streaming = false);
    }
  }

  String? _extractTotal(String content) {
    final m1 = RegExp(r'\*\*TOTAL\*\*\s*\|\s*\*\*([0-9,]+)\*\*', caseSensitive: false).firstMatch(content);
    if (m1 != null) return m1.group(1)!.replaceAll(',', '');
    final m2 = RegExp(r'TOTAL[^0-9]*([0-9,]{4,})', caseSensitive: false).firstMatch(content);
    if (m2 != null) return m2.group(1)!.replaceAll(',', '');
    return null;
  }

  List<Map<String, dynamic>> _parseBudgetTable(String content) {
    final items = <Map<String, dynamic>>[];
    for (final line in content.split('\n')) {
      if (!line.contains('|')) continue;
      final cells = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      if (cells.length < 3) continue;
      if (cells[0].contains('---') || cells[0].toLowerCase() == 'category') continue;
      if (cells[0].replaceAll('*', '').trim().toLowerCase() == 'total') continue;
      final category = cells[0].replaceAll('*', '').trim();
      final description = cells[1].replaceAll('*', '').trim();
      final costStr = cells[2].replaceAll('*', '').replaceAll(RegExp(r'[^\d]'), '');
      final cost = int.tryParse(costStr) ?? 0;
      if (category.isNotEmpty && description.isNotEmpty && cost > 0) {
        items.add({'category': category, 'item_name': description, 'estimated_cost': cost});
      }
    }
    return items;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _handleSend() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _streaming) return;
    _ctrl.clear();
    _sendToAI(text);
  }

  Future<void> _previewEstimatedBudgetPdf() async {
    if (_generatedBudgetContent.trim().isEmpty || _extractedItems.isEmpty) {
      AppSnackbar.error(context, 'Generate a budget estimate first');
      return;
    }

    setState(() => _exportingPdf = true);
    final res = await ReportGenerator.generateAiBudgetEstimateReport(
      items: _extractedItems,
      eventTitle: widget.eventTitle,
      eventType: widget.eventTypeName ?? widget.eventType,
      location: widget.location,
      expectedGuests: widget.expectedGuests,
      total: _extractedTotal,
      content: _generatedBudgetContent,
    );

    if (!mounted) return;
    setState(() => _exportingPdf = false);

    if (res['success'] == true && res['bytes'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(
            title: 'Budget Estimate',
            pdfBytes: res['bytes'],
            filePath: res['path'] as String?,
          ),
        ),
      );
    } else {
      AppSnackbar.error(context, res['message'] ?? 'Failed to generate PDF');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/images/nuru-logo-square.png', width: 32, height: 32, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.trw('ai_budget_assistant'), style: appText(size: 15, weight: FontWeight.w700)),
            Text(context.trw('powered_by_nuru_ai'), style: appText(size: 10, color: AppColors.textTertiary)),
          ]),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';
                return _chatBubble(msg['content'] ?? '', isUser, i == _messages.length - 1 && _streaming && !isUser);
              },
            ),
          ),

          // Action buttons when budget is generated
          if (_extractedTotal != null || _extractedItems.isNotEmpty || _generatedBudgetContent.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (_generatedBudgetContent.isNotEmpty && _extractedItems.isNotEmpty)
                  _actionChip(
                    icon: Icons.picture_as_pdf_rounded,
                    label: _exportingPdf ? 'Preparing PDF...' : 'Preview PDF',
                    color: const Color(0xFFDC2626),
                    onTap: _exportingPdf ? () {} : _previewEstimatedBudgetPdf,
                  ),
                if (_extractedTotal != null && widget.onSaveBudget != null)
                  _actionChip(
                    icon: Icons.savings_rounded,
                    label: 'Set Budget: ${getActiveCurrency()} ${_extractedTotal}',
                    color: _green,
                    onTap: () {
                      widget.onSaveBudget!(_extractedTotal!);
                      Navigator.pop(context);
                    },
                  ),
                if (_extractedItems.isNotEmpty && widget.onImportItems != null)
                  _actionChip(
                    icon: Icons.download_rounded,
                    label: 'Import ${_extractedItems.length} Items',
                    color: AppColors.primary,
                    onTap: () {
                      widget.onImportItems!(_extractedItems);
                      Navigator.pop(context);
                    },
                  ),
              ]),
            ),

          // Input
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: appText(size: 14),
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _handleSend(),
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: appText(size: 13, color: AppColors.textHint),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border, width: 1)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border, width: 1)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _streaming ? null : _handleSend,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _streaming ? const Color(0xFFE2E8F0) : AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _streaming
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary),
                        )
                      : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  static const _green = Color(0xFF16A34A);

  Widget _chatBubble(String content, bool isUser, bool isStreaming) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: isUser ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: content.isEmpty && isStreaming
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 8),
                Text('Thinking...', style: appText(size: 13, color: AppColors.textTertiary)),
              ])
            : isUser
                ? SelectableText(
                    content,
                    style: appText(size: 13, color: Colors.white, height: 1.5),
                  )
                : AiMarkdownContent(
                    content: content,
                    textColor: AppColors.textPrimary,
                    accentColor: AppColors.primary,
                    fontSize: 13,
                    lineHeight: 1.5,
                  ),
      ),
    );
  }

  Widget _actionChip({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: appText(size: 12, weight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
