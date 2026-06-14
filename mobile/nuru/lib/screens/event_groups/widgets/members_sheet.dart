import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/nuru_search_bar.dart';
import '../../../core/services/event_groups_service.dart';
import '../../../core/widgets/nuru_skeleton.dart';

class MembersSheet extends StatefulWidget {
  final String groupId;
  final bool isAdmin;
  final VoidCallback? onChanged;
  final bool embedded;
  final VoidCallback? onClose;
  const MembersSheet({super.key, required this.groupId, required this.isAdmin, this.onChanged,
      this.embedded = false, this.onClose});

  @override
  State<MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<MembersSheet> {
  List<dynamic> _members = [];
  bool _loading = true;
  bool _syncing = false;
  String _search = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await EventGroupsService.members(widget.groupId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _members = res['data'] is Map ? (res['data']['members'] ?? []) : [];
      }
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await EventGroupsService.syncMembers(widget.groupId);
    setState(() => _syncing = false);
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _copyInvite(Map m) async {
    final res = await EventGroupsService.createInvite(widget.groupId,
        contributorId: m['contributor_id'], phone: m['guest_phone'], name: m['display_name']);
    if (res['success'] == true && res['data'] is Map) {
      final token = res['data']['token'];
      final url = 'https://nuru.tz/g/$token';
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link copied')));
      }
    }
  }

  Future<void> _inviteMembers() async {
    // Generate a generic group invite link the admin can share with anyone.
    final res = await EventGroupsService.createInvite(widget.groupId);
    if (!mounted) return;
    if (res['success'] == true && res['data'] is Map) {
      final token = (res['data']['token'] ?? '').toString();
      if (token.isEmpty) return;
      final url = 'https://nuru.tz/g/$token';
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite link copied · share with anyone')),
      );
    }
  }

  String _initials(String n) =>
      n.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();

  @override
  Widget build(BuildContext context) {
    final filtered = _members.where((m) =>
        _search.isEmpty || (m['display_name'] ?? '').toString().toLowerCase().contains(_search.toLowerCase())).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.embedded
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: widget.embedded
            ? const Border(left: BorderSide(color: Color(0xFFE5E5EA)))
            : null,
      ),
      constraints: widget.embedded
          ? const BoxConstraints.expand()
          : BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle (sheet only)
        if (!widget.embedded)
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2))),
        // Header
        Padding(
          padding: EdgeInsets.fromLTRB(12, widget.embedded ? 10 : 4, 8, 6),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Members',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('${_members.length} member${_members.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 9.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
            if (widget.isAdmin)
              _iconButton(
                    icon: _syncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                    onTap: _syncing ? null : _sync,
              ),
            if (widget.embedded)
              _iconButton(
                icon: Icon(Icons.close_rounded, size: 22, color: AppColors.textSecondary),
                onTap: widget.onClose,
              ),
          ]),
        ),
        // Search - matches "Search events" style: filled, pill, no border
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: NuruSearchBar(
            hintText: 'Search members…',
            debounce: const Duration(milliseconds: 200),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 8),
        // Member list
        Expanded(
          child: _loading
              ? const NuruSkeletonList(itemCount: 6)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final m = filtered[i];
                    return _memberRow(m);
                  },
                ),
        ),
        // Footer: Invite Members pill (admin only) - outlined per mockup
        if (widget.isAdmin)
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(color: Colors.white),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _inviteMembers,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary, width: 1.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset('assets/icons/user-add-icon.svg',
                          width: 14, height: 14,
                          colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                      const SizedBox(width: 6),
                      Text('Invite Members',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _memberRow(Map m) {
    final isAdmin = m['is_admin'] == true;
    final canManage = widget.isAdmin && !isAdmin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + name + role badge
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primarySoft,
                backgroundImage:
                    m['avatar_url'] != null ? NetworkImage(m['avatar_url']) : null,
                child: m['avatar_url'] == null
                    ? Text(_initials(m['display_name'] ?? '?'),
                        style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 9))
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(m['display_name'] ?? '',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.textPrimary)),
              ),
              _roleBadge(isAdmin),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _actionButton(
                  icon: Icon(Icons.link_rounded,
                      size: 12, color: AppColors.textPrimary),
                  label: 'Copy Link',
                  color: AppColors.textPrimary,
                  onTap: () => _copyInvite(m),
                ),
                const SizedBox(width: 8),
                _actionButton(
                  icon: SvgPicture.asset('assets/icons/delete-icon.svg',
                      width: 12,
                      height: 12,
                      colorFilter: ColorFilter.mode(
                          AppColors.error, BlendMode.srcIn)),
                  label: 'Remove',
                  color: AppColors.error,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleBadge(bool isAdmin) {
    final bg = isAdmin
        ? AppColors.primary.withOpacity(0.12)
        : const Color(0xFFF1F1F3);
    final fg = isAdmin ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(isAdmin ? 'Admin' : 'Member',
          style: GoogleFonts.inter(
              fontSize: 8.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _actionButton({
    required Widget icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 5),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton({required Widget icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );
  }
}
