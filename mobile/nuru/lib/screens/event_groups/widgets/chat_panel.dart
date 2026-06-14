import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/event_groups_service.dart';
import '../../../core/services/uploads_service.dart';
import '../../../core/utils/event_groups_cache.dart';
import '../../../core/widgets/nuru_skeleton.dart';

const _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const _fullEmojis = [
  '👍','❤️','😂','😮','😢','🙏','🎉','🔥','💯','👏',
  '🤝','💪','✨','🥳','💸','💰','🤔','😎','😭','😡',
  '🙌','👀','🚀','💡','✅','❌',
];

/// Modern chat panel - redesigned to match mobile UI:
/// - Flat #F8F8FA background
/// - White rounded bubbles (16px) with soft shadow
/// - Sender name + time above bubbles
/// - Reactions chip below
/// - System contribution card with gift icon
/// - Composer with attach + send SVG icons
class ChatPanel extends StatefulWidget {
  final String groupId;
  final String? meMemberId;
  final bool isClosed;
  const ChatPanel({super.key, required this.groupId, this.meMemberId, this.isClosed = false});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploading = false;
  String? _cursor;
  Timer? _poll;
  Map<String, dynamic>? _replyTo;
  bool _stickToBottom = true;
  int _newCount = 0;
  bool _hasText = false;
  _PendingImage? _pendingImage;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    // Seed from cache for instant render on re-entry.
    final cached = EventGroupsCache.getMessages(widget.groupId);
    if (cached != null && cached.isNotEmpty) {
      _messages = List.from(cached);
      _cursor = _messages.last['created_at'];
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollEnd());
    }
    _initial(silent: cached != null && cached.isNotEmpty);
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _pollNew());
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    _stickToBottom = atBottom;
    if (atBottom && _newCount > 0) setState(() => _newCount = 0);
  }

  Future<void> _initial({bool silent = false}) async {
    final res = await EventGroupsService.messages(widget.groupId, limit: 50);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        _messages = data is Map ? List.from(data['messages'] ?? []) : [];
        if (_messages.isNotEmpty) _cursor = _messages.last['created_at'];
        EventGroupsCache.putMessages(widget.groupId, _messages);
      }
    });
    if (!silent) _scrollEnd();
    EventGroupsService.markRead(widget.groupId);
  }

  Future<void> _pollNew() async {
    if (_cursor == null) return;
    final res = await EventGroupsService.messages(widget.groupId, after: _cursor, limit: 50);
    if (!mounted) return;
    if (res['success'] == true) {
      final data = res['data'];
      final fresh = data is Map ? List.from(data['messages'] ?? []) : [];
      if (fresh.isEmpty) return;
      setState(() {
        final ids = _messages.map((m) => m['id']).toSet();
        var added = 0;
        for (final m in fresh) {
          if (!ids.contains(m['id'])) { _messages.add(m); added++; }
        }
        _cursor = fresh.last['created_at'];
        if (!_stickToBottom) _newCount += added;
        EventGroupsCache.putMessages(widget.groupId, _messages);
      });
      if (_stickToBottom) {
        _scrollEnd();
        EventGroupsService.markRead(widget.groupId);
      }
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      }
    });
  }

  void _jumpLatest() {
    setState(() => _newCount = 0);
    _stickToBottom = true;
    _scrollEnd();
    EventGroupsService.markRead(widget.groupId);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || widget.isClosed) return;
    final tempId = 'tmp-${DateTime.now().microsecondsSinceEpoch}';
    final reply = _replyTo;
    final optimistic = <String, dynamic>{
      'id': tempId,
      'message_type': 'text',
      'content': text,
      'sender_member_id': widget.meMemberId,
      'sender_name': 'You',
      'reply_to': reply,
      'reactions': [],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_pending': true,
    };
    setState(() {
      _messages.add(optimistic);
      _input.clear();
      _replyTo = null;
      _stickToBottom = true;
      _sending = true;
    });
    _scrollEnd();
    final res = await EventGroupsService.sendMessage(widget.groupId,
        content: text, replyToId: reply?['id']);
    if (!mounted) return;
    setState(() {
      _sending = false;
      final idx = _messages.indexWhere((m) => m['id'] == tempId);
      if (res['success'] == true && res['data'] is Map) {
        final real = Map<String, dynamic>.from(res['data']);
        // De-dupe: if poll already inserted the real message while we were
        // awaiting the server, drop the optimistic placeholder so we don't
        // render the same message twice.
        final dupIdx = _messages.indexWhere((m) => m['id'] == real['id']);
        if (dupIdx >= 0 && dupIdx != idx) {
          if (idx >= 0) _messages.removeAt(idx);
        } else if (idx >= 0) {
          _messages[idx] = real;
        } else {
          _messages.add(real);
        }
        _cursor = real['created_at'];
      } else if (idx >= 0) {
        _messages.removeAt(idx);
        _input.text = text;
      }
    });
    _scrollEnd();
  }

  Future<void> _pickImage() async {
    if (widget.isClosed) return;
    final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1920, imageQuality: 85);
    if (file == null) return;
    setState(() => _pendingImage = _PendingImage(file: file, caption: ''));
  }

  Future<void> _sendPendingImage() async {
    final p = _pendingImage;
    if (p == null || _uploading) return;
    final tempId = 'tmp-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages.add({
        'id': tempId,
        'message_type': 'image',
        'content': p.caption.trim().isEmpty ? null : p.caption.trim(),
        'image_url': p.file.path,
        '_local': true,
        'sender_member_id': widget.meMemberId,
        'sender_name': 'You',
        'reactions': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        '_pending': true,
      });
      _pendingImage = null;
      _stickToBottom = true;
      _uploading = true;
    });
    _scrollEnd();
    try {
      final upRes = await UploadsService.uploadFile(p.file.path);
      final url = upRes['data']?['url'] ?? upRes['data']?['file_url'] ?? upRes['data']?['public_url'];
      if (url == null) throw 'Upload failed';
      final res = await EventGroupsService.sendMessage(widget.groupId,
          imageUrl: url, content: p.caption.trim().isEmpty ? null : p.caption.trim());
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        setState(() {
          final i = _messages.indexWhere((m) => m['id'] == tempId);
          final real = Map<String, dynamic>.from(res['data']);
          if (i >= 0) _messages[i] = real; else _messages.add(real);
          _cursor = real['created_at'];
        });
      } else {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image upload failed')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _react(Map msg, String emoji) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final reactions = List<Map<String, dynamic>>.from((msg['reactions'] ?? []) as List);
      final mineIdx = reactions.indexWhere((r) => r['mine'] == true);
      final sameIdx = reactions.indexWhere((r) => r['emoji'] == emoji);

      // If user already reacted with this same emoji → toggle it off.
      if (mineIdx >= 0 && mineIdx == sameIdx) {
        final r = Map<String, dynamic>.from(reactions[mineIdx]);
        r['mine'] = false;
        r['count'] = ((r['count'] as int) - 1).clamp(0, 1 << 31);
        if ((r['count'] as int) <= 0) {
          reactions.removeAt(mineIdx);
        } else {
          reactions[mineIdx] = r;
        }
      } else {
        // Enforce single reaction per user - remove any previous one first.
        if (mineIdx >= 0) {
          final prev = Map<String, dynamic>.from(reactions[mineIdx]);
          prev['mine'] = false;
          prev['count'] = ((prev['count'] as int) - 1).clamp(0, 1 << 31);
          if ((prev['count'] as int) <= 0) {
            reactions.removeAt(mineIdx);
          } else {
            reactions[mineIdx] = prev;
          }
        }
        // Add or increment the new emoji bucket.
        final newSameIdx = reactions.indexWhere((r) => r['emoji'] == emoji);
        if (newSameIdx >= 0) {
          final r = Map<String, dynamic>.from(reactions[newSameIdx]);
          r['mine'] = true;
          r['count'] = (r['count'] as int) + 1;
          reactions[newSameIdx] = r;
        } else {
          reactions.add({'emoji': emoji, 'count': 1, 'mine': true});
        }
      }
      msg['reactions'] = reactions;
    });
    await EventGroupsService.react(widget.groupId, msg['id'], emoji);
  }

  Future<void> _delete(Map msg) async {
    setState(() {
      msg['is_deleted'] = true;
      msg['content'] = '(deleted)';
    });
    await EventGroupsService.deleteMessage(widget.groupId, msg['id']);
  }

  bool _canEdit(Map m) {
    if (m['is_deleted'] == true) return false;
    if (m['message_type'] == 'system') return false;
    final c = (m['content'] ?? '').toString();
    if (c.isEmpty) return false;
    final raw = (m['created_at'] ?? '').toString();
    final iso = raw.endsWith('Z') || raw.contains('+') ? raw : '${raw}Z';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return false;
    return DateTime.now().difference(dt).inMinutes < 15;
  }

  Future<void> _edit(Map msg) async {
    final ctrl = TextEditingController(text: (msg['content'] ?? '').toString());
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit message', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 14.5),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == msg['content']) return;
    final original = msg['content'];
    setState(() {
      msg['content'] = newText;
      msg['is_edited'] = true;
      msg['edited_at'] = DateTime.now().toUtc().toIso8601String();
    });
    final res = await EventGroupsService.editMessage(widget.groupId, msg['id'], newText);
    if (res['success'] != true && mounted) {
      setState(() {
        msg['content'] = original;
        msg['is_edited'] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error']?.toString() ?? 'Unable to edit')),
      );
    }
  }

  void _showReactPicker(Map msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final e in _fullEmojis)
                GestureDetector(
                  onTap: () { Navigator.pop(context); _react(msg, e); },
                  child: Container(
                    width: 46, height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                    child: _emoji(e, size: 24),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Server timestamps may be naive UTC (no `Z`/offset). Treat them as UTC
  /// before converting to local - otherwise `DateTime.parse` assumes the
  /// device's local zone and the chat shows server time instead of local.
  DateTime? _parseUtc(String iso) {
    if (iso.isEmpty) return null;
    var s = iso;
    final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) {
      if (s.contains('T')) {
        s = '${s}Z';
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}').hasMatch(s)) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      }
    }
    return DateTime.tryParse(s)?.toLocal();
  }

  String _formatTime(String iso) {
    final local = _parseUtc(iso);
    if (local == null) return '';
    var h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:$m $period';
  }

  /// Force OS color emoji rendering - Flutter inherits the surrounding
  /// text color which makes ❤️ render as monochrome (looks black).
  static const TextStyle _emojiStyle = TextStyle(
    fontSize: 13,
    color: null,
    fontFamilyFallback: [
      'Apple Color Emoji',
      'Segoe UI Emoji',
      'Noto Color Emoji',
      'EmojiOne Color',
    ],
  );

  /// Heart emoji is often rendered monochrome on Android - force red tint.
  static bool _isHeart(String e) => e == '❤️' || e == '❤' || e == '♥';

  Widget _emoji(String e, {double size = 13}) {
    final style = _isHeart(e)
        ? _emojiStyle.copyWith(fontSize: size, color: const Color(0xFFE0245E))
        : _emojiStyle.copyWith(fontSize: size);
    return Text(e, style: style);
  }

  bool _sameDay(String a, String b) {
    final da = _parseUtc(a);
    final db = _parseUtc(b);
    if (da == null || db == null) return false;
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dayLabel(String iso) {
    final d = _parseUtc(iso);
    if (d == null) return '';
    final now = DateTime.now();
    if (_sameDay(iso, now.toIso8601String())) return 'Today';
    if (_sameDay(iso, now.subtract(const Duration(days: 1)).toIso8601String())) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  String _initials(String n) =>
      n.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.white,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: NuruSkeletonList(itemCount: 8),
        ),
      );
    }
    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final prev = i > 0 ? _messages[i - 1] : null;
                          final next = i < _messages.length - 1 ? _messages[i + 1] : null;
                          final showDay = prev == null || !_sameDay(prev['created_at'], m['created_at']);
                          final mine = m['sender_member_id'] != null && m['sender_member_id'] == widget.meMemberId;
                          final isSystem = m['message_type'] == 'system';
                          final groupedWithPrev = prev != null
                              && !showDay
                              && prev['sender_member_id'] == m['sender_member_id']
                              && prev['message_type'] != 'system';
                          final groupedWithNext = next != null
                              && _sameDay(next['created_at'], m['created_at'])
                              && next['sender_member_id'] == m['sender_member_id']
                              && next['message_type'] != 'system';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDay) _daySeparator(_dayLabel(m['created_at'])),
                              if (isSystem)
                                _systemMsg(m)
                              else
                                _bubble(m, mine,
                                    showAvatar: true,
                                    showName: true,
                                    isTail: !groupedWithNext),
                            ],
                          );
                        },
                      ),
              ),
              if (_replyTo != null) _replyPreview(),
              _composer(),
            ],
          ),
        ),
        if (_newCount > 0)
          Positioned(
            bottom: (_replyTo != null ? 132 : 88),
            left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _jumpLatest,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text('$_newCount new message${_newCount > 1 ? 's' : ''}',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        if (_pendingImage != null) _imagePreviewSheet(),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primarySoft,
            ),
            child: SvgPicture.asset('assets/icons/group-chat-icon.svg',
                width: 28, height: 28,
                colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                fit: BoxFit.scaleDown),
          ),
          const SizedBox(height: 14),
          Text('No messages yet',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Say hi to your group 👋',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
        ]),
      );

  Widget _daySeparator(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(label,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 1.1)),
          ),
        ),
      );

  Widget _systemMsg(Map m) {
    final meta = (m['metadata'] is Map) ? m['metadata'] as Map : null;
    final isPayment = meta != null && meta['kind'] == 'payment' && meta['amount'] is num;
    if (!isPayment) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
          ),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          child: Text(
            (m['content'] ?? '').toString(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    // Darker emerald palette to match the web event-group contribution card
    // (tailwind emerald-600/700/100 - text-emerald-700, bg-emerald-100 etc.)
    const emerald = Color(0xFF047857); // emerald-700
    const emeraldStrong = Color(0xFF059669); // emerald-600
    const emeraldSoft = Color(0xFFD1FAE5); // emerald-100
    final name = (meta['contributor_name'] ?? 'Someone').toString();
    final amount = (meta['amount'] as num).toDouble();
    final pledge = (meta['pledge'] is num) ? (meta['pledge'] as num).toDouble() : 0.0;
    final paid = (meta['paid'] is num) ? (meta['paid'] as num).toDouble() : 0.0;
    final balanceRaw = meta['balance'];
    final balance = balanceRaw is num
        ? balanceRaw.toDouble()
        : (pledge - paid).clamp(0.0, double.infinity);
    final currency = (meta['currency'] ?? 'TZS').toString();
    final pct = pledge > 0 ? (paid / pledge * 100).clamp(0, 100).round() : 0;
    final overpaid = paid > pledge && pledge > 0;
    final extra = overpaid ? (paid - pledge) : 0.0;
    final complete = pledge > 0 && balance <= 0 && !overpaid;
    String fmt(double n) =>
        '$currency ${n.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();
    final dt = DateTime.tryParse(m['created_at'] ?? '')?.toLocal();
    final dateLabel = dt == null
        ? ''
        : '${dt.day.toString().padLeft(2, '0')} ${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1]}';
    final timeLabel = _formatTime(m['created_at'] ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date/time meta above card
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dateLabel,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
                    const SizedBox(width: 6),
                    Container(width: 3, height: 3, decoration: BoxDecoration(color: AppColors.textTertiary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(timeLabel,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: emerald)),
                  ],
                ),
              ),
              // Contribution card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: emerald.withOpacity(0.20)),
                  boxShadow: AppColors.cardShadow,
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40, height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: complete ? emeraldSoft : AppColors.primarySoft,
                      ),
                      child: SvgPicture.asset('assets/icons/donation-icon.svg',
                          width: 22, height: 22,
                          colorFilter: ColorFilter.mode(complete ? emerald : AppColors.primary, BlendMode.srcIn)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  complete ? 'Pledge Complete' : 'New Contribution',
                                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: emerald, letterSpacing: 1.2),
                                ),
                              ),
                              Text('+${fmt(amount)}',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: emerald, letterSpacing: -0.2)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          if (pledge > 0) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                height: 6,
                                color: AppColors.background,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: overpaid ? AppColors.warning : emeraldStrong,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('${fmt(paid)} of ${fmt(pledge)}',
                                      style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
                                ),
                                Text('$pct%',
                                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              overpaid
                                  ? 'Over by ${fmt(extra)}'
                                  : balance > 0
                                      ? 'Balance ${fmt(balance)}'
                                      : 'Fully paid',
                              style: GoogleFonts.inter(
                                fontSize: 10.5, fontWeight: FontWeight.w700,
                                color: overpaid ? AppColors.warning : balance > 0 ? AppColors.error : emerald,
                              ),
                            ),
                          ],
                        ],
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

  Widget _bubble(Map m, bool mine, {required bool showAvatar, required bool showName, required bool isTail}) {
    final reactions = (m['reactions'] ?? []) as List;
    final pending = m['_pending'] == true;
    final senderName = (m['sender_name'] ?? '').toString();
    final timeLabel = _formatTime(m['created_at']);

    Widget avatar = SizedBox(
      width: 36,
      child: showAvatar
          ? CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primarySoft,
              backgroundImage: m['sender_avatar_url'] != null ? NetworkImage(m['sender_avatar_url']) : null,
              child: m['sender_avatar_url'] == null
                  ? Text(_initials(senderName.isEmpty ? (mine ? 'You' : '?') : senderName),
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w800))
                  : null,
            )
          : null,
    );

    final bubble = Container(
      padding: m['image_url'] != null
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: mine ? AppColors.primary.withOpacity(0.18) : AppColors.border,
        ),
        boxShadow: AppColors.subtleShadow,
      ),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m['reply_to'] != null)
            Container(
              margin: EdgeInsets.only(bottom: 6, left: m['image_url'] != null ? 4 : 0, right: m['image_url'] != null ? 4 : 0, top: m['image_url'] != null ? 4 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(mine ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: AppColors.primary.withOpacity(mine ? 0.6 : 0.85), width: 2.5),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['reply_to']['sender_name'] ?? '',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 1),
                Text(m['reply_to']['content'] ?? 'Image',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ),
          if (m['image_url'] != null) ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: m['_local'] == true
                ? Image.file(File(m['image_url']), width: 240, fit: BoxFit.cover)
                : CachedNetworkImage(imageUrl: m['image_url'], fit: BoxFit.cover, width: 240),
          ),
          if (m['content'] != null && (m['content'] as String).isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  m['image_url'] != null ? 8 : 0,
                  m['image_url'] != null ? 8 : 0,
                  m['image_url'] != null ? 8 : 0,
                  m['image_url'] != null ? 6 : 0),
              child: Text(m['content'],
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  )),
            ),
          if (pending) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.access_time, size: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );

    final reactionsRow = reactions.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, children: [
              for (final r in reactions)
                GestureDetector(
                  onTap: () => _react(m, r['emoji']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: r['mine'] == true ? AppColors.primarySoft : AppColors.surface,
                      border: Border.all(color: r['mine'] == true ? AppColors.primary : AppColors.border),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppColors.subtleShadow,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _emoji(r['emoji'], size: 13),
                      const SizedBox(width: 4),
                      Text('${r['count']}',
                          style: GoogleFonts.inter(
                              fontSize: 10.5, fontWeight: FontWeight.w800,
                              color: r['mine'] == true ? AppColors.primary : AppColors.textSecondary)),
                    ]),
                  ),
                ),
            ]),
          );

    final headerRow = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              mine ? 'You' : (senderName.isEmpty ? 'Member' : senderName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            m['is_edited'] == true ? '$timeLabel · edited' : timeLabel,
            style: GoogleFonts.inter(
                fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textTertiary),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: isTail ? 8 : 2),
      child: GestureDetector(
        onLongPress: widget.isClosed ? null : () => _showActionSheet(m, mine),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) ...[avatar, const SizedBox(width: 10)],
            Flexible(
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showName) headerRow,
                  bubble,
                  reactionsRow,
                ],
              ),
            ),
            if (mine) ...[const SizedBox(width: 10), avatar],
          ],
        ),
      ),
    );
  }

  void _showActionSheet(Map m, bool mine) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(28)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                for (final e in _quickEmojis)
                  GestureDetector(
                    onTap: () { Navigator.pop(context); _react(m, e); },
                    child: Padding(padding: const EdgeInsets.all(4), child: _emoji(e, size: 26)),
                  ),
                GestureDetector(
                  onTap: () { Navigator.pop(context); _showReactPicker(m); },
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                    child: Icon(Icons.add, size: 18, color: AppColors.textSecondary),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text('Reply', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () { Navigator.pop(context); setState(() => _replyTo = Map<String, dynamic>.from(m)); _focus.requestFocus(); },
            ),
            if ((m['content'] ?? '').toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text('Copy', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m['content'] ?? ''));
                  Navigator.pop(context);
                },
              ),
            if (mine && _canEdit(m)) ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edit', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () { Navigator.pop(context); _edit(m); },
            ),
            if (mine) ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.error)),
              onTap: () { Navigator.pop(context); _delete(m); },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _replyPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Row(children: [
        Container(width: 3, height: 32, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Replying to ${_replyTo!['sender_name'] ?? ''}',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(_replyTo!['content'] ?? 'Image',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
          onPressed: () => setState(() => _replyTo = null),
        ),
      ]),
    );
  }

  Widget _composer() {
    if (widget.isClosed) {
      return Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text('Event has ended · chat is read-only',
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    // Floating pill composer per spec - borderless, gold send.
    final sendGold = AppColors.primary;
    const navy = Color(0xFF0A1C40);
    const hintBlueGrey = Color(0xFF8E9BB0);
    return Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.of(context).padding.bottom),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          // The OUTER container carries the border (around attach + input + send).
          // The inner TextField has no border or focus outline.
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 22, offset: Offset(0, 6)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Attach (left) - match mock composer (no IconButton min-size)
          InkWell(
            onTap: _uploading ? null : _pickImage,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _uploading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : SvgPicture.asset('assets/icons/attach-icon.svg',
                      width: 22, height: 22,
                      colorFilter: const ColorFilter.mode(navy, BlendMode.srcIn)),
            ),
          ),
          // Textfield (middle) - outer padding mirrors the inactive composer so
          // the placeholder x-position never shifts when switching tabs.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1, maxLines: 5,
                autocorrect: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Message the group...',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 15.5, color: hintBlueGrey, fontWeight: FontWeight.w500),
                ),
                style: GoogleFonts.inter(
                    fontSize: 15.5, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Send (right) - circular gold
          SizedBox(
            width: 54, height: 54,
            child: Material(
              color: _hasText ? sendGold : sendGold.withOpacity(0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending || !_hasText ? null : _send,
                child: Center(
                  child: _sending
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : SvgPicture.asset('assets/icons/send-icon.svg',
                          width: 22, height: 22,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final e in _fullEmojis)
                GestureDetector(
                  onTap: () {
                    final sel = _input.selection;
                    final txt = _input.text;
                    final start = sel.start >= 0 ? sel.start : txt.length;
                    final end = sel.end >= 0 ? sel.end : txt.length;
                    _input.text = txt.replaceRange(start, end, e);
                    _input.selection = TextSelection.collapsed(offset: start + e.length);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 46, height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                    child: _emoji(e, size: 24),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _imagePreviewSheet() {
    final p = _pendingImage!;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _pendingImage = null),
        child: Container(
          color: Colors.black.withOpacity(0.78),
          child: SafeArea(
            child: GestureDetector(
              onTap: () {},
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _pendingImage = null),
                      ),
                      const Spacer(),
                      Text('Send image',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ]),
                  ),
                  Expanded(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(File(p.file.path), fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.of(context).padding.bottom),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          child: TextField(
                            minLines: 1, maxLines: 4,
                            onChanged: (v) => p.caption = v,
                            decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Add a caption…',
                                hintStyle: GoogleFonts.inter(color: AppColors.textTertiary)),
                            style: GoogleFonts.inter(fontSize: 14.5, decorationThickness: 0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploading ? null : _sendPendingImage,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: SvgPicture.asset('assets/icons/send-icon.svg',
                                width: 18, height: 18,
                                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingImage {
  final XFile file;
  String caption;
  _PendingImage({required this.file, required this.caption});
}
