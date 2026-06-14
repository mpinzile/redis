import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/widgets/expanding_search_action.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import '../../widgets/nuru_emoji_picker.dart';
import '../../widgets/inline_voice_player.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/messages_service.dart';
import '../../core/services/uploads_service.dart';
import '../services/public_service_screen.dart';
import '../../core/services/calls_service.dart';
import '../../core/services/call_ui_coordinator.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../providers/auth_provider.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../core/widgets/nuru_refresh.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/services/events_service.dart';
import '../../core/services/social_service.dart';
import '../../core/utils/prefetch_helper.dart';
import '../../core/utils/messages_cache.dart';
import '../calls/voice_call_screen.dart';
import '../../core/widgets/nuru_video_player.dart';
import '../calls/video_call_screen.dart';

/// Messages screen - matches web Messages.tsx design
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<dynamic> _conversations = [];
  bool _loading = true;
  String _search = '';
  Timer? _pollTimer;
  Timer? _searchDebounce;
  String _filter = 'all'; // all | people | vendors | unread | services | attachments
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    // Seed from cache so the list shows instantly on re-entry - the network
    // refresh below then updates it silently in the background.
    final cached = MessagesCache.conversations;
    if (cached != null && cached.isNotEmpty) {
      _conversations = cached;
      _loading = false;
    }
    _loadConversations(silent: cached != null && cached.isNotEmpty);
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadConversations(silent: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_currentUserId == null) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        _currentUserId = auth.user?['id']?.toString();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _search = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _loadConversations());
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await MessagesService.getConversations(search: _search.isNotEmpty ? _search : null);
    if (mounted) {
      setState(() {
        if (!silent) _loading = false;
        if (res['success'] == true) {
          final data = res['data'];
          _conversations = data is List ? data : (data is Map ? (data['conversations'] ?? []) : []);
          // Sort newest first by last_message time or updated_at
          _conversations.sort((a, b) {
            final aTime = _getConvTimestamp(a);
            final bTime = _getConvTimestamp(b);
            return bTime.compareTo(aTime); // newest first
          });
          // Cache for next mount so re-entry is instant.
          if (_search.isEmpty) MessagesCache.conversations = _conversations;
        }
        if (!silent) _loading = false;
      });
    }
  }

  String _getConvTimestamp(dynamic conv) {
    if (conv is! Map) return '';
    final lastMsg = conv['last_message'];
    String time = '';
    if (lastMsg is Map) time = lastMsg['sent_at']?.toString() ?? lastMsg['created_at']?.toString() ?? '';
    if (time.isEmpty) time = conv['updated_at']?.toString() ?? conv['last_message_at']?.toString() ?? conv['created_at']?.toString() ?? '';
    return time;
  }

  /// A conversation is a "vendor" conversation only from the CUSTOMER's
  /// perspective - i.e. there is a service attached AND the current user is
  /// NOT the service owner. The service owner side simply sees a normal
  /// chat with a customer.
  bool _isVendorConv(dynamic conv) {
    if (conv is! Map) return false;
    final svc = conv['service'];
    if (svc is! Map) return false;
    final providerId = svc['provider_id']?.toString();
    if (_currentUserId != null && providerId == _currentUserId) return false;
    return true;
  }

  bool _isOnline(dynamic conv) {
    if (conv is! Map) return false;
    final p = conv['participant'] ?? conv['other_user'] ?? {};
    if (p is Map) {
      return p['is_online'] == true || p['online'] == true;
    }
    return false;
  }

  /// Verified badge logic:
  ///  - Customer viewing a vendor chat → show only if the SERVICE is verified
  ///  - Otherwise (normal chat, or vendor viewing a customer) → show only if
  ///    the other person is identity-verified
  bool _isVerified(dynamic conv) {
    if (conv is! Map) return false;
    if (_isVendorConv(conv)) {
      final svc = conv['service'];
      if (svc is Map) {
        return svc['is_verified'] == true || svc['verified'] == true;
      }
      return false;
    }
    final p = conv['participant'] ?? conv['other_user'] ?? {};
    if (p is Map) {
      return p['is_verified'] == true || p['is_identity_verified'] == true || p['verified'] == true;
    }
    return false;
  }

  bool _lastMessageMine(dynamic conv) {
    if (conv is! Map) return false;
    final lm = conv['last_message'];
    if (lm is Map) return lm['is_mine'] == true;
    return false;
  }

  String _formatConvTime(dynamic conv) {
    final raw = _getConvTimestamp(conv);
    if (raw.isEmpty) return '';
    DateTime? dt;
    try {
      // Server timestamps are UTC but often arrive without a 'Z' suffix.
      // Append one when missing so DateTime.parse interprets them as UTC
      // and `.toLocal()` produces the user's wall-clock time.
      final hasTz = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
      dt = DateTime.parse(hasTz ? raw : '${raw}Z').toLocal();
    } catch (_) {
      return '';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) {
      // Today → time like 10:30 AM
      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ap';
    } else if (diff == 1) {
      return 'Yesterday';
    } else if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    }
  }

  List<dynamic> get _filteredConversations {
    Iterable<dynamic> src = _conversations;
    switch (_filter) {
      case 'people':
        src = src.where((c) => !_isVendorConv(c));
        break;
      case 'vendors':
        src = src.where((c) => _isVendorConv(c));
        break;
      case 'unread':
        src = src.where((c) => _isUnread(c));
        break;
      case 'services':
        src = src.where((c) => c is Map && (c['service'] != null || c['service_id'] != null || c['service_context'] != null));
        break;
      case 'attachments':
        src = src.where((c) {
          if (c is! Map) return false;
          final last = c['last_message'];
          if (last is! Map) return false;
          final t = (last['message_type'] ?? '').toString();
          return t == 'image' || t == 'video' || t == 'audio' || t == 'file';
        });
        break;
    }
    return src.toList();
  }

  String _getConversationName(dynamic conv) {
    if (conv is! Map) return 'Unknown';
    final participant = conv['participant'] ?? conv['other_user'] ?? conv['recipient'] ?? {};
    if (participant is Map) {
      final fullName = participant['full_name']?.toString() ?? '';
      if (fullName.isNotEmpty) return fullName;
      final name = participant['name']?.toString() ?? '';
      if (name.isNotEmpty) return name;
      final firstName = participant['first_name']?.toString() ?? '';
      final lastName = participant['last_name']?.toString() ?? '';
      final full = '$firstName $lastName'.trim();
      if (full.isNotEmpty) return full;
      return participant['username']?.toString() ?? 'Unknown';
    }
    return 'Unknown';
  }

  String? _getConversationAvatar(dynamic conv) {
    if (conv is! Map) return null;
    final participant = conv['participant'] ?? conv['other_user'] ?? conv['recipient'] ?? {};
    if (participant is Map) {
      return participant['avatar'] as String?;
    }
    return null;
  }

  bool _isImageUrlPreview(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.jpg') || u.endsWith('.jpeg') || u.endsWith('.png') ||
        u.endsWith('.webp') || u.endsWith('.gif') || u.endsWith('.heic');
  }

  bool _isAudioUrlPreview(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.m4a') || u.endsWith('.mp3') || u.endsWith('.aac') ||
        u.endsWith('.wav') || u.endsWith('.ogg') || u.endsWith('.opus');
  }

  bool _isVideoUrlPreview(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm') ||
        u.endsWith('.mkv') || u.endsWith('.3gp');
  }

  /// Returns a preview descriptor for a message used in the conversation
  /// list. When the message has no text but contains an attachment, we
  /// surface an icon + label like "Photo", "Voice message" or "Video"
  /// so users can see at a glance what was shared.
  ({IconData? icon, String text}) _previewFor(Map msg, {bool prefixYou = false}) {
    final content = msg['content']?.toString() ?? msg['message_text']?.toString() ?? '';
    if (content.isNotEmpty) {
      return (icon: null, text: prefixYou ? 'You: $content' : content);
    }
    final urls = _extractAttachmentUrls(msg['attachments']);
    final imgUrl = msg['image_url']?.toString() ?? '';
    final all = <String>[if (imgUrl.isNotEmpty) imgUrl, ...urls];
    if (all.isEmpty) return (icon: null, text: '');
    final hasAudio = all.any(_isAudioUrlPreview);
    final hasVideo = all.any(_isVideoUrlPreview);
    final hasImage = all.any(_isImageUrlPreview);
    String label;
    IconData icon;
    if (hasAudio) { label = 'Voice message'; icon = Icons.mic_rounded; }
    else if (hasVideo) { label = 'Video'; icon = Icons.videocam_rounded; }
    else if (hasImage) { label = 'Photo'; icon = Icons.image_rounded; }
    else { label = 'Attachment'; icon = Icons.attach_file_rounded; }
    return (icon: icon, text: prefixYou ? 'You: $label' : label);
  }

  String _getLastMessage(dynamic conv) {
    if (conv is! Map) return '';
    final lastMsg = conv['last_message'];
    if (lastMsg is Map) {
      return _previewFor(lastMsg, prefixYou: lastMsg['is_mine'] == true).text;
    }
    if (lastMsg is String) return lastMsg;
    return conv['last_message_text']?.toString() ?? '';
  }

  ({IconData? icon, String text}) _getLastMessagePreview(dynamic conv) {
    if (conv is! Map) return (icon: null, text: '');
    final lastMsg = conv['last_message'];
    if (lastMsg is Map) {
      return _previewFor(lastMsg, prefixYou: lastMsg['is_mine'] == true);
    }
    if (lastMsg is String) return (icon: null, text: lastMsg);
    return (icon: null, text: conv['last_message_text']?.toString() ?? '');
  }

  /// Returns the second-most-recent message preview, used to render the
  /// "two-line" preview in the conversation cards (matches the design).
  ({IconData? icon, String text}) _getPreviousMessagePreview(dynamic conv) {
    if (conv is! Map) return (icon: null, text: '');
    final prev = conv['previous_message'];
    if (prev is Map) return _previewFor(prev, prefixYou: prev['is_mine'] == true);
    return (icon: null, text: '');
  }

  List<String> _extractAttachmentUrls(dynamic attachments) {
    if (attachments is! List) return const [];
    return attachments
        .map<String>((item) {
          if (item is String) return item;
          if (item is Map) {
            return item['url']?.toString() ??
                item['image_url']?.toString() ??
                item['file_url']?.toString() ??
                '';
          }
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();
  }

  String _getTimeAgo(dynamic conv) {
    if (conv is! Map) return '';
    final lastMsg = conv['last_message'];
    String time = '';
    if (lastMsg is Map) {
      time = lastMsg['sent_at']?.toString() ?? '';
    }
    if (time.isEmpty) {
      time = conv['updated_at']?.toString() ?? conv['last_message_at']?.toString() ?? '';
    }
    if (time.isEmpty) return '';
    return SocialService.getTimeAgo(time);
  }

  bool _isUnread(dynamic conv) {
    if (conv is! Map) return false;
    return conv['unread_count'] != null && conv['unread_count'] > 0;
  }

  int _getUnreadCount(dynamic conv) {
    if (conv is! Map) return 0;
    return conv['unread_count'] ?? 0;
  }

  void _showNewConversationSheet() {
    final searchCtrl = TextEditingController();
    List<dynamic> searchResults = [];
    bool searching = false;
    Timer? debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(context.tr('new_conversation'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(context.tr('search_for_person'), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
                const SizedBox(height: 16),
                Container(
                  height: 46,
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: context.tr('search_hint'),
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textHint),
                      border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SvgPicture.asset('assets/icons/search-icon.svg', width: 20, height: 20,
                          colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
                      ),
                      isDense: true,
                    ),
                    onChanged: (q) {
                      debounce?.cancel();
                      if (q.trim().length < 2) { setModalState(() { searchResults = []; }); return; }
                      debounce = Timer(const Duration(milliseconds: 400), () async {
                        setModalState(() => searching = true);
                        final res = await EventsService.searchUsers(q.trim());
                        if (ctx.mounted) {
                          setModalState(() {
                            searching = false;
                            if (res['success'] == true) {
                              final data = res['data'];
                              // API returns { items: [...] } - handle all response shapes
                              searchResults = data is List ? data : (data is Map ? (data['items'] ?? data['users'] ?? data['results'] ?? []) : []);
                            }
                          });
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (searching)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                if (!searching && searchResults.isEmpty && searchCtrl.text.length >= 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text(context.tr('no_users_found'), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary))),
                  ),
                if (searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (_, i) {
                        final user = searchResults[i] as Map<String, dynamic>;
                        final fullName = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                        final name = user['full_name']?.toString() ?? (fullName.isNotEmpty ? fullName : user['username']?.toString() ?? 'Unknown');
                        final avatar = user['avatar']?.toString();
                        final subtitle = user['email']?.toString() ?? user['phone']?.toString() ?? '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.04),
                            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                            child: (avatar == null || avatar.isEmpty) ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark)) : null,
                          ),
                          title: Text(name.isNotEmpty ? name : 'Unknown', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)) : null,
                          onTap: () => _startConversation(ctx, user),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _startConversation(BuildContext sheetCtx, Map<String, dynamic> user) async {
    // Check existing conversation
    final existingConv = _conversations.firstWhere(
      (c) {
        if (c is! Map) return false;
        final p = c['participant'] ?? c['other_user'] ?? {};
        if (p is Map) return p['id']?.toString() == user['id']?.toString();
        return false;
      },
      orElse: () => null,
    );

    final rawName = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    final userName = user['full_name']?.toString() ??
        (rawName.isNotEmpty ? rawName : user['username']?.toString() ?? 'Unknown');
    final avatarUrl = user['avatar']?.toString();
    final bool isVerifiedUser = user['is_verified'] == true ||
        user['verified'] == true ||
        user['kyc_verified'] == true;

    if (existingConv != null) {
      Navigator.pop(sheetCtx);
      final name = _getConversationName(existingConv);
      final avatar = _getConversationAvatar(existingConv);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          conversationId: existingConv['id'].toString(),
          name: name,
          avatar: avatar,
          isVerified: _isVerified(existingConv) || isVerifiedUser,
        ),
      ));
      return;
    }

    // Pop the picker sheet and go straight into the chat - no intermediate
    // "Say hello" sheet. This matches the WhatsApp-style flow the user asked
    // for and avoids the multiple-pages-to-close issue.
    Navigator.pop(sheetCtx);

    final res = await MessagesService.startConversation(
      recipientId: user['id'].toString(),
    );
    if (!mounted) return;
    if (res['success'] != true || res['data'] == null) {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not start conversation');
      return;
    }
    final convId = res['data']['id']?.toString();
    if (convId == null) return;
    // Refresh list in background so the new conversation appears in it.
    _loadConversations(silent: true);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatDetailScreen(
        conversationId: convId,
        name: userName,
        avatar: avatarUrl,
        isVerified: isVerifiedUser,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      // Header - matches Find Services screen exactly: arrow_back + centered
      // "Messages" title. The only addition is a "+" action on the right for
      // starting a new conversation.
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              size: 24, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Chat',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _showNewConversationSheet,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/plus-icon.svg',
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // Search bar - matches Find Services screen style
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                ),
                child: Row(children: [
                  const Icon(Icons.search_rounded, size: 20, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: _onSearchChanged,
                      cursorColor: Colors.black,
                      textAlignVertical: TextAlignVertical.center,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        hintText: context.tr('search_conversations'),
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // Filter chips: All | People | Vendors | filter icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: _filterChip('all', context.tr('all'), 'assets/icons/chat-icon.svg')),
                  const SizedBox(width: 10),
                  Expanded(child: _filterChip('people', context.tr('people'), 'assets/icons/user-icon.svg')),
                  const SizedBox(width: 10),
                  Expanded(child: _filterChip('vendors', context.tr('vendors'), 'assets/icons/package-icon.svg')),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: _filter == 'all' || _filter == 'people' || _filter == 'vendors'
                            ? AppColors.surface
                            : AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _filter == 'all' || _filter == 'people' || _filter == 'vendors'
                              ? AppColors.border
                              : AppColors.primary,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/menu-icon.svg',
                          width: 18, height: 18,
                          colorFilter: ColorFilter.mode(
                            _filter == 'all' || _filter == 'people' || _filter == 'vendors'
                                ? AppColors.textPrimary
                                : AppColors.primary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : _filteredConversations.isEmpty
                      ? _buildEmpty(
                          // Distinguish "no DB data" from "filter/search returned nothing".
                          isFiltered: _conversations.isNotEmpty &&
                              (_filter != 'all' || _search.isNotEmpty),
                        )
                      : NuruRefresh(
                          onRefresh: () => _loadConversations(silent: true),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _filteredConversations.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _conversationCard(_filteredConversations[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _getServiceContext(dynamic conv) {
    if (conv is! Map) return '';
    final service = conv['service'] ?? conv['service_context'];
    if (service is Map) {
      return service['title']?.toString() ?? service['name']?.toString() ?? '';
    }
    return conv['service_title']?.toString() ?? conv['service_name']?.toString() ?? '';
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        const options = [
          {'value': 'all', 'label': 'All', 'desc': 'Every chat', 'icon': 'assets/icons/chat-icon.svg'},
          {'value': 'unread', 'label': 'Unread', 'desc': 'New messages', 'icon': 'assets/icons/bell-icon.svg'},
          {'value': 'people', 'label': 'People', 'desc': 'Direct chats', 'icon': 'assets/icons/user-icon.svg'},
          {'value': 'vendors', 'label': 'Vendors', 'desc': 'Service providers', 'icon': 'assets/icons/package-icon.svg'},
          {'value': 'services', 'label': 'Services', 'desc': 'Bookings & inquiries', 'icon': 'assets/icons/package-icon.svg'},
          {'value': 'attachments', 'label': 'Attachments', 'desc': 'Photos, files', 'icon': 'assets/icons/chat-icon.svg'},
        ];
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            String current = _filter;
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(4))),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                        child: Row(children: [
                          Text('Filter', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                          const Spacer(),
                          if (_filter != 'all')
                            GestureDetector(
                              onTap: () { setState(() => _filter = 'all'); Navigator.pop(ctx); },
                              child: Text('Reset', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Text(
                          'Narrow your inbox to exactly what you need.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.4,
                          children: options.map((o) {
                            final v = o['value']!;
                            final sel = current == v;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _filter = v);
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: sel ? AppColors.primarySoft : AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sel ? AppColors.primary : AppColors.border,
                                    width: sel ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34, height: 34,
                                      decoration: BoxDecoration(
                                        color: sel ? Colors.white : AppColors.surfaceVariant,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: SvgPicture.asset(
                                          o['icon']!,
                                          width: 16, height: 16,
                                          colorFilter: ColorFilter.mode(
                                            sel ? AppColors.primary : AppColors.textSecondary,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            o['label']!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            o['desc']!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.textTertiary,
                                              height: 1.25,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterChip(String value, String label, String svgAsset) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              svgAsset,
              width: 16, height: 16,
              colorFilter: ColorFilter.mode(
                selected ? AppColors.primary : AppColors.textSecondary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationCard(dynamic conv) {
    final name = _getConversationName(conv);
    final avatar = _getConversationAvatar(conv);
    final lastPreview = _getLastMessagePreview(conv);
    final prevPreview = _getPreviousMessagePreview(conv);
    final lastMsg = lastPreview.text;
    final prevMsg = prevPreview.text;
    final time = _formatConvTime(conv);
    final unread = _isUnread(conv);
    final unreadCount = _getUnreadCount(conv);
    final isVendor = _isVendorConv(conv);
    final isOnline = _isOnline(conv);
    final isVerified = _isVerified(conv);
    // ignore: unused_local_variable
    final lastIsMine = _lastMessageMine(conv);

    final convId = conv is Map ? conv['id']?.toString() : null;
    return PrefetchOnVisible(
      onVisible: () {
        if (convId == null || convId.isEmpty) return;
        PrefetchHelper.prefetch('conv:$convId', () async {
          final results = await Future.wait([
            MessagesService.getMessages(convId),
            CallsService.listForConversation(convId),
          ]);
          final res = results[0] as Map<String, dynamic>;
          final calls = results[1] as List<dynamic>;
          if (res['success'] == true) {
            final data = res['data'];
            final List msgs = data is Map
                ? ((data['messages'] as List?) ?? const [])
                : (data is List ? data : const []);
            MessagesCache.putMessages(convId, msgs);
          }
          MessagesCache.putCalls(convId, calls);
        });
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: () {
            if (convId != null && convId.isNotEmpty) {
              _showConversationActions(convId, name);
            }
          },
          onTap: () {
            if (convId != null) {
              final svc = (conv is Map ? conv['service'] : null);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  conversationId: convId,
                  name: name,
                  avatar: avatar,
                  isVendor: isVendor,
                  isVerifiedVendor: isVendor && _isVerified(conv),
                  isVerified: _isVerified(conv),
                  service: svc is Map ? Map<String, dynamic>.from(svc) : null,
                  isOnline: !isVendor && _isOnline(conv),
                ),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with online dot
                SizedBox(
                  width: 48, height: 48,
                  child: Stack(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.04),
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 48, height: 48,
                            child: avatar != null && avatar.isNotEmpty
                                ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, errorWidget: (_, __, ___) => _avatarFallback(name), placeholder: (_, __) => _avatarFallback(name))
                                : _avatarFallback(name),
                          ),
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surface, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Content with name + two-line preview (left side).
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.2,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                          ],
                          if (isVendor) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE9A3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Vendor',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7A5A00),
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (lastPreview.icon != null) ...[
                            Icon(lastPreview.icon, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              lastMsg.isEmpty ? 'No messages yet' : lastMsg,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                height: 1.35,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (prevMsg.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (prevPreview.icon != null) ...[
                              Icon(prevPreview.icon, size: 13, color: AppColors.textTertiary),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                prevMsg,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w400,
                                  height: 1.35,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Trailing column: time on top, unread badge below - both
                // anchored to the same right edge for clean vertical alignment
                // across all rows (no zig-zag).
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: unread ? AppColors.primary : AppColors.textTertiary,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryDark, height: 1.0),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return const NuruSkeletonList(
      itemCount: 8,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
      physics: AlwaysScrollableScrollPhysics(),
    );
  }

  Widget _buildEmpty({bool isFiltered = false}) {
    final title = isFiltered
        ? 'No matching conversations'
        : context.tr('no_conversations');
    final subtitle = isFiltered
        ? 'Try a different filter or search term'
        : context.tr('start_conversation');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(18)),
              child: Center(
                child: SvgPicture.asset(
                  isFiltered ? 'assets/icons/search-icon.svg' : 'assets/icons/chat-icon.svg',
                  width: 28, height: 28,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4)),
            const SizedBox(height: 20),
            if (isFiltered)
              GestureDetector(
                onTap: () => setState(() { _filter = 'all'; _search = ''; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('Clear filters', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2)),
                ),
              )
            else
              GestureDetector(
                onTap: _showNewConversationSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text(context.tr('new_message'), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet shown when the user long-presses a conversation in the list.
  /// WhatsApp-style: lets the user delete (hide) the chat from their inbox
  /// without affecting the other participant's view.
  void _showConversationActions(String convId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  name,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: SvgPicture.asset(
                  'assets/icons/delete-icon.svg',
                  width: 22, height: 22,
                  colorFilter: const ColorFilter.mode(Color(0xFFE03131), BlendMode.srcIn),
                ),
                title: Text(
                  context.tr('delete_conversation'),
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFE03131)),
                ),
                subtitle: Text(
                  context.tr('delete_conversation_subtitle'),
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmDeleteConversation(convId, name);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteConversation(String convId, String name) {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('delete_conversation'),
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
          context.tr('delete_conversation_confirm').replaceAll('{name}', name),
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(context.tr('cancel'), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dctx).pop();
              // Optimistic removal from list + cache.
              setState(() {
                _conversations.removeWhere((c) => c is Map && c['id']?.toString() == convId);
                MessagesCache.conversations = List<dynamic>.from(_conversations);
              });
              final res = await MessagesService.hideConversation(convId);
              if (!mounted) return;
              if (res['success'] != true) {
                // Roll back by re-fetching on failure.
                _loadConversations(silent: true);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(res['message']?.toString() ?? 'Failed to remove'),
                ));
              }
            },
            child: Text(
              context.tr('delete'),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFE03131)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT DETAIL SCREEN
// Vendor and normal-user variants share most behavior but differ visually:
//   • Vendor → cream "verified vendor" trust banner + service context card +
//     "Quote / Files / Photos / Payment" action chips below composer.
//   • Normal user → "end-to-end encrypted" banner + "Gallery / Camera / File /
//     Location" action chips. Online status is shown under the name.
// ─────────────────────────────────────────────────────────────────────────────
class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String name;
  final String? avatar;
  final bool isVendor;
  final bool isVerifiedVendor;
  final bool isVerified;
  final bool isOnline;
  final Map<String, dynamic>? service;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.name,
    this.avatar,
    this.isVendor = false,
    this.isVerifiedVendor = false,
    this.isVerified = false,
    this.isOnline = false,
    this.service,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _threadSearchCtrl = TextEditingController();
  final FocusNode _threadSearchFocus = FocusNode();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _showThreadSearch = false;
  String _threadSearch = '';
  Timer? _pollTimer;
  String? _currentUserId;
  // Multiple selected attachments staged for sending
  final List<File> _selectedImages = [];
  Map<String, dynamic>? _replyTo;
  bool _conversationEncrypted = true; // server flag

  // ── Voice notes ──────────────────────────────────────────────────────────
  // Uses the `record` package: tap-and-hold-to-record on the mic button. We
  // upload the resulting m4a file as a regular attachment so the server side
  // doesn't need any audio-specific changes (backward compatible).
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  // ── Emoji picker ─────────────────────────────────────────────────────────
  bool _showEmojiPicker = false;
  final FocusNode _composerFocus = FocusNode();

  // Scroll / new-message tracking (WhatsApp-like behavior)
  bool _isAtBottom = true;
  int _newMessagesCount = 0;
  bool _initialScrolled = false;
  bool _firstServerLoadDone = false;
  bool _notificationsMuted = false;
  bool _blocked = false;
  final Map<String, String> _localCreatedAtByServerId = {};

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _extractAttachmentUrls(dynamic attachments) {
    if (attachments is! List) return const [];
    return attachments
        .map<String>((item) {
          if (item is String) return item;
          if (item is Map) {
            return item['url']?.toString() ??
                item['image_url']?.toString() ??
                item['file_url']?.toString() ??
                '';
          }
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();
  }

  bool _isImageUrl(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.jpg') || u.endsWith('.jpeg') || u.endsWith('.png') ||
        u.endsWith('.webp') || u.endsWith('.gif') || u.endsWith('.heic');
  }

  bool _isAudioUrl(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.m4a') || u.endsWith('.mp3') || u.endsWith('.aac') ||
        u.endsWith('.wav') || u.endsWith('.ogg') || u.endsWith('.opus');
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm') ||
        u.endsWith('.mkv') || u.endsWith('.3gp');
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    // Seed instantly from cache so the chat opens like WhatsApp - no
    // spinner if we have anything to show.
    final cachedMsgs = MessagesCache.getMessages(widget.conversationId);
    final cachedCalls = MessagesCache.getCalls(widget.conversationId);
    if (cachedMsgs != null && cachedMsgs.isNotEmpty) {
      _messages = [
        ...cachedMsgs,
        ...?cachedCalls?.whereType<Map>().map((c) => {...c, '_type': 'call_log'}),
      ];
      _messages.sort((a, b) {
        final at = a is Map ? (a['created_at']?.toString() ?? a['sent_at']?.toString() ?? '') : '';
        final bt = b is Map ? (b['created_at']?.toString() ?? b['sent_at']?.toString() ?? '') : '';
        final ad = _parseTime(at);
        final bd = _parseTime(bt);
        if (ad != null && bd != null) return ad.compareTo(bd);
        return at.compareTo(bt);
      });
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialScrolled) return;
        _initialScrolled = true;
        _scrollToBottom(animate: false, settleFrames: 5);
      });
    }
    _loadMessages(silent: !_loading);
    MessagesService.markAsRead(widget.conversationId);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages(silent: true));
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final atBottom = (pos.maxScrollExtent - pos.pixels).abs() < 80;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _newMessagesCount = 0;
      });
    } else if (atBottom && _newMessagesCount > 0) {
      setState(() => _newMessagesCount = 0);
    }
  }

  String _timelineTime(dynamic item) {
    if (item is! Map) return '';
    return _stableLocalCreatedAt(item) ??
        item['created_at']?.toString() ??
        item['sent_at']?.toString() ??
        item['started_at']?.toString() ??
        item['answered_at']?.toString() ??
        item['ended_at']?.toString() ??
        '';
  }

  String _nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  bool _isLocalEcho(Map msg) => msg['_optimistic'] == true || msg['_pending_server_sync'] == true;

  String? _stableLocalCreatedAt(Map msg) {
    final inline = msg['_local_created_at']?.toString();
    if (inline != null && inline.isNotEmpty) return inline;
    final serverId = (msg['_server_id'] ?? msg['id'])?.toString();
    if (serverId == null || serverId.isEmpty) return null;
    return _localCreatedAtByServerId[serverId];
  }

  String _messageTime(Map msg) {
    return _stableLocalCreatedAt(msg) ??
        msg['created_at']?.toString() ??
        msg['sent_at']?.toString() ??
        '';
  }

  bool _matchesLocalEcho(Map server, Map opt) {
    if (!_isLocalEcho(opt) || !_isMine(opt)) return false;
    final serverId = server['id']?.toString() ?? '';
    final optId = opt['id']?.toString() ?? '';
    final optServerId = opt['_server_id']?.toString() ?? '';
    if (serverId.isNotEmpty && (serverId == optId || serverId == optServerId)) return true;
    final serverText = (server['content'] ?? server['message_text'] ?? '').toString();
    final optText = (opt['content'] ?? opt['message_text'] ?? '').toString();
    if (serverText != optText) return false;
    final serverUrls = _extractAttachmentUrls(server['attachments']).join('|');
    final optUrls = _extractAttachmentUrls(opt['attachments']).join('|');
    if (serverUrls != optUrls) return false;
    final serverTime = _parseTime(_timelineTime(server));
    final optTime = _parseTime(_timelineTime(opt));
    if (serverTime == null || optTime == null) return true;
    return serverTime.difference(optTime).abs() < const Duration(minutes: 5);
  }

  List<dynamic> _mergeTimeline(List<dynamic> serverMsgs, List<dynamic> taggedCalls, List<Map> localEchoes) {
    final merged = <dynamic>[];
    final consumed = <Map>{};
    for (final msg in serverMsgs) {
      if (msg is Map) {
        Map? match;
        for (final opt in localEchoes) {
          if (!consumed.contains(opt) && _matchesLocalEcho(msg, opt)) {
            match = opt;
            break;
          }
        }
        if (match != null) {
          consumed.add(match);
          final serverId = msg['id']?.toString();
          final localCreatedAt = match['_local_created_at']?.toString() ?? match['created_at']?.toString();
          if (serverId != null && serverId.isNotEmpty && localCreatedAt != null && localCreatedAt.isNotEmpty) {
            _localCreatedAtByServerId[serverId] = localCreatedAt;
          }
          merged.add({
            ...msg,
            'is_sender': true,
            'is_mine': true,
            'sender_id': msg['sender_id'] ?? _currentUserId,
            '_client_key': match['_client_key'] ?? match['id'],
            '_local_created_at': localCreatedAt,
          });
          continue;
        }
      }
      merged.add(msg);
    }
    merged.addAll(taggedCalls);
    merged.addAll(localEchoes.where((opt) => !consumed.contains(opt)));
    return merged;
  }

  void _loadCurrentUserId() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _currentUserId = auth.user?['id']?.toString();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _threadSearchCtrl.dispose();
    _threadSearchFocus.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  // ── Voice recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) AppSnackbar.error(context, 'Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      _recordPath = path;
      _recordDuration = Duration.zero;
      setState(() => _isRecording = true);
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordDuration += const Duration(seconds: 1));
      });
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not start recording');
    }
  }

  Future<void> _cancelRecording() async {
    try { await _recorder.stop(); } catch (_) {}
    _recordTimer?.cancel();
    if (_recordPath != null) {
      try { File(_recordPath!).deleteSync(); } catch (_) {}
    }
    _recordPath = null;
    if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
  }

  Future<void> _stopAndSendRecording() async {
    try {
      final path = await _recorder.stop();
      _recordTimer?.cancel();
      if (mounted) setState(() { _isRecording = false; _recordDuration = Duration.zero; });
      final filePath = path ?? _recordPath;
      if (filePath == null || filePath.isEmpty) return;

      // Local echo so the user sees the voice note instantly while keeping
      // the same stable row when the server copy arrives.
      final optimisticId = 'optimistic_${DateTime.now().millisecondsSinceEpoch}';
      final localCreatedAt = _nowUtcIso();
      final optimistic = {
        'id': optimisticId,
        '_client_key': optimisticId,
        'content': '',
        'sender_id': _currentUserId,
        'is_sender': true,
        'created_at': localCreatedAt,
        '_local_created_at': localCreatedAt,
        'attachments': <String>[],
        '_optimistic': true,
        '_uploading': true,
      };
      if (mounted) {
        setState(() => _messages.add(optimistic));
        _scrollToBottom();
      }

      // Upload + send as attachment - backend treats it as a generic file URL
      // so older clients still display the conversation correctly.
      final uploadRes = await UploadsService.uploadFile(filePath);
      if (uploadRes['success'] != true) {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m is Map && m['id'] == optimisticId));
          AppSnackbar.error(context, 'Failed to upload voice note');
        }
        return;
      }
      final data = uploadRes['data'];
      String? url;
      if (data is Map) {
        url = data['url']?.toString() ?? data['file_url']?.toString();
      }
      url ??= uploadRes['url']?.toString();
      if (url == null || url.isEmpty) {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m is Map && m['id'] == optimisticId));
        }
        return;
      }

      // Update placeholder with the real URL while server confirms
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m is Map && m['id'] == optimisticId);
          if (idx >= 0) {
            (_messages[idx] as Map)['attachments'] = [url];
            (_messages[idx] as Map)['_uploading'] = false;
          }
        });
      }

      final res = await MessagesService.sendMessage(
        widget.conversationId,
        content: '',
        attachments: [url],
        encryptionVersion: _conversationEncrypted ? 'v1' : 'plain',
      );
      _recordPath = null;
      if (mounted) {
        if (res['success'] == true && res['data'] is Map) {
          final idx = _messages.indexWhere((m) => m is Map && m['id'] == optimisticId);
          if (idx >= 0) {
            final realMsg = Map<String, dynamic>.from(res['data'] as Map);
            realMsg['id'] = optimisticId;
            realMsg['_server_id'] = (res['data'] as Map)['id'];
            realMsg['_client_key'] = optimisticId;
            realMsg['_local_created_at'] = localCreatedAt;
            final serverId = realMsg['_server_id']?.toString();
            if (serverId != null && serverId.isNotEmpty) _localCreatedAtByServerId[serverId] = localCreatedAt;
            realMsg['is_sender'] = true;
            realMsg['is_mine'] = true;
            realMsg['sender_id'] = realMsg['sender_id'] ?? _currentUserId;
            realMsg.remove('_optimistic');
            realMsg['_pending_server_sync'] = true;
            setState(() => _messages[idx] = realMsg);
          }
        } else {
          // Reload as a safety net so it appears even if response is unexpected
          _loadMessages(silent: true);
        }
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to send voice note');
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
      if (_showEmojiPicker) {
        FocusScope.of(context).unfocus();
      } else {
        _composerFocus.requestFocus();
      }
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    // Fetch messages (server now embeds call logs in the same response so
    // the timeline arrives in one round-trip - no more "messages first,
    // calls second" flicker).
    final res = await MessagesService.getMessages(widget.conversationId, limit: 100);
    List<dynamic> callLogs = const [];
    if (res['success'] == true && res['data'] is Map) {
      final embedded = (res['data'] as Map)['calls'];
      if (embedded is List) callLogs = embedded;
    }
    // Backward-compat fallback: if the server didn't embed calls, fetch them.
    if (callLogs.isEmpty) {
      callLogs = await CallsService.listForConversation(widget.conversationId);
    }
    if (!mounted) return;

    final prevLastId = _messages.isNotEmpty && _messages.last is Map
        ? (_messages.last as Map)['id']?.toString()
        : null;
    final prevCount = _messages.length;

    setState(() {
      if (!silent) _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        // Server now returns {messages, is_encrypted}; older servers return a
        // bare list. Handle both for backward compatibility.
        List rawMsgs;
        if (data is Map) {
          rawMsgs = (data['messages'] as List?) ?? const [];
          if (data['is_encrypted'] != null) {
            _conversationEncrypted = data['is_encrypted'] == true;
          }
        } else if (data is List) {
          rawMsgs = data;
        } else {
          rawMsgs = const [];
        }
        final serverMsgs = List<dynamic>.from(rawMsgs);

        // Keep local echo rows stable while server refreshes arrive, including
        // messages already acknowledged by POST but not yet returned by poll.
        final localEchoes = _messages.whereType<Map>().where(_isLocalEcho).toList();

        // Tag each call log so the bubble renderer can identify them, then
        // merge with messages and sort chronologically by `created_at`.
        // Preserve any previously-known call_log rows by id so a transient
        // empty/failed /calls fetch never makes them disappear from the UI.
        final priorCalls = _messages
            .whereType<Map>()
            .where((m) => m['_type'] == 'call_log')
            .toList();
        final mergedCallsById = <String, Map>{};
        for (final c in priorCalls) {
          final id = c['id']?.toString();
          if (id != null && id.isNotEmpty) mergedCallsById[id] = c;
        }
        for (final c in callLogs.whereType<Map>()) {
          final id = c['id']?.toString();
          if (id == null || id.isEmpty) continue;
          mergedCallsById[id] = {...c, '_type': 'call_log'};
        }
        final taggedCalls = mergedCallsById.values.toList();

        _messages = _mergeTimeline(serverMsgs, taggedCalls, localEchoes);
        // Sort by parsed local DateTime - string compare can break when
        // server timestamps mix tz-aware and naive formats, which is what
        // caused call rows to always appear at the top of the thread.
        _messages.sort((a, b) {
          final at = _timelineTime(a);
          final bt = _timelineTime(b);
          final ad = _parseTime(at);
          final bd = _parseTime(bt);
          if (ad != null && bd != null) return ad.compareTo(bd);
          return at.compareTo(bt);
        });

        // Persist for instant re-entry next time. Cache the merged call set
        // (not just the latest server response) so cache stays authoritative.
        MessagesCache.putMessages(widget.conversationId, serverMsgs);
        MessagesCache.putCalls(widget.conversationId, taggedCalls);
      }
    });

    // Count newly arrived messages (from others) since last poll
    int newFromOthers = 0;
    if (silent && prevLastId != null) {
      bool sawPrev = false;
      for (final m in _messages) {
        if (m is! Map) continue;
        if (!sawPrev) {
          if (m['id']?.toString() == prevLastId) sawPrev = true;
          continue;
        }
        if (!_isMine(m)) newFromOthers++;
      }
    }

    if (!silent && !_initialScrolled) {
      _initialScrolled = true;
      _firstServerLoadDone = true;
      _scrollToBottom(animate: false, settleFrames: 5);
    } else if (!_firstServerLoadDone) {
      // First server response after cache-seeded scroll: snap silently to
      // bottom without animation so the user never sees a second scroll.
      _firstServerLoadDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } else if (silent) {
      if (_isAtBottom) {
        if (_messages.length > prevCount) _scrollToBottom();
      } else if (newFromOthers > 0) {
        setState(() => _newMessagesCount += newFromOthers);
      }
      // The user is currently inside this conversation, so any new
      // incoming messages from the other participant should NOT count as
      // unread. Tell the backend right away - otherwise the conversations
      // list keeps showing a stale unread badge until the user backs out
      // and re-opens the thread.
      if (newFromOthers > 0) {
        MessagesService.markAsRead(widget.conversationId);
      }
    }
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    final selected = List<File>.from(_selectedImages);
    if ((text.isEmpty && selected.isEmpty) || _sending) return;

    if (mounted) setState(() => _sending = true);

    // Upload all selected images sequentially.
    final List<String> uploadedUrls = [];
    for (final file in selected) {
      final uploadRes = await UploadsService.uploadFile(file.path);
      if (!mounted) return;
      if (uploadRes['success'] != true) {
        setState(() => _sending = false);
        AppSnackbar.error(
          context,
          uploadRes['message']?.toString() ?? 'Failed to upload attachment',
        );
        return;
      }
      final data = uploadRes['data'];
      String? url;
      if (data is Map) {
        url = data['url']?.toString() ?? data['file_url']?.toString();
      }
      url ??= uploadRes['url']?.toString();
      if (url != null && url.isNotEmpty) uploadedUrls.add(url);
    }

    final replyTo = _replyTo;
    _msgCtrl.clear();
    final optimisticId = 'optimistic_${DateTime.now().millisecondsSinceEpoch}';
    final localCreatedAt = _nowUtcIso();

    final optimisticMsg = {
      'id': optimisticId,
      'content': text,
      'sender_id': _currentUserId,
      'is_sender': true,
      'created_at': localCreatedAt,
      '_local_created_at': localCreatedAt,
      if (uploadedUrls.isNotEmpty) 'attachments': uploadedUrls,
      if (replyTo != null) 'reply_to_id': replyTo['id'],
      if (replyTo != null)
        'reply_snapshot': {
          'text': (replyTo['content'] ?? replyTo['message_text'] ?? '').toString(),
          'sender': replyTo['_sender_name']?.toString() ?? '',
        },
      '_optimistic': true,
    };
    optimisticMsg['_client_key'] = optimisticMsg['id'];
    setState(() {
      _selectedImages.clear();
      _replyTo = null;
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    final res = await MessagesService.sendMessage(
      widget.conversationId,
      content: text,
      attachments: uploadedUrls.isNotEmpty ? uploadedUrls : null,
      replyToId: replyTo != null ? replyTo['id']?.toString() : null,
      // Transport-framing flag. Backend stores it; payload itself is still
      // the same plaintext, so older clients keep working.
      encryptionVersion: _conversationEncrypted ? 'v1' : 'plain',
    );
    if (mounted) {
      setState(() => _sending = false);
      if (res['success'] == true) {
        final realMsg = res['data'];
        if (realMsg is Map) {
          final idx = _messages.indexWhere((m) => m is Map && m['id'] == optimisticId);
          if (idx >= 0) {
            final merged = Map<String, dynamic>.from(realMsg);
            merged['id'] = optimisticId;
            merged['_server_id'] = realMsg['id'];
            merged['_client_key'] = optimisticId;
            merged['_local_created_at'] = localCreatedAt;
            final serverId = merged['_server_id']?.toString();
            if (serverId != null && serverId.isNotEmpty) _localCreatedAtByServerId[serverId] = localCreatedAt;
            merged['is_sender'] = true;
            merged['is_mine'] = true;
            merged['sender_id'] = merged['sender_id'] ?? _currentUserId;
            merged.remove('_optimistic');
            merged['_pending_server_sync'] = true;
            _messages[idx] = merged;
            setState(() {});
          }
        }
      } else {
        final idx = _messages.indexWhere((m) => m is Map && m['id'] == optimisticId);
        if (idx >= 0) {
          _messages[idx] = {
            ...optimisticMsg,
            '_failed': true,
            'content': text.isNotEmpty ? '⚠ $text' : '⚠ Attachment failed to send',
          };
          setState(() {});
        }
        AppSnackbar.error(
          context,
          res['message']?.toString() ?? 'Failed to send message',
        );
      }
    }
  }

  // ── Attachment pickers ────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(maxWidth: 1600);
      if (picked.isNotEmpty && mounted) {
        setState(() {
          // Cap attachments at 10 to match upload limits.
          for (final p in picked) {
            if (_selectedImages.length >= 10) break;
            _selectedImages.add(File(p.path));
          }
        });
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Could not open gallery');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600);
      if (picked != null && mounted) {
        setState(() => _selectedImages.add(File(picked.path)));
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not open camera');
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (res == null || res.files.isEmpty || !mounted) return;
      // Files are uploaded as attachments; UI shows them as tiles.
      // For the "images only for now" rule we still let the user attach any
      // file but only render image previews - non-image files appear as a
      // generic attachment chip in the bubble.
      final files = res.files.where((f) => f.path != null).map((f) => File(f.path!));
      setState(() {
        for (final f in files) {
          if (_selectedImages.length >= 10) break;
          _selectedImages.add(f);
        }
      });
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not pick file');
    }
  }

  Future<void> _shareLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      LocationPermission p = perm;
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever || p == LocationPermission.denied) {
        if (mounted) AppSnackbar.error(context, 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      // Send as a text message with a maps URL - survives any client.
      final url = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
      _msgCtrl.text = '📍 My location: $url';
      setState(() {});
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not get location');
    }
  }

  void _showQuoteSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send a quote',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  prefixText: 'TSh ',
                  prefixStyle: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary),
                  hintText: 'Amount',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final amt = controller.text.trim();
                    if (amt.isEmpty) return;
                    Navigator.pop(ctx);
                    _msgCtrl.text = '💼 Quote: TSh $amt';
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Attach quote', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _removeSelectedImage(int index) {
    setState(() {
      if (index >= 0 && index < _selectedImages.length) {
        _selectedImages.removeAt(index);
      }
    });
  }

  void _scrollToBottom({bool animate = true, int settleFrames = 1}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animate) {
        _scrollCtrl.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else {
        _scrollCtrl.jumpTo(target);
      }
      if (settleFrames > 1) {
        Future<void>.delayed(const Duration(milliseconds: 16), () {
          if (mounted) _scrollToBottom(animate: false, settleFrames: settleFrames - 1);
        });
      }
      if (mounted) {
        setState(() {
          _isAtBottom = true;
          _newMessagesCount = 0;
        });
      }
    });
  }

  bool _isMine(Map msg) {
    if (_isLocalEcho(msg)) return true;
    if (msg['is_sender'] == true) return true;
    if (msg['is_mine'] == true) return true;
    final senderId = msg['sender_id']?.toString() ?? '';
    if (_currentUserId != null && _currentUserId!.isNotEmpty && senderId == _currentUserId) return true;
    final sender = msg['sender'];
    if (sender is Map) {
      final sId = sender['id']?.toString() ?? '';
      if (_currentUserId != null && sId == _currentUserId) return true;
    }
    return false;
  }

  // ignore: unused_element
  String _getDayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(d.year, d.month, d.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  DateTime? _parseTime(String? time) {
    if (time == null || time.isEmpty) return null;
    try {
      return DateTime.parse(time.endsWith('Z') || time.contains('+') ? time : '${time}Z').toLocal();
    } catch (_) {
      return null;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(topPadding),
          if (_showThreadSearch) _buildThreadSearchBar(),

          Expanded(
            child: Stack(
              children: [
                _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : _buildMessagesList(),
                if (!_loading && !_isAtBottom)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _buildScrollToBottomPill(),
                  ),
                if (_showThreadSearch) _buildSearchNav(),
              ],
            ),
          ),

          _buildComposer(bottomPadding),
        ],
      ),
    );
  }

  void _openContactInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 38, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.06),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: widget.avatar != null && widget.avatar!.isNotEmpty
                          ? CachedNetworkImage(imageUrl: widget.avatar!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _fallbackAvatar(), placeholder: (_, __) => _fallbackAvatar())
                          : Center(
                              child: Text(
                                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                                style: GoogleFonts.inter(fontSize: 42, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            widget.name,
                            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2),
                            textAlign: TextAlign.center,
                          ),
                          if (widget.isVerified || widget.isVerifiedVendor)
                            const Icon(Icons.verified_rounded, size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isVendor
                          ? 'Vendor • Typically replies in a few minutes'
                          : (widget.isOnline ? 'Online' : 'Last seen recently'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _contactAction(
                          icon: 'assets/icons/call-icon.svg',
                          label: 'Audio',
                          onTap: () { Navigator.pop(ctx); _startVoiceCall(); },
                        ),
                        const SizedBox(width: 28),
                        _contactAction(
                          icon: 'assets/icons/video-icon.svg',
                          label: 'Video',
                          onTap: () { Navigator.pop(ctx); _startVideoCall(); },
                        ),
                        const SizedBox(width: 28),
                        _contactAction(
                          icon: 'assets/icons/chat-icon.svg',
                          label: 'Search',
                          onTap: () {
                            Navigator.pop(ctx);
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _showThreadSearch = true);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _threadSearchFocus.requestFocus();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(height: 1, color: AppColors.borderLight),
                    _contactRow(
                      svg: 'assets/icons/shield-icon.svg',
                      title: 'Encryption',
                      subtitle: 'Messages are end-to-end encrypted.',
                    ),
                    Container(height: 1, color: AppColors.borderLight),
                    StatefulBuilder(
                      builder: (ctx2, setSt) => _contactRow(
                        svg: 'assets/icons/bell-icon.svg',
                        title: 'Notifications',
                        subtitle: _notificationsMuted ? 'Muted' : 'On',
                        trailing: Switch(
                          value: !_notificationsMuted,
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            setSt(() => _notificationsMuted = !v);
                            setState(() {});
                            AppSnackbar.success(
                              context,
                              v ? 'Notifications enabled' : 'Notifications muted',
                            );
                          },
                        ),
                      ),
                    ),
                    Container(height: 1, color: AppColors.borderLight),
                    _contactRow(
                      svg: 'assets/icons/photos-icon.svg',
                      title: 'Media, links and docs',
                      subtitle: 'Shared in this conversation',
                      onTap: () {
                        Navigator.pop(ctx);
                        _openMediaGallery();
                      },
                    ),
                    Container(height: 1, color: AppColors.borderLight),
                    _contactRow(
                      svg: 'assets/icons/block-icon.svg',
                      title: _blocked ? 'Unblock ${widget.name}' : 'Block ${widget.name}',
                      subtitle: _blocked
                          ? 'You have blocked this contact'
                          : "You won't receive messages or calls",
                      destructive: true,
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmToggleBlock();
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _contactAction({required String icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            child: Center(
              child: SvgPicture.asset(
                icon,
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _contactRow({
    required String svg,
    required String title,
    required String subtitle,
    bool destructive = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final color = destructive ? const Color(0xFFD93B3B) : AppColors.textPrimary;
    final iconColor = destructive ? color : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              svg,
              width: 20, height: 20,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, height: 1.3)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _confirmToggleBlock() {
    final blocking = !_blocked;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          blocking ? 'Block ${widget.name}?' : 'Unblock ${widget.name}?',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          blocking
              ? "Blocked contacts can't message or call you. You can unblock them anytime."
              : 'You will be able to send and receive messages and calls again.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _blocked = blocking);
              AppSnackbar.success(
                context,
                blocking ? '${widget.name} blocked' : '${widget.name} unblocked',
              );
            },
            child: Text(
              blocking ? 'Block' : 'Unblock',
              style: GoogleFonts.inter(color: const Color(0xFFD93B3B), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _openMediaGallery() {
    // Collect all attachments from messages, classifying by URL extension.
    final List<Map<String, String>> media = [];
    final List<String> audios = [];
    for (final m in _messages) {
      if (m is! Map) continue;
      for (final url in _extractAttachmentUrls(m['attachments'])) {
        if (_isImageUrl(url)) {
          media.add({'type': 'image', 'url': url});
        } else if (_isVideoUrl(url)) {
          media.add({'type': 'video', 'url': url});
        } else if (_isAudioUrl(url)) {
          audios.add(url);
        } else {
          media.add({'type': 'file', 'url': url});
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Text('Media, links and docs',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const Spacer(),
                    Text('${media.length + audios.length} item${(media.length + audios.length) == 1 ? '' : 's'}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Expanded(
                child: (media.isEmpty && audios.isEmpty)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'assets/icons/photos-icon.svg',
                                width: 36, height: 36,
                                colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn),
                              ),
                              const SizedBox(height: 12),
                              Text('No shared media yet',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text('Photos, audio and files you share will appear here.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, height: 1.4)),
                            ],
                          ),
                        ),
                      )
                    : CustomScrollView(
                        controller: scrollCtrl,
                        slivers: [
                          if (audios.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              sliver: SliverList.separated(
                                itemCount: audios.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) => InlineVoicePlayer(url: audios[i]),
                              ),
                            ),
                          if (media.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.all(8),
                              sliver: SliverGrid.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                itemCount: media.length,
                                itemBuilder: (_, i) {
                                  final item = media[i];
                                  final url = item['url']!;
                                  final type = item['type']!;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _openMediaItem(type, url),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _mediaTile(type, url),
                                    ),
                                  );
                                },
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

  Widget _mediaTile(String type, String url) {
    if (type == 'image') {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      );
    }
    if (type == 'video') {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black87),
          const Center(
            child: Icon(Icons.play_circle_fill_rounded, size: 36, color: Colors.white),
          ),
        ],
      );
    }
    final iconAsset = type == 'audio'
        ? 'assets/icons/microphone-icon.svg'
        : 'assets/icons/attach-icon.svg';
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: SvgPicture.asset(
          iconAsset,
          width: 24, height: 24,
          colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
        ),
      ),
    );
  }

  void _openMediaItem(String type, String url) {
    if (type == 'image') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImageViewerScreen(url: url),
        fullscreenDialog: true,
      ));
      return;
    }
    if (type == 'video') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _VideoViewerScreen(url: url),
        fullscreenDialog: true,
      ));
      return;
    }
    if (type == 'audio') {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38, height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 18),
              Text('Voice message', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              InlineVoicePlayer(url: url),
            ],
          ),
        ),
      );
      return;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildHeader(double topPadding) {
    final subtitle = widget.isVendor
        ? 'Typically replies in a few minutes'
        : (widget.isOnline ? 'Online' : 'Tap for contact info');
    return Container(
      padding: EdgeInsets.only(top: topPadding + 6, left: 4, right: 4, bottom: 12),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SvgPicture.asset(
                'assets/icons/chevron-left-icon.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openContactInfo,
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.04),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.avatar != null && widget.avatar!.isNotEmpty
                        ? CachedNetworkImage(imageUrl: widget.avatar!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _fallbackAvatar(), placeholder: (_, __) => _fallbackAvatar())
                        : _fallbackAvatar(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              widget.name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.2,
                                letterSpacing: -0.1,
                              ),
                              softWrap: true,
                            ),
                            if (widget.isVerified || widget.isVerifiedVendor)
                              const Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                            if (widget.isVendor)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFE9A3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Vendor',
                                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF7A5A00), height: 1.2),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary, height: 1.1, fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/call-icon.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
            ),
            splashRadius: 22,
            onPressed: _startVoiceCall,
            tooltip: 'Voice call',
          ),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/video-icon.svg',
              width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
            ),
            splashRadius: 22,
            onPressed: _startVideoCall,
            tooltip: 'Video call',
          ),
          IconButton(
            icon: Icon(_showThreadSearch ? Icons.close_rounded : Icons.more_horiz_rounded, size: 22, color: AppColors.textPrimary),
            splashRadius: 22,
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                _showThreadSearch = !_showThreadSearch;
                if (!_showThreadSearch) { _threadSearch = ''; _threadSearchCtrl.clear(); }
              });
              if (_showThreadSearch) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _threadSearchFocus.requestFocus();
                });
              }
            },
            tooltip: _showThreadSearch ? 'Close search' : 'More',
          ),
        ],
      ),
    );
  }

  // Highlight matches of [_threadSearch] in a body of text.
  Widget _buildHighlightedText(String text, TextStyle base) {
    if (_threadSearch.isEmpty) return Text(text, style: base);
    final q = _threadSearch;
    final lower = text.toLowerCase();
    if (!lower.contains(q)) return Text(text, style: base);
    final spans = <TextSpan>[];
    int i = 0;
    while (i < text.length) {
      final idx = lower.indexOf(q, i);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(i), style: base));
        break;
      }
      if (idx > i) spans.add(TextSpan(text: text.substring(i, idx), style: base));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: base.copyWith(
          backgroundColor: AppColors.primary.withValues(alpha: 0.22),
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ));
      i = idx + q.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  // Indices of messages matching the current thread search query.
  List<int> get _searchMatchIndices {
    if (_threadSearch.isEmpty) return const [];
    final q = _threadSearch;
    final out = <int>[];
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m is! Map) continue;
      final t = (m['content']?.toString() ?? m['message_text']?.toString() ?? '').toLowerCase();
      if (t.contains(q)) out.add(i);
    }
    return out;
  }

  int _currentMatch = 0;

  void _jumpToMatch(int direction) {
    final matches = _searchMatchIndices;
    if (matches.isEmpty) return;
    setState(() {
      // Wrap-around so user can keep tapping arrows endlessly.
      final next = _currentMatch + direction;
      if (next < 0) {
        _currentMatch = matches.length - 1;
      } else if (next >= matches.length) {
        _currentMatch = 0;
      } else {
        _currentMatch = next;
      }
    });
    final target = matches[_currentMatch];
    final ratio = _messages.isEmpty ? 0.0 : target / _messages.length;
    if (_scrollCtrl.hasClients) {
      final max = _scrollCtrl.position.maxScrollExtent;
      // List is NOT reversed - bottom of list is at maxScrollExtent.
      // Higher index = lower in list = larger scroll offset.
      _scrollCtrl.animateTo(
        (max * ratio).clamp(0.0, max),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildSearchNav() {
    final matches = _searchMatchIndices;
    if (_threadSearch.isEmpty || matches.isEmpty) return const SizedBox.shrink();
    final cur = (_currentMatch + 1).clamp(1, matches.length);
    return Positioned(
      right: 16,
      top: 12,
      child: Material(
        color: Colors.white,
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => _jumpToMatch(-1),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: AppColors.textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('$cur/${matches.length}',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            InkWell(
              onTap: () => _jumpToMatch(1),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textPrimary),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildThreadSearchBar() {
    // Mirrors the conversations-list search style: white pill, hairline
    // border, soft prefix icon - so users get one consistent search affordance
    // across the inbox and individual chats (WhatsApp-style "find in chat").
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, size: 20, color: Color(0xFF8E8E93)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _threadSearchCtrl,
              focusNode: _threadSearchFocus,
              autofocus: true,
              cursorColor: Colors.black,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (v) => setState(() {
                _threadSearch = v.trim().toLowerCase();
                _currentMatch = 0;
              }),
              style: GoogleFonts.inter(fontSize: 14, color: Colors.black, decorationThickness: 0),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: 'Search in chat',
                hintStyle: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
            ),
          ),
          if (_threadSearch.isNotEmpty)
            GestureDetector(
              onTap: () {
                _threadSearchCtrl.clear();
                setState(() => _threadSearch = '');
                _threadSearchFocus.requestFocus();
              },
              child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF8E8E93)),
            ),
        ]),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset('assets/icons/chat-icon.svg', width: 32, height: 32, colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
          const SizedBox(height: 14),
          Text('Say hello!', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text('Start your conversation with ${widget.name}', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4), textAlign: TextAlign.center),
          ),
        ]),
      );
    }

    // When searching we keep ALL messages visible (so jump up/down navigates
    // through highlighted matches in context), instead of filtering them out.
    final visible = _messages;

    final rows = <Widget>[
      _buildEncryptionBanner(),
      if (widget.isVendor && widget.service != null) _buildServiceContextCard(),
      ...visible.whereType<Map>().map(_messageBubble),
    ];

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: rows.length,
      itemBuilder: (_, idx) => rows[idx],
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Center(
        child: Text(
          widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark, height: 1.0),
        ),
      ),
    );
  }

  Future<void> _startVoiceCall() async {
    // Show a lightweight "Calling…" sheet immediately for snappy UX, then
    // hit /calls/start. Once we have the LiveKit token, push the full
    // VoiceCallScreen (which connects to LiveKit and shows mute/speaker/end).
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      ),
    );
    final res = await CallsService.startCall(
      conversationId: widget.conversationId,
      kind: 'voice',
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close spinner

    if (res['success'] != true || res['data'] is! Map) {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not start call');
      return;
    }
    final data = res['data'] as Map;
    final call = data['call'] is Map ? data['call'] as Map : const {};
    final callId = call['id']?.toString() ?? '';
    final url = data['url']?.toString() ?? '';
    final token = data['token']?.toString() ?? '';
    if (callId.isEmpty || url.isEmpty || token.isEmpty) {
      AppSnackbar.error(context, 'Invalid call response');
      return;
    }
    if (!CallUiCoordinator.openActive(callId)) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: 'active_call_$callId'),
        builder: (_) => VoiceCallScreen.outgoing(
          callId: callId,
          peerName: widget.name,
          peerAvatar: widget.avatar,
          livekitUrl: url,
          livekitToken: token,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _startVideoCall() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      ),
    );
    final res = await CallsService.startCall(
      conversationId: widget.conversationId,
      kind: 'video',
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (res['success'] != true || res['data'] is! Map) {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not start video call');
      return;
    }
    final data = res['data'] as Map;
    final call = data['call'] is Map ? data['call'] as Map : const {};
    final callId = call['id']?.toString() ?? '';
    final url = data['url']?.toString() ?? '';
    final token = data['token']?.toString() ?? '';
    if (callId.isEmpty || url.isEmpty || token.isEmpty) {
      AppSnackbar.error(context, 'Invalid call response');
      return;
    }
    if (!CallUiCoordinator.openActive(callId)) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: 'active_call_$callId'),
        builder: (_) => VideoCallScreen.outgoing(
          callId: callId,
          peerName: widget.name,
          peerAvatar: widget.avatar,
          livekitUrl: url,
          livekitToken: token,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildScrollToBottomPill() {
    final hasNew = _newMessagesCount > 0;
    return GestureDetector(
      onTap: () => _scrollToBottom(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: hasNew ? 12 : 10, vertical: hasNew ? 8 : 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight, width: 0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasNew) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                child: Text(_newMessagesCount > 99 ? '99+' : '$_newMessagesCount',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0)),
              ),
              const SizedBox(width: 6),
              Text(_newMessagesCount == 1 ? 'new message' : 'new messages',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.0)),
              const SizedBox(width: 6),
            ],
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: hasNew ? AppColors.primary : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Cream banner: vendor variant shows "verified vendor" + 3 trust pills,
  /// normal variant shows the WhatsApp-style E2EE notice.
  Widget _buildEncryptionBanner() {
    if (widget.isVendor && widget.isVerifiedVendor) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1C7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: AppColors.textPrimary.withValues(alpha: 0.85)),
                  const SizedBox(width: 6),
                  Text("You're chatting with a verified vendor",
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  _trustChipSvg('assets/icons/verified-icon.svg', 'Verified business'),
                  _trustChipSvg('assets/icons/shield-icon.svg', 'Secure payments'),
                  _trustChipSvg('assets/icons/verified-icon.svg', 'Trusted by Nuru'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Always show the E2EE notice (WhatsApp-style) - do not hide it based on
    // server flag, so it stays persistently visible at the top of the thread.

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1C7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textPrimary.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Messages and calls are end-to-end encrypted.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.85), height: 1.35, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showEncryptionLearnMoreSheet(context),
              child: Text(
                'Learn more',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Friendly bottom-sheet explaining what end-to-end encryption means
  /// in Nuru conversations. Triggered from the encryption banner's
  /// "Learn more" tap.
  void _showEncryptionLearnMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.lock_rounded,
                        size: 20, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Text('End-to-end encryption',
                      style: GoogleFonts.inter(
                          fontSize: 17, fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Your messages and calls in this conversation are secured with '
                'end-to-end encryption. That means only you and the person you\'re '
                'chatting with can read or listen to them · not even Nuru.',
                style: GoogleFonts.inter(
                    fontSize: 14, height: 1.5,
                    color: AppColors.textPrimary.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 14),
              _learnMoreBullet('Messages stay private between you and the recipient.'),
              _learnMoreBullet('Voice and video calls are encrypted end-to-end.'),
              _learnMoreBullet('Nuru never stores the keys needed to read them.'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Got it',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _learnMoreBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5, height: 5,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 13.5, height: 1.45,
                    color: AppColors.textPrimary.withValues(alpha: 0.85))),
          ),
        ],
      ),
    );
  }

  Widget _trustChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF7A5A00)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF7A5A00))),
      ],
    );
  }

  Widget _trustChipSvg(String asset, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: 13, height: 13,
          colorFilter: const ColorFilter.mode(Color(0xFF7A5A00), BlendMode.srcIn),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF7A5A00))),
      ],
    );
  }

  Widget _buildServiceContextCard() {
    final svc = widget.service ?? const {};
    final image = svc['image']?.toString();
    final title = svc['title']?.toString() ?? svc['name']?.toString() ?? 'Service';
    final eventTitle = svc['event_title']?.toString();
    final venue = svc['location']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60, height: 60,
                child: image != null && image.isNotEmpty
                    ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant))
                    : Container(color: AppColors.surfaceVariant, child: const Icon(Icons.event_rounded, color: AppColors.textTertiary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(eventTitle ?? title,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(venue ?? title,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary, height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final svcId = (widget.service ?? const {})['id']?.toString();
                if (svcId == null || svcId.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublicServiceScreen(serviceId: svcId),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.borderLight),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('View', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(dynamic msg) {
    if (msg is! Map) return const SizedBox.shrink();

    // Call-log row - rendered as a centered, pill-shaped status chip rather
    // than a left/right speech bubble. See _loadMessages where we tag these.
    if (msg['_type'] == 'call_log') {
      return _callLogBubble(msg);
    }

    final text = msg['content']?.toString() ?? msg['message_text']?.toString() ?? '';
    final isMine = _isMine(msg);
    final time = _messageTime(msg);
    final attachmentUrls = _extractAttachmentUrls(msg['attachments']);
    final rawImageUrl = msg['image_url']?.toString() ?? '';
    final allUrls = <String>[
      if (rawImageUrl.isNotEmpty) rawImageUrl,
      ...attachmentUrls,
    ];
    final imageUrls = allUrls.where(_isImageUrl).toList();
    final videoUrls = allUrls.where(_isVideoUrl).toList();
    final audioUrls = allUrls.where(_isAudioUrl).toList();
    final fileUrls = allUrls
        .where((u) => !_isImageUrl(u) && !_isAudioUrl(u) && !_isVideoUrl(u))
        .toList();
    final isUploading = msg['_uploading'] == true;

    final msgDate = _parseTime(time);
    String timeDisplay = '';
    if (msgDate != null) {
      final h = msgDate.hour;
      final m = msgDate.minute.toString().padLeft(2, '0');
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final ampm = h >= 12 ? 'PM' : 'AM';
      timeDisplay = '$h12:$m $ampm';
    }
    final isRead = msg['is_read'] == true || msg['read_at'] != null;
    final isFailed = msg['_failed'] == true;

    final bubbleColor = isMine ? const Color(0xFFFFF4D1) : Colors.white;
    const textColor = AppColors.textPrimary;

    // Pull reply snapshot (server) or fallback to inline preview
    final reply = msg['reply_snapshot'];
    final hasReply = reply is Map && (
      (reply['text']?.toString().isNotEmpty ?? false) ||
      (reply['sender']?.toString().isNotEmpty ?? false)
    );

    // Audio-only messages (voice notes) render naked - no card/border around
    // them - so they look like the WhatsApp bubble-less voice chip.
    final isAudioOnly = audioUrls.isNotEmpty &&
        text.isEmpty &&
        imageUrls.isEmpty &&
        videoUrls.isEmpty &&
        fileUrls.isEmpty &&
        !hasReply;

    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasReply) _replySnapshotBlock(reply as Map, isMine),
        if (imageUrls.isNotEmpty) ...[
          _imageGrid(imageUrls, allowOpen: true),
          if (text.isNotEmpty || fileUrls.isNotEmpty || audioUrls.isNotEmpty || videoUrls.isNotEmpty) const SizedBox(height: 6),
        ],
        ...videoUrls.map((u) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _videoBubble(u),
        )),
        if (audioUrls.isEmpty && isUploading)
          _voiceChip(null, uploading: true),
        ...audioUrls.map((u) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _voiceChip(u),
        )),
        ...fileUrls.map((u) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _fileChip(u),
        )),
        if (text.isNotEmpty)
          _buildHighlightedText(
            text,
            GoogleFonts.inter(fontSize: 14.5, color: textColor, height: 1.4, fontWeight: FontWeight.w400),
          ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (timeDisplay.isNotEmpty)
              Text(timeDisplay,
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary, height: 1.0, fontWeight: FontWeight.w400)),
            if (isMine) ...[
              const SizedBox(width: 4),
              Icon(
                isFailed ? Icons.error_outline_rounded : Icons.done_all_rounded,
                size: 13,
                color: isFailed ? Colors.red.shade400 : (isRead ? AppColors.primary : AppColors.textTertiary),
              ),
            ],
          ],
        ),
      ],
    );

    return _SwipeToReply(
      isMine: isMine,
      onReply: () => _setReplyTo(msg),
      child: GestureDetector(
        onLongPress: () => _onMessageLongPress(msg),
        // Note: no global onTap - media has its own tap handlers, and tap on
        // text bubbles should NOT trigger reply (use swipe or long-press).
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: isAudioOnly
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    child: bubbleContent,
                  )
                : Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(16),
                      border: isMine ? null : Border.all(color: const Color(0xFFEDEDEF), width: 1),
                    ),
                    child: bubbleContent,
                  ),
          ),
        ),
      ),
    );
  }

  /// Centered call-log bubble: missed / outgoing / incoming + duration.
  ///
  /// `msg` is a row from `GET /calls/conversation/{id}`, tagged with
  /// `_type: 'call_log'` in [_loadMessages]. Expected shape:
  ///   { id, status, kind, caller_id, callee_id, duration_seconds,
  ///     created_at, ended_at }
  Widget _callLogBubble(Map msg) {
    final status = msg['status']?.toString() ?? 'ended';
    final callerId = msg['caller_id']?.toString() ?? '';
    final direction = msg['direction']?.toString().toLowerCase();
    final isOutgoing = direction == 'outgoing' || (_currentUserId != null && callerId == _currentUserId);
    final duration = (msg['duration_seconds'] as num?)?.toInt() ?? 0;
    final isVideo = (msg['kind']?.toString().toLowerCase() == 'video');
    final kindWord = isVideo ? 'video' : 'voice';

    // Pick label + colors from status. Missed calls are the only "loud" state.
    String label;
    Color iconColor;
    Color bgColor;
    IconData iconData = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
    double iconRotate = 0;

    switch (status) {
      case 'missed':
      case 'declined':
      case 'no_answer':
        label = isOutgoing
            ? (status == 'declined' ? 'Call declined' : 'No answer')
            : 'Missed $kindWord call';
        iconColor = const Color(0xFFE53935);
        bgColor = const Color(0xFFE53935).withValues(alpha: 0.10);
        if (!isVideo) iconRotate = 2.356;
        break;
      case 'ended':
      case 'connected':
        final dur = _formatCallDuration(duration);
        final dirWord = isOutgoing ? 'Outgoing' : 'Incoming';
        label = '$dirWord ${isVideo ? 'video' : ''} call · $dur'.replaceAll('  ', ' ');
        iconColor = const Color(0xFF22C55E);
        bgColor = AppColors.primary.withValues(alpha: 0.10);
        break;
      case 'ringing':
      case 'answered':
        label = isOutgoing ? 'Calling…' : 'Ringing…';
        iconColor = AppColors.primaryDark;
        bgColor = AppColors.primary.withValues(alpha: 0.14);
        break;
      default:
        label = isVideo ? 'Video call' : 'Call';
        iconColor = AppColors.textSecondary;
        bgColor = AppColors.surfaceVariant;
    }

    final time = _timelineTime(msg);
    final dt = _parseTime(time);
    String timeStr = '';
    if (dt != null) {
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final ampm = h >= 12 ? 'PM' : 'AM';
      timeStr = '$h12:$m $ampm';
    }

    return GestureDetector(
      onTap: isVideo ? _startVideoCall : _startVoiceCall, // tap to call back, like WhatsApp
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: iconRotate,
                  child: Icon(iconData, size: 14, color: iconColor),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCallDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    if (seconds >= 3600) {
      final h = (seconds ~/ 3600).toString();
      final mm = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
      return '$h:$mm:$s';
    }
    return '$m:$s';
  }

  Widget _replySnapshotBlock(Map reply, bool isMine) {
    final text = reply['text']?.toString() ?? '';
    final sender = reply['sender']?.toString() ?? 'Reply';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha: 0.45) : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sender, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(text,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
          ],
        ],
      ),
    );
  }

  /// Renders 1, 2, or 3+ images. For 4+ shows the first 3 with "+N" overlay
  /// on the third tile. Tapping any tile opens a fullscreen pager.
  Widget _imageGrid(List<String> urls, {bool allowOpen = true}) {
    final maxW = MediaQuery.of(context).size.width * 0.62;
    void open(int i) {
      if (!allowOpen) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImageGalleryScreen(urls: urls, initialIndex: i),
        fullscreenDialog: true,
      ));
    }
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => open(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: urls.first,
            width: maxW,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    if (urls.length == 2) {
      return SizedBox(
        width: maxW,
        child: Row(
          children: [
            Expanded(child: GestureDetector(onTap: () => open(0), child: _gridTile(urls[0], radius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
            const SizedBox(width: 3),
            Expanded(child: GestureDetector(onTap: () => open(1), child: _gridTile(urls[1], radius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12))))),
          ],
        ),
      );
    }
    final extra = urls.length - 3;
    return SizedBox(
      width: maxW,
      child: Row(
        children: [
          Expanded(child: GestureDetector(onTap: () => open(0), child: _gridTile(urls[0], radius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
          const SizedBox(width: 3),
          Expanded(child: GestureDetector(onTap: () => open(1), child: _gridTile(urls[1]))),
          const SizedBox(width: 3),
          Expanded(
            child: GestureDetector(
              onTap: () => open(2),
              child: Stack(
                children: [
                  _gridTile(urls[2], radius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12))),
                  if (extra > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            alignment: Alignment.center,
                            child: Text('+$extra',
                                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridTile(String url, {BorderRadius? radius}) {
    final child = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      height: 110,
      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
    );
    return radius == null ? child : ClipRRect(borderRadius: radius, child: child);
  }

  /// Compact voice-note chip with a play button. When [url] is null and
  /// [uploading] is true, shows an in-progress placeholder so the user sees
  /// the message land in the chat the moment they hit send.
  Widget _voiceChip(String? url, {bool uploading = false}) {
    if (uploading || url == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Sending...',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    // In-app inline player - plays audio without opening a browser/asset link.
    return InlineVoicePlayer(url: url);
  }

  /// In-bubble video tile. Shows a poster + play button; tapping opens the
  /// fullscreen built-in video player.
  Widget _videoBubble(String url) {
    final maxW = MediaQuery.of(context).size.width * 0.62;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _VideoViewerScreen(url: url),
        fullscreenDialog: true,
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: maxW,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NuruVideoPlayer(
                url: url,
                height: 180,
                showControls: false,
                borderRadius: BorderRadius.circular(12),
              ),
              Container(color: Colors.black.withValues(alpha: 0.18)),
              Center(
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileChip(String url) {
    final name = Uri.tryParse(url)?.pathSegments.isNotEmpty == true
        ? Uri.parse(url).pathSegments.last
        : 'File';
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.download_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _setReplyTo(Map msg) {
    if (msg['_type'] == 'call_log') return;
    final senderName = _isMine(msg) ? 'You' : widget.name;
    final attachUrls = _extractAttachmentUrls(msg['attachments']);
    final imgUrl = msg['image_url']?.toString() ?? '';
    final allUrls = <String>[
      if (imgUrl.isNotEmpty) imgUrl,
      ...attachUrls,
    ];
    final firstImage = allUrls.firstWhere(_isImageUrl, orElse: () => '');
    final hasAudio = allUrls.any(_isAudioUrl);
    final hasVideo = allUrls.any(_isVideoUrl);
    setState(() => _replyTo = {
      'id': msg['id'],
      'content': msg['content'] ?? msg['message_text'],
      '_sender_name': senderName,
      if (firstImage.isNotEmpty) '_thumb': firstImage,
      if (hasAudio) '_kind': 'audio',
      if (hasVideo) '_kind': 'video',
      if (firstImage.isNotEmpty) '_kind': 'image',
    });
    // Soft focus the composer so the user can immediately start typing.
    FocusScope.of(context).requestFocus(_composerFocus);
    HapticFeedback.selectionClick();
  }

  void _onMessageLongPress(Map msg) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: AppColors.textPrimary),
              title: Text('Reply', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _setReplyTo(msg); },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
              title: Text('Copy', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                final text = (msg['content'] ?? msg['message_text'] ?? '').toString();
                if (text.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: text));
                  AppSnackbar.success(context, 'Copied to clipboard');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Composer ──────────────────────────────────────────────────────────────

  Widget _buildComposer(double bottomPadding) {
    final canSend = _msgCtrl.text.trim().isNotEmpty || _selectedImages.isNotEmpty;
    final fmtDur = '${_recordDuration.inMinutes.toString().padLeft(2, '0')}:'
        '${(_recordDuration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyTo != null) _replyPreview(),
        if (_selectedImages.isNotEmpty) _attachmentStrip(),

        // Single composer row matching the design exactly: yellow "+" circle
        // OUTSIDE a single rounded pill that contains [input + emoji + mic/send].
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomPadding),
          color: Colors.white,
          child: _isRecording
              ? Row(
                  children: [
                    GestureDetector(
                      onTap: _cancelRecording,
                      child: Container(
                        width: 44, height: 44,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFE4E4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 22, color: Color(0xFFD83A3A)),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFD83A3A), shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Text('Recording  $fmtDur',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _stopAndSendRecording,
                      child: Container(
                        width: 44, height: 44,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: Center(
                          child: SvgPicture.asset('assets/icons/send-icon.svg',
                              width: 18, height: 18,
                              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                        ),
                      ),
                    ),
                  ],
                )
              // Single bordered pill containing EVERYTHING:
              // [yellow + circle] [text input] [smiley] [mic OR send]
              : Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Yellow "+" circle - INSIDE the pill, left side.
                      GestureDetector(
                        onTap: _showAttachmentSheet,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/plus-icon.svg',
                              width: 20, height: 20,
                              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _msgCtrl,
                          focusNode: _composerFocus,
                          maxLines: 4, minLines: 1,
                          onChanged: (_) => setState(() {}),
                          onTap: () {
                            if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
                          },
                          style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary, height: 1.35, decoration: TextDecoration.none, decorationThickness: 0),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: GoogleFonts.inter(fontSize: 15, color: AppColors.textHint, height: 1.35, decoration: TextDecoration.none),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      // Emoji icon (smiley toggles to keyboard when picker open)
                      GestureDetector(
                        onTap: _toggleEmojiPicker,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _showEmojiPicker
                              ? SvgPicture.asset(
                                  'assets/icons/keyboard-icon.svg',
                                  width: 22, height: 22,
                                  colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
                                )
                              : const Icon(
                                  Icons.sentiment_satisfied_outlined,
                                  size: 22,
                                  color: AppColors.textPrimary,
                                ),
                        ),
                      ),
                      // Mic OR Send (when there's something to send)
                      canSend
                          ? GestureDetector(
                              onTap: _sending ? null : _sendMessage,
                              child: Container(
                                width: 36, height: 36,
                                margin: const EdgeInsets.only(left: 2, right: 4),
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                child: _sending
                                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Center(child: SvgPicture.asset('assets/icons/send-icon.svg', width: 15, height: 15, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
                              ),
                            )
                          : GestureDetector(
                              onTap: _startRecording,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6, right: 14),
                                child: SvgPicture.asset(
                                  'assets/icons/microphone-icon.svg',
                                  width: 22, height: 22,
                                  colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
        ),

        // Emoji picker - slides in below the composer when toggled.
        if (_showEmojiPicker)
          NuruEmojiPicker(
            height: MediaQuery.of(context).viewInsets.bottom > 0
                ? (MediaQuery.of(context).size.height * 0.24).clamp(180.0, 230.0).toDouble()
                : 340,
            onClose: () => setState(() => _showEmojiPicker = false),
            onEmojiSelected: (e) {
              final sel = _msgCtrl.selection;
              final text = _msgCtrl.text;
              final pos = sel.isValid ? sel.start : text.length;
              final newText = text.substring(0, pos) + e + text.substring(pos);
              _msgCtrl.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: pos + e.length),
              );
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _replyPreview() {
    final reply = _replyTo!;
    final sender = reply['_sender_name']?.toString() ?? 'Reply';
    final content = (reply['content'] ?? '').toString();
    final thumb = reply['_thumb']?.toString() ?? '';
    final kind = reply['_kind']?.toString() ?? '';
    String previewText = content;
    if (previewText.isEmpty) {
      if (kind == 'image') previewText = '📷 Photo';
      else if (kind == 'video') previewText = '🎬 Video';
      else if (kind == 'audio') previewText = '🎤 Voice message';
      else previewText = 'Attachment';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: const BoxDecoration(color: AppColors.surface),
      child: Row(
        children: [
          Container(width: 3, height: 40, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to $sender',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 2),
                Text(previewText,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (thumb.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: thumb,
                width: 40, height: 40, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(width: 40, height: 40, color: AppColors.surfaceVariant),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _attachmentStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: AppColors.surface,
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _selectedImages.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _selectedImages[i];
            final isImg = ['.jpg','.jpeg','.png','.gif','.webp']
                .any((e) => f.path.toLowerCase().endsWith(e));
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: isImg
                      ? Image.file(f, width: 60, height: 60, fit: BoxFit.cover)
                      : Container(
                          width: 60, height: 60,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.insert_drive_file_rounded, color: AppColors.textSecondary),
                        ),
                ),
                Positioned(
                  top: 0, right: 0,
                  child: GestureDetector(
                    onTap: () => _removeSelectedImage(i),
                    child: Container(
                      width: 20, height: 20,
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    final chips = widget.isVendor
        ? [
            _ActionChipSpec('Quote', icon: Icons.request_quote_outlined, onTap: _showQuoteSheet),
            _ActionChipSpec('Files', svgAsset: 'assets/icons/attach-icon.svg', onTap: _pickFile),
            _ActionChipSpec('Photos', svgAsset: 'assets/icons/photos-icon.svg', onTap: _pickFromGallery),
            _ActionChipSpec('Camera', svgAsset: 'assets/icons/camera-icon.svg', onTap: _pickFromCamera),
            _ActionChipSpec('Location', svgAsset: 'assets/icons/location-icon.svg', onTap: _shareLocation),
            _ActionChipSpec('Payment', svgAsset: 'assets/icons/card-icon.svg', onTap: _showQuoteSheet),
          ]
        : [
            _ActionChipSpec('Gallery', svgAsset: 'assets/icons/photos-icon.svg', onTap: _pickFromGallery),
            _ActionChipSpec('Camera', svgAsset: 'assets/icons/camera-icon.svg', onTap: _pickFromCamera),
            _ActionChipSpec('File', svgAsset: 'assets/icons/attach-icon.svg', onTap: _pickFile),
            _ActionChipSpec('Location', svgAsset: 'assets/icons/location-icon.svg', onTap: _shareLocation),
          ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: const Color(0xFFE5E5E8), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text('Share',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final c in chips)
                      Expanded(
                        child: GestureDetector(
                          onTap: () { Navigator.pop(ctx); c.onTap(); },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7DC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: c.svgAsset != null
                                      ? SvgPicture.asset(c.svgAsset!, width: 18, height: 18,
                                          colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn))
                                      : Icon(c.icon, size: 18, color: AppColors.primary),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(c.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionChipSpec {
  final String label;
  final String? svgAsset;
  final IconData? icon;
  final VoidCallback onTap;
  const _ActionChipSpec(this.label, {this.svgAsset, this.icon, required this.onTap});
}

class _ImageViewerScreen extends StatelessWidget {
  final String url;
  const _ImageViewerScreen({required this.url});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 48),
          ),
        ),
      ),
    );
  }
}

/// Swipeable fullscreen image gallery - pinch/zoom + page through all
/// images in the same message.
class _ImageGalleryScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ImageGalleryScreen({required this.urls, this.initialIndex = 0});
  @override
  State<_ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<_ImageGalleryScreen> {
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1} / ${widget.urls.length}',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1, maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoViewerScreen extends StatelessWidget {
  final String url;
  const _VideoViewerScreen({required this.url});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: NuruVideoPlayer(url: url, autoPlay: true, showControls: true),
      ),
    );
  }
}

/// WhatsApp-style swipe-to-reply: drag the message horizontally toward the
/// composer; if you pass the threshold, [onReply] fires and a reply icon
/// fades in beneath the bubble.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool isMine;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.isMine, required this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  double _dx = 0;
  static const double _threshold = 56;
  bool _triggered = false;

  void _reset() {
    setState(() {
      _dx = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mine drags left (negative), peer drags right (positive).
    final dirSign = widget.isMine ? -1.0 : 1.0;
    final progress = (_dx.abs() / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        final next = _dx + d.delta.dx;
        // Only allow drag in the correct direction.
        if (dirSign > 0 && next < 0) return;
        if (dirSign < 0 && next > 0) return;
        if (next.abs() > 90) return;
        setState(() => _dx = next);
        if (!_triggered && _dx.abs() >= _threshold) {
          _triggered = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_triggered) widget.onReply();
        _reset();
      },
      onHorizontalDragCancel: _reset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply hint icon revealed under the bubble while dragging.
          Positioned.fill(
            child: Align(
              alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Opacity(
                  opacity: progress,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.reply_rounded, size: 18, color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
