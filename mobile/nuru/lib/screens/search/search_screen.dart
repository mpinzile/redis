import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_scrollable_tabs.dart';

import '../events/event_detail_screen.dart';
import '../events/event_public_view_screen.dart';
import '../public_profile/public_profile_screen.dart';
import '../services/public_service_screen.dart';
import '../../core/services/api_service.dart';
import '../../core/l10n/l10n_helper.dart';
import '../../core/widgets/event_cover_image.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  static String get _baseUrl => ApiService.baseUrl;
  final _ctrl = TextEditingController();
  late TabController _tabCtrl;
  bool _loading = false;
  String _query = '';
  List<dynamic> _users = [];
  List<dynamic> _events = [];
  List<dynamic> _services = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tabCtrl.dispose();
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

  /// Global search - fires 3 parallel requests matching web search.ts
  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _loading = true; _query = q.trim(); });

    final headers = await _headers();
    final results = await Future.wait([
      // /users/search?q=...&limit=6 - web: searchApi.searchPeople
      http.get(Uri.parse('$_baseUrl/users/search').replace(queryParameters: {'q': _query, 'limit': '10'}), headers: headers),
      // /events?q=...&limit=6 - web: searchApi.searchEvents
      http.get(Uri.parse('$_baseUrl/events').replace(queryParameters: {'q': _query, 'limit': '10'}), headers: headers),
      // /services?q=...&limit=6 - web: searchApi.searchServices
      http.get(Uri.parse('$_baseUrl/services').replace(queryParameters: {'q': _query, 'limit': '10'}), headers: headers),
    ].map((f) => f.catchError((_) => http.Response('{}', 500))));

    if (mounted) {
      setState(() {
        _loading = false;
        // Parse people: response has { items: [...] } or { data: { items: [...] } }
        _users = _extractList(results[0].body, ['items', 'users', 'data']);
        // Parse events: response has { events: [...] } or { data: { events: [...] } }
        _events = _extractList(results[1].body, ['events', 'data']);
        // Parse services: response has { services: [...] } or { data: { services: [...] } }
        _services = _extractList(results[2].body, ['services', 'data']);
      });
    }
  }

  List<dynamic> _extractList(String body, List<String> keys) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        // Try direct keys first
        for (final k in keys) {
          final v = decoded[k];
          if (v is List) return v;
        }
        // Try nested under 'data'
        if (decoded['data'] is Map) {
          for (final k in keys) {
            final v = decoded['data'][k];
            if (v is List) return v;
          }
        }
        if (decoded['data'] is List) return decoded['data'];
      }
      if (decoded is List) return decoded;
    } catch (_) {}
    return [];
  }

  TextStyle _f({required double size, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary, double height = 1.3}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: SvgPicture.asset('assets/icons/chevron-left-icon.svg', width: 22, height: 22,
            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 18, color: Color(0xFF8E8E93)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: 'Search people, events, services...',
                  hintStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: const Color(0xFF9E9E9E)),
                ),
                onChanged: (v) {
                  if (v.trim().length >= 2) _search(v);
                },
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
              ),
            ),
          ]),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: SvgPicture.asset('assets/icons/close-icon.svg', width: 18, height: 18,
                colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
              onPressed: () {
                _ctrl.clear();
                setState(() { _query = ''; _users = []; _events = []; _services = []; });
              },
            ),
          const SizedBox(width: 8),
        ],
        bottom: _query.isNotEmpty
            ? _SearchUnderlineTabs(
                controller: _tabCtrl,
                labels: [
                  '${context.tr('search_people')} (${_users.length})',
                  '${context.tr('events')} (${_events.length})',
                  '${context.tr('services')} (${_services.length})',
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _query.isEmpty
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset('assets/icons/search-icon.svg', width: 48, height: 48,
                      colorFilter: ColorFilter.mode(AppColors.textHint.withOpacity(0.4), BlendMode.srcIn)),
                    const SizedBox(height: 12),
                    Text('Search Nuru', style: _f(size: 16, weight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Find people, events & services', style: _f(size: 13, color: AppColors.textTertiary)),
                  ],
                ))
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _usersList(),
                    _eventsList(),
                    _servicesList(),
                  ],
                ),
    );
  }

  Widget _usersList() {
    if (_users.isEmpty) return _emptyResult('No people found');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = _users[i] as Map<String, dynamic>;
        final rawName = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        final name = u['full_name']?.toString() ?? (rawName.isNotEmpty ? rawName : u['username']?.toString() ?? 'Unknown');
        final avatar = (u['avatar'] ?? u['profile_picture_url']) as String?;
        final username = u['username']?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          leading: CircleAvatar(
            radius: 20,
            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            backgroundColor: AppColors.surfaceVariant,
            child: avatar == null || avatar.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: _f(size: 14, weight: FontWeight.w700, color: AppColors.textSecondary)) : null,
          ),
          title: Text(name, style: _f(size: 14, weight: FontWeight.w600)),
          subtitle: username.isNotEmpty ? Text('@$username', style: _f(size: 11, color: AppColors.textTertiary)) : null,
          trailing: SvgPicture.asset('assets/icons/chevron-right-icon.svg', width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
          onTap: () {
            final userId = u['id']?.toString();
            if (userId != null) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: userId)));
            }
          },
        );
      },
    );
  }

  Widget _eventsList() {
    if (_events.isEmpty) return _emptyResult('No events found');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = _events[i] as Map<String, dynamic>;
        final title = e['title'] ?? e['name'] ?? 'Untitled';
        final date = e['start_date']?.toString() ?? '';
        final rawRole = (e['role'] ?? e['viewer_role'] ?? e['my_role'])?.toString().toLowerCase();
        final knownRole = rawRole == 'creator' || rawRole == 'organizer' || rawRole == 'owner'
            ? 'creator'
            : (rawRole == 'committee' || rawRole == 'member' ? 'committee' : null);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          leading: EventCoverImage(
            event: e,
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(10),
          ),
          title: Text(title.toString(), style: _f(size: 14, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: date.isNotEmpty ? Text(date.substring(0, date.length >= 10 ? 10 : date.length), style: _f(size: 11, color: AppColors.textTertiary)) : null,
          trailing: SvgPicture.asset('assets/icons/chevron-right-icon.svg', width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
          onTap: () {
            final eventId = e['id'].toString();
            // Route to management only when the viewer is the creator/committee.
            // Everyone else (including invitees and the public) lands on the
            // public event page rather than the management overview.
            if (knownRole == 'creator' || knownRole == 'committee') {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => EventDetailScreen(eventId: eventId, initialData: e, knownRole: knownRole),
              ));
            } else {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => EventPublicViewScreen(eventId: eventId, initialData: e),
              ));
            }
          },
        );
      },
    );
  }

  Widget _servicesList() {
    if (_services.isEmpty) return _emptyResult('No services found');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _services[i] as Map<String, dynamic>;
        final name = s['title'] ?? s['name'] ?? 'Service';
        final category = s['category_name'] ?? (s['service_category'] is Map ? s['service_category']['name'] : '') ?? '';
        final image = s['primary_image'] as String?;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: image != null && image.isNotEmpty
                ? Image.network(image, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.work_outline_rounded, size: 20, color: AppColors.textSecondary))
                : const Icon(Icons.work_outline_rounded, size: 20, color: AppColors.textSecondary),
          ),
          title: Text(name.toString(), style: _f(size: 14, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: category.toString().isNotEmpty ? Text(category.toString(), style: _f(size: 11, color: AppColors.textTertiary)) : null,
          trailing: SvgPicture.asset('assets/icons/chevron-right-icon.svg', width: 16, height: 16,
            colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
          onTap: () {
            final serviceId = s['id']?.toString();
            if (serviceId != null && serviceId.isNotEmpty) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PublicServiceScreen(serviceId: serviceId)));
            }
          },
        );
      },
    );
  }

  Widget _emptyResult(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/icons/search-icon.svg', width: 40, height: 40,
            colorFilter: ColorFilter.mode(AppColors.textHint.withOpacity(0.4), BlendMode.srcIn)),
          const SizedBox(height: 12),
          Text(msg, style: _f(size: 14, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _SearchUnderlineTabs extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;
  final TabController controller;
  const _SearchUnderlineTabs({required this.labels, required this.controller});
  @override
  Size get preferredSize => const Size.fromHeight(58);
  @override
  Widget build(BuildContext context) {
    return NuruPillTabBar(controller: controller, labels: labels);
  }
}

