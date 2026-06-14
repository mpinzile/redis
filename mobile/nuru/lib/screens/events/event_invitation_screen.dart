import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/share_helpers.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/events_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../home/widgets/pill_tabs.dart';
import '../invitation_cards/svg_card_renderer.dart';
import '../invitation_cards/svg_template_registry.dart';
import '../../features/card_designer/card_designer_screen.dart';
import '../../features/card_designer/card_renderer.dart';
import '../../features/card_designer/model.dart';

/// "Create Invitation" screen - premium designer where organisers pick a
/// template variant per event type and persist that choice on the event so
/// preview, share, and download all render the same card.
class EventInvitationScreen extends StatefulWidget {
  final String eventId;
  final String? eventTypeKey;
  final String? themeColorHex;
  final String? eventTitle;

  const EventInvitationScreen({
    super.key,
    required this.eventId,
    this.eventTypeKey,
    this.themeColorHex,
    this.eventTitle,
  });

  @override
  State<EventInvitationScreen> createState() => _EventInvitationScreenState();
}

class _EventInvitationScreenState extends State<EventInvitationScreen> {
  // Tabs hydrate from /event-types so they stay in lockstep with create-event.
  // Fallback list mirrors the platform's event types (matches mockup).
  List<_TypeTab> _types = const [
    _TypeTab('all', 'All'),
    _TypeTab('wedding', 'Wedding'),
    _TypeTab('corporate', 'Corporate'),
    _TypeTab('birthday', 'Birthday'),
    _TypeTab('burial', 'Burial'),
    _TypeTab('anniversary', 'Anniversary'),
    _TypeTab('product_launch', 'Product Launch'),
    _TypeTab('conference', 'Conference'),
    _TypeTab('festival', 'Festival'),
    _TypeTab('graduation', 'Graduation'),
    _TypeTab('baby_shower', 'Baby Shower'),
    _TypeTab('exhibition', 'Exhibition'),
    _TypeTab('send_off', 'Send Off'),
  ];

  int _activeType = 0;
  int _activeVariant = 0;
  late PageController _pager;

  bool _loading = true;
  bool _saving = false;

  String _title = '';
  String _date = '';
  String _time = '';
  String _venue = '';
  String _organizer = '';
  Color _accent = const Color(0xFFD4AF37);
  String? _serverTemplateId;
  // Editable copy overrides - persisted as events.invitation_content (JSONB).
  InvitationContent _overrides = const InvitationContent();

  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pager = PageController(viewportFraction: 0.86);
    _activeType = _resolveTypeIndex(widget.eventTypeKey);
    _bootstrap();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  int _resolveTypeIndex(String? key) {
    if (key == null) return 0;
    final k = key.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    for (int i = 0; i < _types.length; i++) {
      if (_types[i].key == k || k.contains(_types[i].key)) return i;
    }
    return 0;
  }

