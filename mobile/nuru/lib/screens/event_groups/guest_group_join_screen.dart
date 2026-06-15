import 'package:flutter/material.dart';
import 'package:nuru/widgets/skeletons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/event_groups_service.dart';
import 'event_group_workspace_screen.dart';

/// Public guest landing page (deep-link target for `/g/:token`).
/// Lets non-Nuru contributors claim their invite and enter the workspace
/// using a group-scoped JWT.
class GuestGroupJoinScreen extends StatefulWidget {
  final String token;
  const GuestGroupJoinScreen({super.key, required this.token});

  @override
  State<GuestGroupJoinScreen> createState() => _GuestGroupJoinScreenState();
}

class _GuestGroupJoinScreenState extends State<GuestGroupJoinScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await EventGroupsService.previewInvite(widget.token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data']);
        final pf = _data!['prefill'] as Map?;
        _name.text = pf?['name'] ?? '';
        _phone.text = pf?['phone'] ?? '';
      } else {
        _error = res['message'] ?? 'Invite unavailable';
      }
    });
  }

  Future<void> _join() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    final res = await EventGroupsService.claimInvite(widget.token,
        name: _name.text.trim(), phone: _phone.text.trim().isEmpty ? null : _phone.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true && res['data'] is Map) {
      final guestToken = res['data']['guest_token'];
      if (guestToken is String) await EventGroupsService.saveGuestToken(guestToken);
      final groupId = res['data']['group_id'];
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => EventGroupWorkspaceScreen(groupId: groupId),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Could not join')));
    }
  }

  String _initials(String n) =>
      n.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0].toUpperCase()).join();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? SkeletonGroup(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: const [
                    SkeletonBox(height: 180, radius: 18),
                    SizedBox(height: 18),
                    SkeletonLine(widthFactor: 0.6, height: 16),
                    SizedBox(height: 10),
                    SkeletonLine(widthFactor: 0.4, height: 12),
                    SizedBox(height: 24),
                    SkeletonBox(height: 50, radius: 14),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.link_off, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Invite unavailable',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(_error ?? '',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
                      ]),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 12),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -38),
                        child: Center(
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primarySoft,
                              backgroundImage: _data?['group']?['image_url'] != null
                                  ? NetworkImage(_data!['group']['image_url']) : null,
                              child: _data?['group']?['image_url'] == null
                                  ? Text(_initials(_data?['group']?['name'] ?? ''),
                                      style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary))
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text("YOU'RE INVITED TO",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.textTertiary)),
                          const SizedBox(height: 6),
                          Text(_data?['group']?['name'] ?? '',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
                          if (_data?['group']?['event_name'] != null) ...[
                            const SizedBox(height: 2),
                            Text('for ${_data!['group']['event_name']}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              Icon(Icons.verified_outlined, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                'Join the group chat & live scoreboard. No account needed · your link gives you secure access to this group only.',
                                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                              )),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name *', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _submitting ? null : _join,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _submitting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.chat_bubble_outline),
                            label: const Text('Join group'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
      ),
    );
  }
}
