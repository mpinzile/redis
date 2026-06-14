import '../../core/widgets/nuru_refresh_indicator.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/widgets/nuru_skeleton.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/services/user_services_service.dart';
import '../../core/services/api_service.dart';
import '../../core/l10n/l10n_helper.dart';
import 'widgets/my_contribution_payments_tab.dart';

class ContributorsScreen extends StatefulWidget {
  const ContributorsScreen({super.key});

  @override
  State<ContributorsScreen> createState() => _ContributorsScreenState();
}

class _ContributorsScreenState extends State<ContributorsScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _contributors = [];
  bool _loading = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await UserServicesService.getContributors();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        final data = res['data'];
        if (data is Map) {
          _contributors = data['contributors'] ?? [];
        } else if (data is List) {
          _contributors = data;
        } else {
          _contributors = [];
        }
      }
    });
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _deleteContributor(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          context.trw('delete_contributor'),
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Text(
          'Remove $name from your contributors? This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.trw('delete'),
              style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final headers = await _headers();
      final resp = await http.delete(
        Uri.parse('${ApiService.baseUrl}/user-contributors/$id'),
        headers: headers,
      );
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        AppSnackbar.success(context, context.tr('contributor_removed'));
        _load();
      } else {
        AppSnackbar.error(context, context.tr('failed_delete'));
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, context.tr('failed_delete'));
    }
  }

  void _editContributor(Map<String, dynamic> c) {
    final nameCtrl = TextEditingController(text: c['name']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: c['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: c['phone']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: c['notes']?.toString() ?? '');
    final id = c['id']?.toString() ?? '';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: AppIcon('pen', size: 20, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.trw('edit_contributor'),
                              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Update contact details and notes.',
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(child: AppIcon('close', size: 14, color: AppColors.textSecondary)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sheetField('Name', nameCtrl, icon: 'user'),
                    const SizedBox(height: 12),
                    _sheetField('Phone', phoneCtrl, icon: 'phone', type: TextInputType.phone),
                    const SizedBox(height: 12),
                    _sheetField('Email', emailCtrl, icon: 'email', type: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    _sheetField('Notes', notesCtrl, icon: 'pen', maxLines: 3),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setSheet(() => saving = true);
                                try {
                                  final headers = await _headers();
                                  final resp = await http.put(
                                    Uri.parse('${ApiService.baseUrl}/user-contributors/$id'),
                                    headers: headers,
                                    body: jsonEncode({
                                      'name': nameCtrl.text.trim(),
                                      'email': emailCtrl.text.trim(),
                                      'phone': phoneCtrl.text.trim(),
                                      'notes': notesCtrl.text.trim(),
                                    }),
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  if (resp.statusCode >= 200 && resp.statusCode < 300) {
                                    AppSnackbar.success(context, context.tr('contributor_updated'));
                                    _load();
                                  } else {
                                    AppSnackbar.error(context, context.tr('failed_update'));
                                  }
                                } catch (_) {
                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  AppSnackbar.error(context, context.tr('failed_update'));
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                            : Text(
                                context.trw('save_changes'),
                                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(
    String label,
    TextEditingController ctrl, {
    String? icon,
    TextInputType type = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.2),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          autocorrect: false,
          enableSuggestions: false,
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            prefixIcon: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: AppIcon(icon, size: 16, color: AppColors.textTertiary),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            hintStyle: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFFA1A1AA)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.7), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(
        title: context.tr('contributors'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: _PillTabs(
              controller: _tabController,
              tabs: const ['Contributors', 'My Contributions'],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          NuruRefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            child: _loading
                ? const NuruSkeletonList(itemCount: 6, showTrailing: true)
                : _contributors.isEmpty
                    ? ListView(children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                        _emptyState(),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _contributors.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _contributorCard(_contributors[i]),
                      ),
          ),
          const MyContributionPaymentsTab(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Center(
              child: AppIcon('contributors', size: 32, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No contributors yet',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Your contributor address book will appear here once you add people who can contribute to your events.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _contributorCard(dynamic contributor) {
    final c = contributor is Map<String, dynamic>
        ? contributor
        : Map<String, dynamic>.from(contributor as Map? ?? {});
    final name = c['name']?.toString() ?? 'Unknown';
    final email = c['email']?.toString() ?? '';
    final phone = c['phone']?.toString() ?? '';
    final notes = c['notes']?.toString() ?? '';
    final id = c['id']?.toString() ?? '';

    // The API enriches contributors with linked Nuru user info when the
    // contributor phone matches a registered Nuru account. Different
    // versions expose this under slightly different keys - handle all.
    final nuruUser = c['nuru_user'] is Map ? Map<String, dynamic>.from(c['nuru_user']) : null;
    final avatarUrl = (c['avatar_url'] ??
            c['user_avatar'] ??
            c['avatar'] ??
            (nuruUser?['avatar_url']) ??
            (nuruUser?['avatar']))
        ?.toString();
    final isNuruUser = (c['is_nuru_user'] == true) ||
        (c['user_id'] != null && c['user_id'].toString().isNotEmpty) ||
        nuruUser != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(name, avatarUrl, isNuruUser),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name only - no verification-style pill next to usernames
                // (per Nuru policy). The avatar ring already signals a linked
                // Nuru account.
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const AppIcon('phone', size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ),
                if (email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      const AppIcon('email', size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textTertiary, height: 1.35, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
          // Inline edit + delete actions - surfaced directly so users see them
          // at a glance instead of hidden behind a 3-dot menu.
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _rowAction(
                asset: 'assets/icons/pen-icon.svg',
                tint: AppColors.textSecondary,
                tooltip: context.trw('edit'),
                onTap: () => _editContributor(c),
              ),
              const SizedBox(height: 6),
              _rowAction(
                asset: 'assets/icons/delete-icon.svg',
                tint: AppColors.error,
                tooltip: context.trw('delete'),
                onTap: id.isEmpty ? null : () => _deleteContributor(id, name),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowAction({
    required String asset,
    required Color tint,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              onTap == null ? tint.withOpacity(0.4) : tint,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String name, String? url, bool isNuruUser) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final inner = (url != null && url.isNotEmpty)
        ? ClipOval(
            child: CachedNetworkImage(
              imageUrl: url,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.primarySoft),
              errorWidget: (_, __, ___) => _initialAvatar(initial),
            ),
          )
        : _initialAvatar(initial);
    if (!isNuruUser) {
      return SizedBox(width: 46, height: 46, child: inner);
    }
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFFFFB259)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipOval(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(1.5),
          child: ClipOval(child: inner),
        ),
      ),
    );
  }

  Widget _initialAvatar(String initial) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primarySoft),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
      ),
    );
  }
}

/// Pill-style tab bar matching the event-details page aesthetic.
class _PillTabs extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  const _PillTabs({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) => Row(
          children: List.generate(tabs.length, (i) {
            final active = controller.index == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => controller.animateTo(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tabs[i],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