  Future<void> _bootstrap() async {
    final accent = _hexToColor(widget.themeColorHex);
    if (accent != null) _accent = accent;
    if (widget.eventTitle != null) _title = widget.eventTitle!;

    // Load event types (so tabs always match create-event)
    try {
      final tres = await EventsService.getEventTypes();
      if (tres['success'] == true && tres['data'] is List) {
        final list = (tres['data'] as List).whereType<Map>().toList();
        if (list.isNotEmpty) {
          _types = [
            const _TypeTab('all', 'All'),
            ...list.map((t) {
              final name = (t['name'] ?? '').toString();
              final key = name.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
              return _TypeTab(key, name);
            }),
          ];
          _activeType = _resolveTypeIndex(widget.eventTypeKey);
        }
      }
    } catch (_) {}

    try {
      final res = await EventsService.getEventById(widget.eventId);
      if (res['success'] == true) {
        final data = res['data'] is Map ? res['data'] as Map : {};
        _title = (data['title'] ?? data['name'] ?? _title).toString();
        _date = (data['start_date'] ?? '').toString();
        _time = (data['start_time'] ?? '').toString();
        _venue = (data['venue'] ?? data['location'] ?? '').toString();
        final org = data['organizer'];
        if (org is Map) _organizer = (org['name'] ?? '').toString();
        final tc = data['theme_color']?.toString();
        final c = _hexToColor(tc);
        if (c != null) _accent = c;
        // Persisted choice
        _serverTemplateId =
            (data['invitation_template_id'] ?? '').toString().isEmpty
                ? null
                : data['invitation_template_id'].toString();
        final acHex = data['invitation_accent_color']?.toString();
        final ac = _hexToColor(acHex);
        if (ac != null) _accent = ac;

        // Hydrate editable copy overrides
        final ic = data['invitation_content'];
        if (ic is Map) {
          _overrides = InvitationContent.fromJson(Map<String, dynamic>.from(ic));
        }

        // Hydrate active tab/variant from saved SVG template id (e.g. "wedding-botanical").
        if (_serverTemplateId != null) {
          final tpl = templateById(_serverTemplateId);
          if (tpl != null) {
            // Pick first matching tab whose key resolves to one of the template's categories.
            for (int i = 0; i < _types.length; i++) {
              final cats = _categoriesForTypeKey(_types[i].key);
              if (tpl.category.any(cats.contains)) {
                _activeType = i;
                break;
              }
            }
            final list = _templatesForActiveType();
            final idx = list.indexWhere((t) => t.id == tpl.id);
            if (idx >= 0) _activeVariant = idx;
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pager.hasClients && _activeVariant > 0) {
        _pager.jumpToPage(_activeVariant);
      }
    });
  }

  Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  String _hexFromColor(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Future<void> _persistTemplate({bool persistContent = false}) async {
    final list = _templatesForActiveType();
    if (list.isEmpty) return;
    final safeIdx = _activeVariant.clamp(0, list.length - 1);
    final id = list[safeIdx].id;
    _serverTemplateId = id;
    try {
      await EventsService.updateEvent(
        widget.eventId,
        invitationTemplateId: id,
        invitationAccentColor: _hexFromColor(_accent),
        invitationContent: persistContent ? _overridesToJson(_overrides) : null,
      );
    } catch (_) {}
  }

  Map<String, dynamic> _overridesToJson(InvitationContent c) {
    final m = <String, dynamic>{};
    if ((c.headline ?? '').isNotEmpty) m['headline'] = c.headline;
    if ((c.subHeadline ?? '').isNotEmpty) m['sub_headline'] = c.subHeadline;
    if ((c.hostLine ?? '').isNotEmpty) m['host_line'] = c.hostLine;
    if ((c.body ?? '').isNotEmpty) m['body'] = c.body;
    if ((c.footerNote ?? '').isNotEmpty) m['footer_note'] = c.footerNote;
    if ((c.dressCodeLabel ?? '').isNotEmpty) m['dress_code_label'] = c.dressCodeLabel;
    if ((c.rsvpLabel ?? '').isNotEmpty) m['rsvp_label'] = c.rsvpLabel;
    if (c.qrOverride != null) m['qr_override'] = c.qrOverride!.toJson();
    if (c.hiddenIds.isNotEmpty) m['hidden_ids'] = c.hiddenIds;
    if (c.designDoc != null) m['design_doc'] = c.designDoc;
    return m;
  }

  // Map an event-type tab key to the registry's category buckets.
  // Mirrors web's _eventTypeCategoryMap so mobile picks the same templates.
  List<String> _categoriesForTypeKey(String key) {
    switch (key) {
      case 'all':
        return const [
          'wedding','birthday','sendoff','anniversary','memorial',
          'corporate','conference','graduation','baby_shower'
        ];
      case 'wedding': return const ['wedding'];
      case 'birthday': return const ['birthday'];
      case 'send_off':
      case 'sendoff': return const ['sendoff'];
      case 'anniversary': return const ['anniversary'];
      case 'burial':
      case 'memorial': return const ['memorial'];
      case 'corporate':
      case 'product_launch':
      case 'festival':
      case 'exhibition': return const ['corporate'];
      case 'conference': return const ['conference','corporate'];
      case 'graduation': return const ['graduation'];
      case 'baby_shower': return const ['baby_shower'];
      default: return const ['wedding'];
    }
  }

  List<SvgCardTemplate> _templatesForActiveType() {
    final cats = _categoriesForTypeKey(_types[_activeType].key);
    final list = kSvgTemplates
        .where((t) => t.category.any(cats.contains))
        .toList();
    return list.isEmpty ? kSvgTemplates : list;
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return 'SAT, 14 JUN 2026';
    try {
      final d = DateTime.parse(dateStr);
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      const months = [
        'JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'
      ];
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTime(String t) {
    if (t.isEmpty) return '4:00 PM';
    final parts = t.contains('T') ? t.split('T').last.split(':') : t.split(':');
    if (parts.length < 2) return t;
    int h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    if (h == 0) h = 12;
    if (h > 12) h -= 12;
    return '$h:$m $ampm';
  }

  // Tanzanian sample names per category (used when no real guest)
  String _sampleName() {
    switch (_types[_activeType].key) {
      case 'wedding':
      case 'anniversary':
        return 'Asha & Baraka';
      case 'birthday':
        return 'Neema Mushi';
      case 'baby_shower':
        return 'Baby Mwakasege';
      case 'graduation':
        return 'John Mollel';
      case 'send_off':
        return 'Lulu Massawe';
      case 'burial':
        return 'In Memory of Mzee Mushi';
      case 'corporate':
      case 'product_launch':
      case 'conference':
      case 'exhibition':
      case 'festival':
        return 'Honoured Guest';
      default:
        return 'Asha Mwakasege';
    }
  }

  String _greeting() {
    switch (_types[_activeType].key) {
      case 'wedding':
        return 'TOGETHER WITH THEIR FAMILIES';
      case 'birthday':
        return 'JOIN US TO CELEBRATE';
      case 'burial':
        return 'IN LOVING MEMORY';
      case 'anniversary':
        return 'A LIFETIME TOGETHER';
      case 'send_off':
        return 'A FAREWELL CELEBRATION';
      case 'baby_shower':
        return 'A LITTLE ONE IS ON THE WAY';
      case 'graduation':
        return 'A NEW CHAPTER BEGINS';
      case 'corporate':
      case 'product_launch':
      case 'conference':
      case 'exhibition':
      case 'festival':
        return 'YOU ARE INVITED';
      default:
        return 'YOU ARE CORDIALLY INVITED';
    }
  }

  // ── SVG template renderer ──────────────────────────────────────
  Widget _renderTemplate(SvgCardTemplate tpl, double width) {
    final designDoc = _overrides.designDoc;
    final card = designDoc != null
        ? CardRenderer(
            doc: CardDesignDoc.fromJson(designDoc),
            context: _designerContext(),
          )
        : SvgCardRenderer(
            template: tpl,
            contentOverrides: _overrides.isEmpty ? null : _overrides,
            data: SvgCardData(
              guestName: _sampleName(),
              secondName: tpl.fields.secondNameField != null ? 'Baraka' : null,
              eventTitle: _title.isEmpty ? 'Your Event' : _title,
              date: _formatDate(_date),
              time: _formatTime(_time),
              venue: _venue.isEmpty ? 'TBA' : _venue,
              address: _venue,
              qrValue: widget.eventId,
            ),
          );
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: card,
      ),
    );
  }

  // Build the per-render context used by CardRenderer (placeholder substitution
  // + QR payload). When a real guest downloads the card later, the same
  // context type is built with their guest name + invite token.
  CardRenderContext _designerContext() => CardRenderContext(
        guestName: _sampleName(),
        eventTitle: _title.isEmpty ? 'Your Event' : _title,
        eventDate: _formatDate(_date),
        eventTime: _formatTime(_time),
        eventLocation: _venue.isEmpty ? 'TBA' : _venue,
        organizerName: _organizer,
        inviteCode: 'PREVIEW',
        qrPayload: widget.eventId,
      );

  Future<void> _openDesigner() async {
    final hasExisting = _overrides.designDoc != null;
    // Always show the launcher: continue editing, start blank, or seed from
    // a template-style starter. This makes the editor a real workspace, not
    // just an extension of the picked SVG template.
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Card workspace',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      decorationThickness: 0)),
            ),
            if (hasExisting)
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('Continue editing my design'),
                onTap: () => Navigator.pop(ctx, 'continue'),
              ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Blank canvas'),
              subtitle: const Text('Build a fully custom card from scratch'),
              onTap: () => Navigator.pop(ctx, 'blank'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Smart starter'),
              subtitle: const Text(
                  'Title, guest name, date, venue and QR pre-placed'),
              onTap: () => Navigator.pop(ctx, 'starter'),
            ),
            if (hasExisting)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Reset custom design',
                    style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text(
                    'Removes the custom design and reverts to the template'),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'reset') {
      await _resetDesigner();
      return;
    }
    final initial = choice == 'continue' && hasExisting
        ? CardDesignDoc.fromJson(_overrides.designDoc!)
        : choice == 'blank'
            ? CardDesignDoc.blank()
            : CardDesignDoc.starter(
                accent: _accent,
                title: _title.isEmpty ? '{{event_title}}' : _title,
              );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CardDesignerScreen(
        initial: initial,
        sampleContext: _designerContext(),
        onSave: (doc) async {
          setState(() {
            _overrides = _overrides.copyWith(designDoc: doc.toJson());
          });
          await _persistTemplate(persistContent: true);
          if (mounted) {
            AppSnackbar.success(context, 'Design saved');
          }
        },
      ),
    ));
  }

  Future<void> _resetDesigner() async {
    setState(() {
      _overrides = _overrides.copyWith(clearDesignDoc: true);
    });
    await _persistTemplate(persistContent: true);
  }

  Future<File> _renderToFile() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw 'Card not ready';
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) throw 'Failed to render';
    final dir = await getTemporaryDirectory();
    final safe = (_title.isEmpty ? 'invitation' : _title)
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File(
        '${dir.path}/${safe}_invitation_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bd.buffer.asUint8List());
    return file;
  }

  Future<void> _share() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final file = await _renderToFile();
      await Share.shareXFiles([XFile(file.path)],
          subject: '$_title invitation',
          text: 'You are invited to $_title',
        sharePositionOrigin: sharePositionOrigin(context),
      );
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not share invitation');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openPreview() {
    final list = _templatesForActiveType();
    if (list.isEmpty) return;
    final tpl = list[_activeVariant.clamp(0, list.length - 1)];
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullScreenPreview(
        builder: () => _renderTemplate(tpl, 360),
        onShare: _share,
        title: _title.isEmpty ? 'Invitation Preview' : _title,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/arrow-left-icon.svg',
            width: 22,
            height: 22,
            colorFilter:
                const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        centerTitle: true,
        title: Text('Create Invitation',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _openPreview,
            child: Text('Preview',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content(),
    );
  }

  Widget _content() {
    return Column(children: [
      const SizedBox(height: 6),
      // Event-type tabs - same visual style as the home feed (PillTabs)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: PillTabs(
          tabs: _types.map((t) => t.label).toList(),
          selected: _activeType,
          onChanged: (i) {
            setState(() {
              _activeType = i;
              _activeVariant = 0;
            });
            if (_pager.hasClients) _pager.jumpToPage(0);
            _persistTemplate();
          },
        ),
      ),

      // Swipeable card variants - bespoke SVG templates from the registry
      Expanded(
        child: Builder(builder: (_) {
          final tpls = _templatesForActiveType();
          final count = tpls.length;
          return Column(children: [
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: count,
                onPageChanged: (i) {
                  setState(() => _activeVariant = i);
                  _persistTemplate();
                },
                itemBuilder: (ctx, i) {
                  return LayoutBuilder(builder: (c, cons) {
                    final w = (cons.maxWidth - 40).clamp(260.0, 360.0).toDouble();
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: RepaintBoundary(
                          key: i == _activeVariant ? _captureKey : null,
                          child: _renderTemplate(tpls[i], w),
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
            // Visible "now editing" template header - shows the user exactly
            // which SVG template they are customising and lets them browse all.
            if (count > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: _NowEditingHeader(
                  index: _activeVariant.clamp(0, count - 1) + 1,
                  total: count,
                  template: tpls[_activeVariant.clamp(0, count - 1)],
                  accent: _accent,
                  hasOverrides: !_overrides.isEmpty,
                  onBrowse: _showTemplatePicker,
                ),
              ),
            // Pagination dots
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: List.generate(count, (i) {
                  final active = _activeVariant == i;
                  return GestureDetector(
                    onTap: () => _pager.animateToPage(i,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut),
                    child: Container(
                      width: active ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ]);
        }),
      ),

      // Editor toolbar - Designer / Template / Copy / Layout / Style / Details
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            _customizeTile(Icons.brush_rounded,
                _overrides.designDoc != null ? 'Edit Design' : 'Designer',
                onTap: _openDesigner),
            _customizeTile(Icons.dashboard_customize_rounded, 'Template',
                onTap: _showTemplatePicker),
            _customizeTile(Icons.edit_note_rounded, 'Copy',
                onTap: _showCopySheet),
            _customizeTile(Icons.qr_code_2_rounded, 'Layout',
                onTap: _showQrLayoutSheet),
            _customizeTile(Icons.palette_outlined, 'Style',
                onTap: _showStyleSheet),
          ],
        ),
      ),

      // Share Invitation CTA
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _share,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.ios_share_rounded,
                      color: Colors.black, size: 20),
              label: Text(
                _saving ? 'Preparing…' : 'Share Invitation',
                style: GoogleFonts.inter(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _customizeTile(IconData icon, String label,
      {required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEDEF)),
          ),
          child: Column(children: [
            Icon(icon, size: 20, color: AppColors.textPrimary),
            const SizedBox(height: 5),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Template picker - full grid with thumbnails of every bespoke SVG.
  void _showTemplatePicker() {
    final tpls = _templatesForActiveType();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scroll) {
            return Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Choose a template',
                          style: GoogleFonts.playfairDisplay(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${tpls.length} bespoke designs for ${_types[_activeType].label}',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 480 / 720, // card + caption
                  ),
                  itemCount: tpls.length,
                  itemBuilder: (_, i) {
                    final tpl = tpls[i];
                    final selected = i == _activeVariant;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _activeVariant = i);
                        if (_pager.hasClients) _pager.jumpToPage(i);
                        _persistTemplate();
                        Navigator.pop(ctx);
                      },
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? AppColors.primary : const Color(0xFFEAEAEA),
                                width: selected ? 2.4 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SvgPicture.asset(
                              tpl.assetPath,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text('${(i + 1).toString().padLeft(2, '0')}',
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  letterSpacing: 1.4,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(tpl.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle,
                                size: 14, color: AppColors.primary),
                        ]),
                      ]),
                    );
                  },
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  // ── Copy editor - every editable text field on the bespoke SVG card.
  void _showCopySheet() {
    final headline = TextEditingController(text: _overrides.headline ?? '');
    final sub = TextEditingController(text: _overrides.subHeadline ?? '');
    final host = TextEditingController(text: _overrides.hostLine ?? '');
    final body = TextEditingController(text: _overrides.body ?? '');
    final footer = TextEditingController(text: _overrides.footerNote ?? '');
    final dress = TextEditingController(text: _overrides.dressCodeLabel ?? '');
    final rsvp = TextEditingController(text: _overrides.rsvpLabel ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scroll) {
            return Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Edit invitation copy',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Rewrite every line on the card. Leave blank to use the template default.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textTertiary)),
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  children: [
                    _copyField('Headline', 'You are cordially invited', headline),
                    _copyField('Sub headline', 'Together with their families', sub),
                    _copyField('Host line', 'Hosted by Mwakasege Family', host),
                    _copyField('Body', 'A celebration of love and tradition', body, maxLines: 3),
                    _copyField('Footer note', 'Reception to follow', footer),
                    _copyField('Dress code label', 'Black tie · TZ formal', dress),
                    _copyField('RSVP label', 'Scan to RSVP', rsvp),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _overrides = const InvitationContent());
                          _persistTemplate(persistContent: true);
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        child: Text('Reset',
                            style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _overrides = InvitationContent(
                              headline: headline.text.trim().isEmpty ? null : headline.text.trim(),
                              subHeadline: sub.text.trim().isEmpty ? null : sub.text.trim(),
                              hostLine: host.text.trim().isEmpty ? null : host.text.trim(),
                              body: body.text.trim().isEmpty ? null : body.text.trim(),
                              footerNote: footer.text.trim().isEmpty ? null : footer.text.trim(),
                              dressCodeLabel: dress.text.trim().isEmpty ? null : dress.text.trim(),
                              rsvpLabel: rsvp.text.trim().isEmpty ? null : rsvp.text.trim(),
                            );
                          });
                          _persistTemplate(persistContent: true);
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Save copy',
                            style: GoogleFonts.inter(
                                color: Colors.black,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _copyField(String label, String hint, TextEditingController c,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 10,
                letterSpacing: 1.4,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: maxLines,
          autocorrect: false,
          enableSuggestions: false,
          style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              decorationThickness: 0),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                color: const Color(0xFFB6B6B6),
                fontSize: 13,
                fontWeight: FontWeight.w500),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ]),
    );
  }

  // ── QR & Layout designer - drag/resize the QR and toggle text elements ──
  void _showQrLayoutSheet() async {
    final list = _templatesForActiveType();
    if (list.isEmpty) return;
    final tpl = list[_activeVariant.clamp(0, list.length - 1)];
    // Load element list & starting QR rect.
    final elements = await loadSvgTextElements(tpl);
    final auto = await autoQrRectFor(tpl);
    if (!mounted) return;
    final start = _overrides.qrOverride ??
        (auto != null
            ? QrOverride(x: auto.x, y: auto.y, size: auto.size)
            : const QrOverride(x: 204, y: 540, size: 72));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return _QrLayoutSheet(
          template: tpl,
          accent: _accent,
          eventId: widget.eventId,
          baseData: SvgCardData(
            guestName: _sampleName(),
            secondName: tpl.fields.secondNameField != null ? 'Baraka' : null,
            eventTitle: _title.isEmpty ? 'Your Event' : _title,
            date: _formatDate(_date),
            time: _formatTime(_time),
            venue: _venue.isEmpty ? 'TBA' : _venue,
            address: _venue,
            qrValue: widget.eventId,
          ),
          initialOverride: start,
          initialHidden: List<String>.from(_overrides.hiddenIds),
          textElements: elements,
          baseOverrides: _overrides,
          onSave: (qr, hiddenIds) {
            setState(() {
              _overrides = _overrides.copyWith(
                qrOverride: qr,
                hiddenIds: hiddenIds,
              );
            });
            _persistTemplate(persistContent: true);
          },
          onResetQr: () {
            setState(() {
              _overrides = _overrides.copyWith(clearQrOverride: true);
            });
            _persistTemplate(persistContent: true);
          },
        );
      },
    );
  }

  void _showStyleSheet() {
    final palette = <Color>[
      const Color(0xFFD4AF37),
      const Color(0xFFE63946),
      const Color(0xFF1D3557),
      const Color(0xFF2A9D8F),
      const Color(0xFF6A4C93),
      const Color(0xFF111111),
      const Color(0xFFB5651D),
      const Color(0xFFF77F00),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Accent Color',
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: palette
                  .map((c) => GestureDetector(
                        onTap: () {
                          setState(() => _accent = c);
                          _persistTemplate();
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _accent.value == c.value
                                    ? AppColors.primary
                                    : Colors.white,
                                width: 3),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ),
      ),
    );
  }

  void _showDetailsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Event Details',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _detailRow('Title', _title),
                _detailRow('Date', _formatDate(_date)),
                _detailRow('Time', _formatTime(_time)),
                _detailRow('Venue', _venue),
                if (_organizer.isNotEmpty) _detailRow('Host', _organizer),
              ]),
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 70,
            child: Text(k,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(v.isEmpty ? '-' : v,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600))),
      ]),
    );
  }
  // Legacy hand-painted card variants removed - invitations now render from
  // the bespoke SVG template registry (see _renderTemplate above).

}

class _TypeTab {
  final String key;
  final String label;
  const _TypeTab(this.key, this.label);
}

class _FullScreenPreview extends StatelessWidget {
  final Widget Function() builder;
  final VoidCallback onShare;
  final String title;
  const _FullScreenPreview({
    required this.builder,
    required this.onShare,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 56),
                child: builder(),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: Text(
              title,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.maybePop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Close',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.maybePop(context);
                    onShare();
                  },
                  icon: const Icon(Icons.ios_share_rounded,
                      size: 18, color: Colors.black),
                  label: Text('Share',
                      style: GoogleFonts.inter(
                          color: Colors.black, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visible "now editing" template header - sits between the carousel and the
// editor toolbar so the organiser always sees which bespoke SVG template they
// are customising. Designed in the editorial aesthetic: soft cream surface,
// gold rule, small uppercase index, large display name.
// ─────────────────────────────────────────────────────────────────────────────
class _NowEditingHeader extends StatelessWidget {
  final int index;
  final int total;
  final SvgCardTemplate template;
  final Color accent;
  final bool hasOverrides;
  final VoidCallback onBrowse;

  const _NowEditingHeader({
    required this.index,
    required this.total,
    required this.template,
    required this.accent,
    required this.hasOverrides,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final cats = template.category.map((c) => c.replaceAll('_', ' ')).join(' / ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF9F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE6D6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Left: gold index pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(index.toString().padLeft(2, '0'),
                style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A),
                    height: 1.0)),
            const SizedBox(height: 1),
            Text('OF ${total.toString().padLeft(2, '0')}',
                style: GoogleFonts.inter(
                    fontSize: 8,
                    letterSpacing: 1.4,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 14),
        // Middle: name + meta
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('NOW EDITING',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      letterSpacing: 1.6,
                      color: accent,
                      fontWeight: FontWeight.w800)),
              if (hasOverrides) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('CUSTOMISED',
                      style: GoogleFonts.inter(
                          fontSize: 8,
                          letterSpacing: 1.2,
                          color: const Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A))),
            const SizedBox(height: 1),
            Text('${cats.toUpperCase()} · ${template.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        // Right: browse button
        TextButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.grid_view_rounded,
              size: 16, color: AppColors.textPrimary),
          label: Text('Browse',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE6E6E6)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR & Layout designer sheet - drag the QR around the card with your finger,
// resize it with a slider, and toggle off any hardcoded text element you do
// not want on your invitation. All choices persist in events.invitation_content.
// ─────────────────────────────────────────────────────────────────────────────
class _QrLayoutSheet extends StatefulWidget {
  final SvgCardTemplate template;
  final Color accent;
  final String eventId;
  final SvgCardData baseData;
  final QrOverride initialOverride;
  final List<String> initialHidden;
  final List<SvgTextElement> textElements;
  final InvitationContent baseOverrides;
  final void Function(QrOverride qr, List<String> hiddenIds) onSave;
  final VoidCallback onResetQr;

  const _QrLayoutSheet({
    required this.template,
    required this.accent,
    required this.eventId,
    required this.baseData,
    required this.initialOverride,
    required this.initialHidden,
    required this.textElements,
    required this.baseOverrides,
    required this.onSave,
    required this.onResetQr,
  });

  @override
  State<_QrLayoutSheet> createState() => _QrLayoutSheetState();
}

class _QrLayoutSheetState extends State<_QrLayoutSheet> {
  static const double _svgW = 480;
  static const double _svgH = 680;
  static const double _minSize = 40;
  static const double _maxSize = 200;

  late double _x;
  late double _y;
  late double _size;
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _x = widget.initialOverride.x;
    _y = widget.initialOverride.y;
    _size = widget.initialOverride.size;
    _hidden = {...widget.initialHidden};
  }

  void _clamp() {
    _size = _size.clamp(_minSize, _maxSize);
    _x = _x.clamp(0.0, _svgW - _size);
    _y = _y.clamp(0.0, _svgH - _size);
  }

  InvitationContent _liveOverrides() => widget.baseOverrides.copyWith(
        qrOverride: QrOverride(x: _x, y: _y, size: _size),
        hiddenIds: _hidden.toList(),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (_, scroll) {
        return Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('QR & Layout',
                          style: GoogleFonts.playfairDisplay(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                          'Drag the QR with your finger. Resize with the slider. Hide any text you do not need.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ]),
              ),
              TextButton(
                onPressed: () {
                  widget.onResetQr();
                  Navigator.pop(context);
                },
                child: Text('Reset',
                    style: GoogleFonts.inter(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                _designerCanvas(),
                const SizedBox(height: 12),
                _sizeAndNudgeRow(),
                const SizedBox(height: 18),
                _elementsHeader(),
                const SizedBox(height: 6),
                ...widget.textElements.map(_elementTile),
                const SizedBox(height: 18),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.onSave(
                      QrOverride(x: _x, y: _y, size: _size),
                      _hidden.toList(),
                    );
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save layout',
                      style: GoogleFonts.inter(
                          color: Colors.black, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _designerCanvas() {
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final h = w * (_svgH / _svgW);
      final scale = w / _svgW;
      return Stack(children: [
        // Live SVG card preview with the user's QR + hide overrides applied.
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: widget.accent.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SvgCardRenderer(
            template: widget.template,
            data: widget.baseData,
            contentOverrides: _liveOverrides(),
          ),
        ),
        // Allowed-area frame (whole card).
        Positioned(
          left: 0,
          top: 0,
          width: w,
          height: h,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: widget.accent.withOpacity(0.25), width: 1),
              ),
            ),
          ),
        ),
        // Drag handle on top of the QR - same square in screen coords.
        Positioned(
          left: _x * scale,
          top: _y * scale,
          width: _size * scale,
          height: _size * scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) {
              setState(() {
                _x += d.delta.dx / scale;
                _y += d.delta.dy / scale;
                _clamp();
              });
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: widget.accent, width: 2),
                color: widget.accent.withOpacity(0.05),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.open_with_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _sizeAndNudgeRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF9F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE6D6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('SIZE',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${_size.round()} px',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.accent,
            inactiveTrackColor: const Color(0xFFEDE6D6),
            thumbColor: widget.accent,
            overlayColor: widget.accent.withOpacity(0.14),
            trackHeight: 3,
          ),
          child: Slider(
            value: _size.clamp(_minSize, _maxSize),
            min: _minSize,
            max: _maxSize,
            onChanged: (v) => setState(() {
              _size = v;
              _clamp();
            }),
          ),
        ),
        const SizedBox(height: 4),
        Text('NUDGE',
            style: GoogleFonts.inter(
                fontSize: 10,
                letterSpacing: 1.4,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          _nudge(Icons.arrow_back_rounded, () => _move(-4, 0)),
          const SizedBox(width: 8),
          _nudge(Icons.arrow_upward_rounded, () => _move(0, -4)),
          const SizedBox(width: 8),
          _nudge(Icons.arrow_downward_rounded, () => _move(0, 4)),
          const SizedBox(width: 8),
          _nudge(Icons.arrow_forward_rounded, () => _move(4, 0)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _x = (_svgW - _size) / 2;
                _y = (_svgH - _size) / 2;
                _clamp();
              });
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.center_focus_strong_rounded,
                size: 14, color: AppColors.textPrimary),
            label: Text('Centre',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ]),
      ]),
    );
  }

  void _move(double dx, double dy) {
    setState(() {
      _x += dx;
      _y += dy;
      _clamp();
    });
  }

  Widget _nudge(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _elementsHeader() {
    return Row(children: [
      Text('TEXT ELEMENTS',
          style: GoogleFonts.inter(
              fontSize: 10,
              letterSpacing: 1.4,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w800)),
      const Spacer(),
      Text('${_hidden.length} hidden',
          style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _elementTile(SvgTextElement e) {
    final hidden = _hidden.contains(e.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: hidden ? const Color(0xFFF7F7F8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDEF)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.id.toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  e.sample.isEmpty ? '-' : e.sample,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: hidden
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: hidden ? TextDecoration.lineThrough : null,
                  ),
                ),
              ]),
        ),
        Switch.adaptive(
          value: !hidden,
          activeColor: widget.accent,
          onChanged: (v) => setState(() {
            if (v) {
              _hidden.remove(e.id);
            } else {
              _hidden.add(e.id);
            }
          }),
        ),
      ]),
    );
  }
}
