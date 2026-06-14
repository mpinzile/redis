
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/events_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/ticketing_service.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/nuru_date_time_picker.dart';
import '../../core/widgets/amount_input.dart';
import '../../core/widgets/agreement_gate.dart';
import 'event_detail_screen.dart';
import 'map_picker_screen.dart';
import 'widgets/ticket_class_form.dart';
import 'widgets/event_ticketing_card.dart';
// Recommendations + card-template pickers removed from create flow.
import '../../core/l10n/l10n_helper.dart';
import '../../core/utils/money_format.dart';

class CreateEventScreen extends StatefulWidget {
  final Map<String, dynamic>? editEvent;
  const CreateEventScreen({super.key, this.editEvent});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  static const int _maxCoverImageBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  final _expectedGuestsCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  // Legacy controllers kept so we can still hydrate old events that only
  // stored ``dress_code`` / ``special_instructions``. New events use the
  // flexible ``_extraDetailsItems`` list below instead.
  final _dressCodeCtrl = TextEditingController();
  final _specialInstructionsCtrl = TextEditingController();
  final _reminderContactPhoneCtrl = TextEditingController();
  final _contributionPaymentInstructionsCtrl = TextEditingController();
  final _whatToExpectNotesCtrl = TextEditingController();
  final List<Map<String, String>> _whatToExpectItems = [];
  int? _wteExpandedIndex;
  static const List<String> _wteIconChoices = [
    'star','calendar','clock','heart','camera','users','microphone','user'
  ];
  // Free-form extra detail rows ({label, details}) - replaces dress_code /
  // special_instructions on the create UI.
  final List<Map<String, String>> _extraDetailsItems = [];
  int? _extraExpandedIndex;
  final _guestOfHonorCtrl = TextEditingController();
  String? _eventTypeId;
  String _visibility = 'private';
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  bool _sellsTickets = false;
  bool _isPublic = false;
  bool _saving = false;
  String? _imagePath;
  String? _existingImageUrl;
  double? _venueLatitude;
  double? _venueLongitude;
  String? _venueAddress;
  List<Map<String, dynamic>> _apiEventTypes = [];
  bool _typesLoading = true;
  List<TicketClassData> _ticketClasses = [];

  // Event owner separation feature
  bool _createdForSomeoneElse = false;
  Map<String, dynamic>? _eventOwner; // {id, first_name, last_name, full_name, email, phone, avatar}
  final TextEditingController _recognizableOwnerNameCtrl = TextEditingController();
  final TextEditingController _ownerSearchCtrl = TextEditingController();
  Timer? _ownerSearchDebounce;
  List<Map<String, dynamic>> _ownerSearchResults = [];
  bool _ownerSearching = false;
  bool _showOwnerRegister = false;
  final TextEditingController _newOwnerFirstNameCtrl = TextEditingController();
  final TextEditingController _newOwnerLastNameCtrl = TextEditingController();
  final TextEditingController _newOwnerPhoneCtrl = TextEditingController();
  bool _registeringOwner = false;

  // Vendor selection (optional, can be added later)
  final List<Map<String, dynamic>> _selectedVendors = [];
  final TextEditingController _vendorSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _vendorResults = [];
  bool _vendorSearching = false;

  // Vendor IDs (user_service.id) the organiser wants to invite as sponsors.
  // Sent to POST /user-events/{id}/sponsors after the event is saved.
  final Set<String> _sponsorVendorIds = {};

  // 5-step wizard: 0 Basic, 1 When & Where, 2 Tickets, 3 Vendors, 4 Preview
  int _step = 0;
  static const List<String> _stepTitles = ['Basic Info', 'When & Where', 'Tickets', 'Vendors', 'Preview'];
  static const List<List<String>> _stepHeadings = [
    ['Basic Information', 'Tell us about your event.'],
    ['When & Where', 'Set the date, time and venue. Venue can be added later.'],
    ['Tickets & Visibility', 'Set up tickets and choose who can see your event.'],
    ['Vendors & Sponsors', 'Pick service providers and, if you like, invite some of them as sponsors. Everyone will be notified to confirm.'],
    ['Preview', 'Review your event details before publishing.'],
  ];

  bool get _isEdit => widget.editEvent != null;

  @override
  void initState() {
    super.initState();
    _loadEventTypes();
    if (_isEdit) {
      _populateFromEvent(widget.editEvent!);
      _loadExistingTicketClasses();
      // Re-fetch the full event so we never rely on a stale list payload that
      // may be missing description / cover_image / venue coordinates.
      _refreshEditPayload();
    } else {
      _checkAgreement();
    }
  }

  Future<void> _refreshEditPayload() async {
    final id = widget.editEvent?['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      final res = await EventsService.getEventById(id);
      if (!mounted || res['success'] != true) return;
      final data = res['data'];
      if (data is Map) {
        setState(() => _populateFromEvent(Map<String, dynamic>.from(data)));
      }
    } catch (_) {/* ignore - populate already ran from initial payload */}
  }

  Future<void> _loadExistingTicketClasses() async {
    final eventId = widget.editEvent?['id']?.toString();
    if (eventId == null) return;
    final res = await TicketingService.getMyTicketClasses(eventId);
    if (res['success'] == true && mounted) {
      final classes = res['data']?['ticket_classes'] as List? ?? [];
      setState(() {
        _ticketClasses = classes
          .map((tc) => TicketClassData.fromJson(tc as Map<String, dynamic>))
          .toList();
      });
    }
  }

  void _populateFromEvent(Map<String, dynamic> e) {
    _titleCtrl.text = extractStr(e['title']);
    _descCtrl.text = extractStr(e['description']);
    _locationCtrl.text = extractStr(e['location']);
    _venueCtrl.text = extractStr(e['venue']);
    _dressCodeCtrl.text = extractStr(e['dress_code']);
    _specialInstructionsCtrl.text = extractStr(e['special_instructions']);
    _reminderContactPhoneCtrl.text = extractStr(e['reminder_contact_phone']);
    _contributionPaymentInstructionsCtrl.text = extractStr(e['contribution_payment_instructions']);
    _whatToExpectNotesCtrl.text = extractStr(e['what_to_expect_notes']);
    _guestOfHonorCtrl.text = extractStr(e['guest_of_honor']);
    _whatToExpectItems.clear();
    final rawWte = e['what_to_expect'];
    if (rawWte is List) {
      for (final it in rawWte) {
        if (it is Map) {
          final label = (it['label'] ?? it['title'] ?? '').toString().trim();
          if (label.isEmpty) continue;
          _whatToExpectItems.add({
            'icon': (it['icon'] ?? 'sparkle').toString(),
            'label': label,
            'description': (it['description'] ?? '').toString(),
          });
        }
      }
    }
    // Extra details - prefer the new column; fall back to legacy dress_code
    // / special_instructions so users editing old events see them as rows
    // they can keep, edit, or delete.
    _extraDetailsItems.clear();
    final rawExtras = e['extra_details'];
    if (rawExtras is List) {
      for (final it in rawExtras) {
        if (it is Map) {
          final label = (it['label'] ?? '').toString().trim();
          final details = (it['details'] ?? it['description'] ?? '').toString().trim();
          if (label.isEmpty || details.isEmpty) continue;
          _extraDetailsItems.add({'label': label, 'details': details});
        }
      }
    }
    if (_extraDetailsItems.isEmpty) {
      final legacyDress = extractStr(e['dress_code']);
      final legacyInstr = extractStr(e['special_instructions']);
      if (legacyDress.isNotEmpty) {
        _extraDetailsItems.add({'label': 'Dress code', 'details': legacyDress});
      }
      if (legacyInstr.isNotEmpty) {
        _extraDetailsItems.add({'label': 'Special instructions', 'details': legacyInstr});
      }
    }
    String _toIntStr(dynamic v) {
      if (v == null) return '';
      final n = v is num ? v : num.tryParse(v.toString());
      if (n == null) return '';
      return n.toInt().toString();
    }
    if (e['expected_guests'] != null) _expectedGuestsCtrl.text = AmountInputFormatter().formatEditUpdate(const TextEditingValue(), TextEditingValue(text: _toIntStr(e['expected_guests']))).text;
    if (e['budget'] != null) _budgetCtrl.text = AmountInputFormatter().formatEditUpdate(const TextEditingValue(), TextEditingValue(text: _toIntStr(e['budget']))).text;
    final rawType = e['event_type'];
    if (rawType is Map) {
      _eventTypeId = rawType['id']?.toString();
    } else if (rawType is String) {
      _eventTypeId = rawType;
    }
    _eventTypeId ??= e['event_type_id']?.toString();
    _visibility = extractStr(e['visibility'], fallback: 'private');
    _isPublic = e['is_public'] == true;
    _sellsTickets = e['sells_tickets'] == true;
    if (e['start_date'] != null) {
      try {
        _startDate = DateTime.parse(e['start_date'].toString());
        _startTime = TimeOfDay.fromDateTime(_startDate!);
      } catch (_) {}
    }
    if (e['end_date'] != null) {
      try { _endDate = DateTime.parse(e['end_date'].toString()); } catch (_) {}
    }
    final vc = e['venue_coordinates'];
    if (vc is Map) {
      _venueLatitude = double.tryParse(vc['latitude']?.toString() ?? '');
      _venueLongitude = double.tryParse(vc['longitude']?.toString() ?? '');
    }
    _venueAddress = e['venue_address']?.toString();
    final img = e['image_url'] ?? e['image'] ?? e['cover_image'];
    if (img != null && img.toString().isNotEmpty) {
      _existingImageUrl = img.toString();
    }
    // Event owner hydration
    _createdForSomeoneElse = e['created_for_someone_else'] == true;
    _recognizableOwnerNameCtrl.text = extractStr(e['recognizable_event_owner_name']);
    if (_createdForSomeoneElse && e['event_owner_user_id'] != null) {
      _eventOwner = {
        'id': e['event_owner_user_id'].toString(),
        'first_name': extractStr(e['event_owner_first_name']),
        'last_name': extractStr(e['event_owner_last_name']),
        'full_name': extractStr(e['event_owner_full_name']),
        'username': extractStr(e['event_owner_username']),
        'email': extractStr(e['event_owner_email']),
        'phone': extractStr(e['event_owner_phone']),
        'avatar': e['event_owner_avatar'],
      };
    }
  }

  Future<void> _checkAgreement() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final accepted = await AgreementGate.checkAndPrompt(context, 'organiser_agreement');
    if (!accepted && mounted) Navigator.pop(context);
  }

  Future<void> _loadEventTypes() async {
    final res = await EventsService.getEventTypes();
    if (mounted) {
      setState(() {
        _typesLoading = false;
        if (res['success'] == true) {
          final data = res['data'];
          if (data is List) {
            _apiEventTypes = data.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
          }
        }
        if (_apiEventTypes.isEmpty) {
          _apiEventTypes = [
            {'id': 'wedding', 'name': 'Wedding'},
            {'id': 'birthday', 'name': 'Birthday'},
            {'id': 'corporate', 'name': 'Corporate'},
            {'id': 'graduation', 'name': 'Graduation'},
            {'id': 'funeral', 'name': 'Funeral'},
            {'id': 'baby_shower', 'name': 'Baby Shower'},
            {'id': 'anniversary', 'name': 'Anniversary'},
            {'id': 'conference', 'name': 'Conference'},
            {'id': 'other', 'name': 'Other'},
          ];
        }
        _eventTypeId ??= _apiEventTypes.first['id']?.toString();
      });
    }
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(
        initialLatitude: _venueLatitude,
        initialLongitude: _venueLongitude,
      )),
    );
    if (result != null && mounted) {
      setState(() {
        _venueLatitude = result['latitude'] as double?;
        _venueLongitude = result['longitude'] as double?;
        _venueAddress = result['address'] as String?;
        if (_locationCtrl.text.trim().isEmpty && _venueAddress != null) {
          _locationCtrl.text = _venueAddress!;
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;

      // Crop to 16:9 cover ratio for parity with web cover image experience.
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        compressQuality: 88,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop cover image',
            toolbarColor: const Color(0xFF1A1A2E),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.primary,
            backgroundColor: const Color(0xFF1A1A2E),
            dimmedLayerColor: Colors.black54,
            cropFrameColor: AppColors.primary,
            cropGridColor: Colors.white30,
            lockAspectRatio: true,
            hideBottomControls: false,
            showCropGrid: true,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: 'Crop cover image',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            minimumAspectRatio: 16 / 9,
          ),
        ],
      );
      if (cropped == null || !mounted) return;

      final size = await File(cropped.path).length();
      if (size > _maxCoverImageBytes) {
        if (mounted) {
          AppSnackbar.error(context, 'Cover image must be 5MB or smaller');
        }
        return;
      }

      setState(() => _imagePath = cropped.path);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to pick image');
    }
  }

  bool _validateBeforeSave() {
    if ((_eventTypeId ?? '').isEmpty) {
      AppSnackbar.error(context, 'Please select an event type');
      return false;
    }

    if (_startDate == null) {
      AppSnackbar.error(context, 'Please select a start date');
      return false;
    }

    if (_endDate != null && _startDate != null) {
      final startOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      final endOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      if (endOnly.isBefore(startOnly)) {
        AppSnackbar.error(context, 'End date cannot be earlier than start date');
        return false;
      }
    }

    if (_createdForSomeoneElse && (_eventOwner?['id'] == null || _eventOwner!['id'].toString().isEmpty)) {
      AppSnackbar.error(context, 'Please select the actual event owner');
      return false;
    }

    if (_sellsTickets && _ticketClasses.isEmpty) {
      AppSnackbar.error(context, 'Add at least one ticket class or turn off ticketing');
      return false;
    }

    return true;
  }


  // ── Event-owner search & registration ──────────────────────────────
  void _onOwnerSearchChanged(String q) {
    _ownerSearchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { _ownerSearchResults = []; _ownerSearching = false; });
      return;
    }
    setState(() => _ownerSearching = true);
    _ownerSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await EventsService.searchUsers(q.trim());
      if (!mounted) return;
      setState(() {
        _ownerSearching = false;
        if (res['success'] == true) {
          final data = res['data'];
          final rawList = data is List ? data : (data is Map ? (data['items'] ?? data['users'] ?? data['results'] ?? []) : []);
          _ownerSearchResults = (rawList is List ? rawList : []).map((u) {
            if (u is! Map) return <String, dynamic>{};
            final m = Map<String, dynamic>.from(u);
            if ((m['first_name'] == null || m['first_name'] == '') && m['full_name'] != null) {
              final parts = (m['full_name'] as String).split(' ');
              m['first_name'] = parts.first;
              m['last_name'] = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            }
            final avatar = (m['avatar'] ?? m['profile_picture_url'] ?? m['avatar_url'] ?? m['provider_avatar_url'])?.toString() ?? '';
            if (avatar.isNotEmpty) m['avatar'] = avatar;
            return m;
          }).toList().cast<Map<String, dynamic>>();
        } else {
          _ownerSearchResults = [];
        }
      });
    });
  }

  Future<void> _registerMissingOwner() async {
    final first = _newOwnerFirstNameCtrl.text.trim();
    final last = _newOwnerLastNameCtrl.text.trim();
    final phone = _newOwnerPhoneCtrl.text.trim();
    if (first.isEmpty || last.isEmpty || phone.isEmpty) {
      AppSnackbar.error(context, 'Please fill all required fields');
      return;
    }
    setState(() => _registeringOwner = true);
    try {
      // Build a username + signup. Mirrors UserSearchInput on web.
      final uname = ('${first}_${last}_${DateTime.now().millisecondsSinceEpoch}')
          .toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      final res = await AuthApi.signup(
        firstName: first,
        lastName: last,
        username: uname,
        phone: phone,
        password: 'Nuru@2026',
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'] as Map?;
        final id = data?['id']?.toString() ?? data?['user_id']?.toString() ?? '';
        setState(() {
          _eventOwner = {
            'id': id,
            'first_name': first,
            'last_name': last,
            'full_name': '$first $last',
            'username': data?['username']?.toString() ?? uname,
            'email': '',
            'phone': phone,
          };
          _showOwnerRegister = false;
          _ownerSearchCtrl.clear();
          _ownerSearchResults = [];
          _newOwnerFirstNameCtrl.clear();
          _newOwnerLastNameCtrl.clear();
          _newOwnerPhoneCtrl.clear();
        });
        AppSnackbar.success(context, 'Owner registered. Account-setup link sent.');
      } else {
        AppSnackbar.error(context, res['message']?.toString() ?? 'Registration failed');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Registration failed');
    } finally {
      if (mounted) setState(() => _registeringOwner = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _venueCtrl.dispose();
    _expectedGuestsCtrl.dispose();
    _budgetCtrl.dispose();
    _dressCodeCtrl.dispose();
    _specialInstructionsCtrl.dispose();
    _guestOfHonorCtrl.dispose();
    _reminderContactPhoneCtrl.dispose();
    _contributionPaymentInstructionsCtrl.dispose();
    _whatToExpectNotesCtrl.dispose();
    _vendorSearchCtrl.dispose();
    _recognizableOwnerNameCtrl.dispose();
    _ownerSearchCtrl.dispose();
    _newOwnerFirstNameCtrl.dispose();
    _newOwnerLastNameCtrl.dispose();
    _newOwnerPhoneCtrl.dispose();
    _ownerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _save({bool asDraft = false}) async {
    if (!asDraft) {
      if (!_formKey.currentState!.validate()) return;
      if (!_validateBeforeSave()) return;
    }
    setState(() => _saving = true);

    final expectedGuests = int.tryParse(_expectedGuestsCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final budget = double.tryParse(_budgetCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));

    String? startDateStr;
    if (_startDate != null) {
      if (_startTime != null) {
        final combined = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, _startTime!.hour, _startTime!.minute);
        startDateStr = combined.toIso8601String();
      } else {
        startDateStr = _startDate!.toIso8601String();
      }
    }

    String? timeStr;
    if (_startTime != null) {
      timeStr = '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
    }

    Map<String, dynamic> res;
    if (_isEdit) {
      res = await EventsService.updateEvent(
        widget.editEvent!['id'].toString(),
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        eventTypeId: _eventTypeId,
        location: _locationCtrl.text.trim(),
        venue: _venueCtrl.text.trim(),
        visibility: _visibility,
        startDate: startDateStr,
        endDate: _endDate?.toIso8601String(),
        expectedGuests: expectedGuests,
        budget: budget,
        sellsTickets: _sellsTickets,
        isPublic: _isPublic,
        // Legacy fields are explicitly cleared whenever the user touches
        // extra_details so we never double-render old values.
        dressCode: '',
        specialInstructions: '',
        reminderContactPhone: _reminderContactPhoneCtrl.text.trim().isEmpty ? null : _reminderContactPhoneCtrl.text.trim(),
        contributionPaymentInstructions: _contributionPaymentInstructionsCtrl.text.trim(),
        whatToExpect: _wtePayload(),
        whatToExpectNotes: _whatToExpectNotesCtrl.text.trim(),
        extraDetails: _extraDetailsPayload() ?? const [],
        guestOfHonor: _guestOfHonorCtrl.text.trim(),
        time: timeStr,
        imagePath: _imagePath,
        venueLatitude: _venueLatitude,
        venueLongitude: _venueLongitude,
        venueAddress: _venueAddress,
        createdForSomeoneElse: _createdForSomeoneElse,
        eventOwnerUserId: _createdForSomeoneElse ? (_eventOwner?['id']?.toString() ?? '') : '',
        recognizableEventOwnerName: _createdForSomeoneElse ? _recognizableOwnerNameCtrl.text.trim() : '',
      );
    } else {
      String? ownerUserIdArg;
      String? ownerNameArg;
      if (_createdForSomeoneElse) {
        final ownerId = _eventOwner?['id'];
        ownerUserIdArg = ownerId?.toString();
        final trimmedName = _recognizableOwnerNameCtrl.text.trim();
        if (trimmedName.isNotEmpty) {
          ownerNameArg = trimmedName;
        }
      }
      res = await EventsService.createEvent(
        title: _titleCtrl.text.trim(),
        eventType: _eventTypeId ?? 'other',
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        venue: _venueCtrl.text.trim().isEmpty ? null : _venueCtrl.text.trim(),
        visibility: _visibility,
        startDate: startDateStr,
        endDate: _endDate?.toIso8601String(),
        expectedGuests: expectedGuests,
        budget: budget,
        sellsTickets: _sellsTickets,
        isPublic: _isPublic,
        dressCode: null,
        specialInstructions: null,
        reminderContactPhone: _reminderContactPhoneCtrl.text.trim().isEmpty ? null : _reminderContactPhoneCtrl.text.trim(),
        contributionPaymentInstructions: _contributionPaymentInstructionsCtrl.text.trim().isEmpty ? null : _contributionPaymentInstructionsCtrl.text.trim(),
        whatToExpect: _wtePayload(),
        whatToExpectNotes: _whatToExpectNotesCtrl.text.trim().isEmpty ? null : _whatToExpectNotesCtrl.text.trim(),
        extraDetails: _extraDetailsPayload(),
        guestOfHonor: _guestOfHonorCtrl.text.trim().isEmpty ? null : _guestOfHonorCtrl.text.trim(),
        time: timeStr,
        imagePath: _imagePath,
        venueLatitude: _venueLatitude,
        venueLongitude: _venueLongitude,
        venueAddress: _venueAddress,
        status: asDraft ? 'draft' : 'published',
        createdForSomeoneElse: _createdForSomeoneElse,
        eventOwnerUserId: ownerUserIdArg,
        recognizableEventOwnerName: ownerNameArg,
      );
    }

    setState(() => _saving = false);
    if (mounted) {
      if (res['success'] == true) {
        final createdId = res['data']?['id']?.toString();
        if (_sellsTickets && createdId != null && _ticketClasses.isNotEmpty) {
          await _syncTicketClasses(createdId);
        }
        if (createdId != null && _selectedVendors.isNotEmpty && !_isEdit) {
          await _assignSelectedVendors(createdId);
        }
        if (createdId != null && _sponsorVendorIds.isNotEmpty) {
          await _inviteSelectedSponsors(createdId);
        }
        AppSnackbar.success(context, asDraft ? 'Draft saved' : (_isEdit ? 'Event updated' : 'Event created'));
        if (asDraft) {
          Navigator.pop(context, true);
        } else if (!_isEdit && res['data'] != null) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: createdId!, initialData: res['data'], knownRole: 'creator'),
          ));
        } else {
          Navigator.pop(context, true);
        }
      } else {
        AppSnackbar.error(context, res['message'] ?? 'Something went wrong. Please try again.');
      }
    }
  }

  Future<void> _syncTicketClasses(String eventId) async {
    for (final tc in _ticketClasses) {
      try {
        if (tc.id != null) {
          await TicketingService.updateTicketClass(tc.id!, tc.toJson());
        } else {
          await TicketingService.createTicketClass(eventId, tc.toJson());
        }
      } catch (_) {}
    }
  }

  Future<void> _assignSelectedVendors(String eventId) async {
    for (final v in _selectedVendors) {
      try {
        final providerUserId = v['provider']?['id']?.toString()
            ?? v['provider_user_id']?.toString()
            ?? v['user_id']?.toString();
        final payload = <String, dynamic>{
          'provider_service_id': v['id']?.toString(),
          if (providerUserId != null) 'provider_user_id': providerUserId,
          if (v['min_price'] != null) 'quoted_price': v['min_price'],
        };
        await EventsService.addEventService(eventId, payload);
      } catch (_) {}
    }
  }

  Timer? _vendorDebounce;
  bool _vendorsAutoLoaded = false;

  Future<void> _runVendorSearch({String? query}) async {
    final q = (query ?? _vendorSearchCtrl.text).trim();
    setState(() => _vendorSearching = true);
    final res = q.length >= 2
        ? await EventsService.searchServicesPublic(q, eventTypeId: _eventTypeId)
        : await EventsService.getServices(limit: 12, category: _eventTypeId);
    if (!mounted) return;
    setState(() {
      _vendorSearching = false;
      if (res['success'] == true) {
        final data = res['data'];
        final list = data is List ? data : (data is Map ? (data['services'] ?? data['items'] ?? []) : []);
        _vendorResults = List<Map<String, dynamic>>.from(list as List);
      } else {
        _vendorResults = [];
      }
    });
  }

  void _onVendorSearchChanged(String q) {
    _vendorDebounce?.cancel();
    _vendorDebounce = Timer(const Duration(milliseconds: 350), () => _runVendorSearch(query: q));
  }

  void _maybeAutoLoadVendors() {
    if (_vendorsAutoLoaded) return;
    _vendorsAutoLoaded = true;
    _runVendorSearch();
  }

  void _toggleVendor(Map<String, dynamic> v) {
    final id = v['id']?.toString();
    if (id == null) return;
    setState(() {
      final idx = _selectedVendors.indexWhere((s) => s['id']?.toString() == id);
      if (idx >= 0) {
        _selectedVendors.removeAt(idx);
        _sponsorVendorIds.remove(id);
      } else {
        _selectedVendors.add(v);
      }
    });
  }

  Future<void> _inviteSelectedSponsors(String eventId) async {
    for (final id in _sponsorVendorIds) {
      try {
        await EventsService.inviteSponsor(eventId, {'user_service_id': id});
      } catch (_) {/* silent - surfaced from the sponsors tab later */}
    }
  }

  String? _vendorImage(Map<String, dynamic> m) {
    for (final k in ['image', 'primary_image', 'cover_image', 'image_url']) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map) {
        final u = v['thumbnail_url'] ?? v['url'];
        if (u is String && u.isNotEmpty) return u;
      }
    }
    for (final k in ['images', 'gallery_images']) {
      if (m[k] is List && (m[k] as List).isNotEmpty) {
        final f = (m[k] as List).first;
        if (f is String && f.isNotEmpty) return f;
        if (f is Map) {
          final u = f['url'] ?? f['image_url'] ?? f['thumbnail_url'];
          if (u is String && u.isNotEmpty) return u;
        }
      }
    }
    return null;
  }

  Widget _buildVendorsStep() {
    final showResults = _vendorResults.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Find vendors', style: appText(size: 15, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Search caterers, photographers, decor and more. Selected vendors will be notified to confirm.',
          style: appText(size: 11.5, color: AppColors.textTertiary, height: 1.4)),
        const SizedBox(height: 14),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFEDEDEF), width: 1),
          ),
          child: Row(children: [
            SvgPicture.asset('assets/icons/search-icon.svg', width: 18, height: 18,
                colorFilter: const ColorFilter.mode(Color(0xFF8E8E93), BlendMode.srcIn)),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _vendorSearchCtrl,
                onChanged: _onVendorSearchChanged,
                autocorrect: false,
                cursorColor: Colors.black,
                textAlignVertical: TextAlignVertical.center,
                style: appText(size: 14),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Search vendors by name or service',
                  hintStyle: appText(size: 14, color: const Color(0xFF9E9E9E)),
                ),
              ),
            ),
            if (_vendorSearching)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            else if (_vendorSearchCtrl.text.isNotEmpty)
              GestureDetector(
                onTap: () { _vendorSearchCtrl.clear(); _runVendorSearch(); },
                child: SvgPicture.asset('assets/icons/close-icon.svg', width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(Color(0xFF8E8E93), BlendMode.srcIn)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        if (_vendorSearching && _vendorResults.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
          )
        else if (showResults)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _vendorResults.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (_, i) => _vendorGridTile(_vendorResults[i]),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _vendorSearchCtrl.text.trim().isEmpty
                  ? 'No vendors available right now. Try a search above.'
                  : 'No vendors match your search.',
              style: appText(size: 12, color: AppColors.textTertiary),
            ),
          ),
      ])),
      const SizedBox(height: 14),
      if (_selectedVendors.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Selected (${_selectedVendors.length})',
            style: appText(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4),
          ),
        ),
        ..._selectedVendors.map((v) => _selectedVendorTile(v)),
      ] else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Text(
            'You can skip this step and add vendors anytime from the event.',
            style: appText(size: 12, color: AppColors.textTertiary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
    ]);
  }

  Widget _vendorGridTile(Map<String, dynamic> v) {
    final id = v['id']?.toString() ?? '';
    final selected = _selectedVendors.any((s) => s['id']?.toString() == id);
    final title = (v['title'] ?? v['name'] ?? 'Service').toString();
    final category = (v['service_type_name'] ?? v['service_category']?['name'] ?? v['category'] ?? '').toString();
    final price = v['min_price'];
    final rating = v['rating'];
    final image = _vendorImage(v);

    final outerRadius = 14.0;
    final borderWidth = selected ? 1.5 : 1.0;
    final innerRadius = outerRadius - borderWidth;
    return GestureDetector(
      onTap: () => _toggleVendor(v),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(outerRadius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: borderWidth,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(innerRadius),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1.4,
              child: Stack(children: [
                Positioned.fill(
                  child: image != null
                      ? Image.network(image, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceVariant))
                      : Container(color: AppColors.surfaceVariant),
                ),
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? AppColors.primary : AppColors.borderLight, width: 1.2),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        selected ? 'assets/icons/check-icon.svg' : 'assets/icons/plus-icon.svg',
                        width: 12, height: 12,
                        colorFilter: ColorFilter.mode(
                          selected ? Colors.white : AppColors.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: appText(size: 12.5, weight: FontWeight.w700, height: 1.25)),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(category, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: appText(size: 10, color: AppColors.textTertiary)),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  if (rating != null) ...[
                    SvgPicture.asset('assets/icons/star-icon.svg', width: 11, height: 11,
                        colorFilter: const ColorFilter.mode(Color(0xFFE8A33D), BlendMode.srcIn)),
                    const SizedBox(width: 2),
                    Text(double.tryParse(rating.toString())?.toStringAsFixed(1) ?? '$rating',
                      style: appText(size: 10, weight: FontWeight.w700)),
                  ],
                ]),
                if (price != null) ...[
                  const SizedBox(height: 4),
                  Text('From ${getActiveCurrency()} ${_formatNum(price)}',
                    style: appText(size: 11.5, weight: FontWeight.w800, color: AppColors.primary)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _selectedVendorTile(Map<String, dynamic> v) {
    final id = v['id']?.toString() ?? '';
    final title = (v['title'] ?? v['name'] ?? 'Service').toString();
    final providerName = (v['provider']?['name'] ?? v['provider_name'] ?? '').toString();
    final img = _vendorImage(v);
    final isSponsor = _sponsorVendorIds.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSponsor ? const Color(0xFFE8A33D) : AppColors.border,
          width: isSponsor ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52, height: 52,
              child: img != null
                  ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceVariant))
                  : Container(color: AppColors.surfaceVariant,
                      child: Center(child: SvgPicture.asset('assets/icons/image-icon.svg', width: 18, height: 18,
                          colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: appText(size: 13, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (providerName.isNotEmpty)
              Text(providerName, style: appText(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              isSponsor
                  ? 'Will be invited as a sponsor for this event'
                  : 'Will be notified to confirm booking',
              style: appText(
                size: 10,
                color: isSponsor ? const Color(0xFFB8791E) : AppColors.primary,
                weight: FontWeight.w600,
              ),
            ),
          ])),
          IconButton(
            icon: SvgPicture.asset('assets/icons/close-icon.svg', width: 16, height: 16,
                colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
            onPressed: () => _toggleVendor(v),
          ),
        ]),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (id.isEmpty) return;
            setState(() {
              if (isSponsor) {
                _sponsorVendorIds.remove(id);
              } else {
                _sponsorVendorIds.add(id);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSponsor
                  ? const Color(0xFFFFF6E5)
                  : AppColors.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSponsor ? const Color(0xFFE8A33D) : AppColors.borderLight,
              ),
            ),
            child: Row(children: [
              SvgPicture.asset(
                'assets/icons/star-icon.svg',
                width: 14, height: 14,
                colorFilter: ColorFilter.mode(
                  isSponsor ? const Color(0xFFE8A33D) : AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSponsor ? 'Sponsor invite · will be sent after saving' : 'Invite as a sponsor',
                  style: appText(
                    size: 12,
                    weight: FontWeight.w700,
                    color: isSponsor ? const Color(0xFFB8791E) : AppColors.textSecondary,
                  ),
                ),
              ),
              SvgPicture.asset(
                isSponsor ? 'assets/icons/check-icon.svg' : 'assets/icons/plus-icon.svg',
                width: 14, height: 14,
                colorFilter: ColorFilter.mode(
                  isSponsor ? const Color(0xFFE8A33D) : AppColors.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _formatNum(dynamic n) {
    final num val = n is num ? n : (num.tryParse(n.toString()) ?? 0);
    return val.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildStepper(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_stepHeadings[_step][0],
                          style: appText(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(_stepHeadings[_step][1],
                          style: appText(size: 13, color: AppColors.textSecondary)),
                      ]),
                    ),
                    _buildStepContent(),
                  ]),
                ),
              ),
            ),
            _buildStepNav(),
          ]),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return Column(children: [
          _buildEventDetailsCard(),
          const SizedBox(height: 16),
          _buildEventOwnerCard(),
          const SizedBox(height: 16),
          _buildCoverImageCard(),
          const SizedBox(height: 16),
          _buildVisibilityCard(),
        ]);
      case 1:
        return Column(children: [
          _buildDateTimeCard(),
          const SizedBox(height: 16),
          _buildGuestsBudgetCard(),
          const SizedBox(height: 16),
          _venueOnlyCard(),
          const SizedBox(height: 16),
          _buildOptionalDetailsCard(),
        ]);
      case 2:
        return Column(children: [
          EventTicketingCard(
            sellsTickets: _sellsTickets,
            onSellsTicketsChanged: (v) => setState(() => _sellsTickets = v),
            isPublic: _isPublic,
            onIsPublicChanged: (v) => setState(() => _isPublic = v),
            ticketClasses: _ticketClasses,
            onTicketClassesChanged: (v) => setState(() => _ticketClasses = v),
          ),
          // Service recommendations & invitation card picker moved out of
          // create flow - they live on the event detail screen after the
          // event is saved.
        ]);
      case 3:
        return _buildVendorsStep();
      case 4:
      default:
        return _buildPreviewCard();
    }
  }

  Widget _venueOnlyCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('event_location')),
      _input(_locationCtrl, context.tr('event_venue_address')),
      const SizedBox(height: 6),
      Text(
        'Optional. You can add or change the venue later.',
        style: appText(size: 11, color: AppColors.textTertiary),
      ),
      const SizedBox(height: 12),
      _buildMapPickerButton(),
      const SizedBox(height: 16),
      _label(context.tr('venue_name')),
      _input(_venueCtrl, context.tr('venue_name_optional')),
    ]));
  }

  Widget _buildStepper() {
    const shortTitles = ['Basic', 'When', 'Tickets', 'Vendors', 'Preview'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: List.generate(_stepTitles.length * 2 - 1, (i) {
        if (i.isOdd) {
          final past = (i ~/ 2) < _step;
          return Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: past ? AppColors.primary : AppColors.border, borderRadius: BorderRadius.circular(2))),
          ));
        }
        final idx = i ~/ 2;
        final active = idx == _step;
        final done = idx < _step;
        return GestureDetector(
          onTap: () { if (idx < _step) setState(() => _step = idx); },
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active || done ? AppColors.primary : Colors.white,
                border: Border.all(color: active || done ? AppColors.primary : AppColors.border, width: 1.5),
              ),
              alignment: Alignment.center,
              child: done
                  ? SvgPicture.asset('assets/icons/check-icon.svg', width: 14, height: 14,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))
                  : Text('${idx + 1}', style: appText(size: 12, weight: FontWeight.w700, color: active ? Colors.white : AppColors.textTertiary)),
            ),
            const SizedBox(height: 6),
            Text(shortTitles[idx], style: appText(size: 11, weight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.textPrimary : AppColors.textTertiary)),
          ]),
        );
      })),
    );
  }

  Widget _buildStepNav() {
    final isLast = _step == _stepTitles.length - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(children: [
          if (_step > 0) ...[
            SizedBox(
              height: 52, width: 52,
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _step -= 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (isLast) { _save(); return; }
                        if (!_validateStep(_step)) return;
                        setState(() => _step += 1);
                        if (_step == 3) _maybeAutoLoadVendors();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(isLast ? (_isEdit ? context.tr('save_changes') : context.tr('create_event')) : 'Next',
                              style: appText(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(width: 8),
                          SvgPicture.asset('assets/icons/arrow-right-icon.svg', width: 18, height: 18,
                            colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
                        ],
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if ((_eventTypeId ?? '').isEmpty) { AppSnackbar.error(context, 'Please select an event type'); return false; }
        if (_titleCtrl.text.trim().isEmpty) { AppSnackbar.error(context, 'Event title is required'); return false; }
        return true;
      case 1:
        if (_startDate == null) { AppSnackbar.error(context, 'Please select a start date'); return false; }
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          AppSnackbar.error(context, 'End date cannot be earlier than start date'); return false;
        }
        return true;
      case 2:
        if (_sellsTickets && _ticketClasses.isEmpty) {
          AppSnackbar.error(context, 'Add at least one ticket class or turn off ticketing');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  Widget _buildPreviewCard() {
    final typeName = _apiEventTypes
        .firstWhere((t) => t['id']?.toString() == _eventTypeId, orElse: () => <String, dynamic>{})['name']
        ?.toString() ?? '';
    String startLine = _startDate == null ? 'No date set' : _formatDate(_startDate!);
    if (_startTime != null) {
      startLine += ' • ${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
    }
    final endLine = _endDate == null ? null : _formatDate(_endDate!);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_imagePath != null)
            Image.file(File(_imagePath!), height: 200, width: double.infinity, fit: BoxFit.cover)
          else if (_existingImageUrl != null)
            Image.network(_existingImageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 160, color: AppColors.surfaceVariant))
          else
            Container(
              height: 160, width: double.infinity,
              color: AppColors.surfaceVariant,
              child: Center(
                child: SvgPicture.asset('assets/icons/image-icon.svg', width: 36, height: 36,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (typeName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(typeName, style: appText(size: 11, weight: FontWeight.w700, color: AppColors.primary)),
                ),
              const SizedBox(height: 10),
              Text(_titleCtrl.text.trim().isEmpty ? 'Untitled event' : _titleCtrl.text.trim(),
                  style: appText(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary)),
              if (_descCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_descCtrl.text.trim(), style: appText(size: 14, color: AppColors.textSecondary, height: 1.5)),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _previewSection('When', [
        _previewRow('assets/icons/calendar-icon.svg', 'Starts: $startLine'),
        if (endLine != null) _previewRow('assets/icons/calendar-icon.svg', 'Ends: $endLine'),
      ]),
      _previewSection('Where', [
        if (_venueCtrl.text.trim().isNotEmpty)
          _previewRow('assets/icons/home-icon.svg', _venueCtrl.text.trim()),
        if (_locationCtrl.text.trim().isNotEmpty)
          _previewRow('assets/icons/location-icon.svg', _locationCtrl.text.trim()),
        if (_venueAddress != null && _venueAddress!.trim().isNotEmpty)
          _previewRow('assets/icons/location-icon.svg', _venueAddress!.trim()),
        if (_venueLatitude != null && _venueLongitude != null)
          _previewRow('assets/icons/location-icon.svg',
              'Pinned at ${_venueLatitude!.toStringAsFixed(5)}, ${_venueLongitude!.toStringAsFixed(5)}'),
      ]),
      _previewSection('Planning', [
        if (_expectedGuestsCtrl.text.trim().isNotEmpty)
          _previewItem(
            icon: 'assets/icons/user-icon.svg',
            label: 'Expected guests',
            value: _expectedGuestsCtrl.text.trim(),
          ),
        if (_budgetCtrl.text.trim().isNotEmpty)
          _previewItem(
            icon: 'assets/icons/card-icon.svg',
            label: 'Budget',
            value: formatMoney(num.tryParse(
                    _budgetCtrl.text.replaceAll(RegExp(r"[^0-9.]"), "")) ??
                0),
          ),
        if (_guestOfHonorCtrl.text.trim().isNotEmpty)
          _previewItem(
            icon: 'assets/icons/user-icon.svg',
            label: 'Guest of honor',
            value: _guestOfHonorCtrl.text.trim(),
          ),
        if (_reminderContactPhoneCtrl.text.trim().isNotEmpty)
          _previewItem(
            icon: 'assets/icons/phone-icon.svg',
            label: 'Reminder contact',
            value: _reminderContactPhoneCtrl.text.trim(),
          ),
      ]),
      // Additional info lives in its own clearly-labelled section so the
      // Planning block stays focused on the core logistics.
      if (_extraDetailsItems.any((m) =>
          (m['label'] ?? '').trim().isNotEmpty &&
          (m['details'] ?? '').trim().isNotEmpty))
        _previewSection('Additional info', [
          ..._extraDetailsItems
              .where((m) =>
                  (m['label'] ?? '').trim().isNotEmpty &&
                  (m['details'] ?? '').trim().isNotEmpty)
              .map((m) => _previewItem(
                    icon: 'assets/icons/info-icon.svg',
                    label: m['label']!.trim(),
                    value: m['details']!.trim(),
                  )),
        ]),
      _previewSection('Visibility & Tickets', [
        _previewRow(_visibility == 'public' ? 'assets/icons/view-icon.svg' : 'assets/icons/shield-icon.svg',
            _visibility == 'public' ? 'Public event (discoverable)' : 'Private event (invitees only)'),
        _previewRow('assets/icons/ticket-icon.svg',
            _sellsTickets
                ? '${_ticketClasses.length} ticket class${_ticketClasses.length == 1 ? '' : 'es'} on sale'
                : 'Not selling tickets'),
        if (_sellsTickets && _ticketClasses.isNotEmpty)
          ..._ticketClasses.map((tc) {
            final price = tc.price;
            final qty = tc.quantity;
            final parts = <String>[];
            if (price > 0) parts.add('${getActiveCurrency()} ${formatMoney(price)}');
            if (qty > 0) parts.add('$qty seats');
            final sub = parts.isEmpty ? '' : '  •  ${parts.join('  •  ')}';
            return Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 6),
              child: Text('${tc.name}$sub',
                  style: appText(size: 13, color: AppColors.textSecondary, height: 1.4)),
            );
          }),
      ]),
      if (_whatToExpectItems.any((m) => (m['label'] ?? '').trim().isNotEmpty) ||
          _whatToExpectNotesCtrl.text.trim().isNotEmpty)
        _previewSection('What to expect', [
          ..._whatToExpectItems
              .where((m) => (m['label'] ?? '').trim().isNotEmpty)
              .map((m) {
            final label = m['label']!.trim();
            final desc = (m['description'] ?? '').trim();
            return _previewRow('assets/icons/sparkles-icon.svg',
                desc.isEmpty ? label : '$label: $desc');
          }),
          if (_whatToExpectNotesCtrl.text.trim().isNotEmpty)
            _previewRow('assets/icons/info-icon.svg', _whatToExpectNotesCtrl.text.trim()),
        ]),
      if (_selectedVendors.isNotEmpty)
        _previewSection('Vendors (${_selectedVendors.length})',
          _selectedVendors.map((v) {
            final name = (v['name'] ?? v['business_name'] ?? v['title'] ?? '').toString();
            final cat = (v['category'] ?? v['service_type'] ?? '').toString();
            return _previewRow('assets/icons/package-icon.svg',
                cat.isEmpty ? name : '$name  •  $cat');
          }).toList(),
        ),
    ]);
  }

  Widget _previewSection(String title, List<Widget> rows) {
    final visible = rows.where((w) => w is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Text(title.toUpperCase(),
              style: appText(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 1.0,
              )),
        ),
        // Render rows with a thin divider between them for a clean list feel.
        for (int i = 0; i < visible.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.borderLight,
              indent: 60,
              endIndent: 16,
            ),
          visible[i],
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  /// Polished list row with a tinted icon chip + label/value pair.
  Widget _previewItem({
    required String icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(icon,
              width: 16,
              height: 16,
              colorFilter:
                  const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: appText(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.2)),
              const SizedBox(height: 2),
              Text(value,
                  style: appText(
                      size: 14.5,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.35)),
            ],
          ),
        ),
      ]),
    );
  }

  /// Compact single-line row (used by sections that pass text only).
  Widget _previewRow(String iconAsset, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(iconAsset,
              width: 16,
              height: 16,
              colorFilter:
                  const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: appText(
                  size: 14.5,
                  weight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  height: 1.4)),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: SvgPicture.asset('assets/icons/arrow-left-icon.svg', width: 22, height: 22,
              colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn)),
          ),
        ),
        Expanded(child: Center(
          child: Text(
            _isEdit ? context.tr('edit_event') : context.tr('create_event'),
            style: appText(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        )),
        GestureDetector(
          onTap: _saving ? null : (_isEdit ? _saveStep : _saveDraft),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              _isEdit ? 'Save' : 'Save Draft',
              style: appText(size: 14, weight: FontWeight.w600, color: AppColors.primary),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _saveDraft() async {
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Add a title to save a draft');
      return;
    }
    if ((_eventTypeId ?? '').isEmpty) {
      AppSnackbar.error(context, 'Select an event type to save a draft');
      return;
    }
    await _save(asDraft: true);
  }

  /// Save only the fields belonging to the current step (edit mode).
  /// Validates that step, then PATCHes only those fields.
  Future<void> _saveStep() async {
    if (!_validateStep(_step)) return;
    final eventId = widget.editEvent?['id']?.toString();
    if (eventId == null) return;

    setState(() => _saving = true);
    Map<String, dynamic> res = {'success': true};

    try {
      switch (_step) {
        case 0: // Basic info
          res = await EventsService.updateEvent(
            eventId,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            eventTypeId: _eventTypeId,
          );
          break;
        case 1: // When & Where (date/time + venue)
          String? startDateStr;
          if (_startDate != null) {
            final d = _startDate!;
            final t = _startTime;
            final combined = t == null
                ? DateTime(d.year, d.month, d.day)
                : DateTime(d.year, d.month, d.day, t.hour, t.minute);
            startDateStr = combined.toIso8601String();
          }
          final timeStr = _startTime == null
              ? null
              : '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
          res = await EventsService.updateEvent(
            eventId,
            startDate: startDateStr,
            endDate: _endDate?.toIso8601String(),
            time: timeStr,
            location: _locationCtrl.text.trim(),
            venue: _venueCtrl.text.trim(),
            venueLatitude: _venueLatitude,
            venueLongitude: _venueLongitude,
            venueAddress: _venueAddress,
          );
          break;
        case 2: // Tickets & visibility
          res = await EventsService.updateEvent(
            eventId,
            visibility: _visibility,
            sellsTickets: _sellsTickets,
            isPublic: _isPublic,
          );
          if (res['success'] == true && _sellsTickets && _ticketClasses.isNotEmpty) {
            await _syncTicketClasses(eventId);
          }
          break;
        case 3: // Vendors - assigning vendors during edit isn't part of PATCH;
                // delegated to the dedicated vendor flows. No-op here.
          res = {'success': true};
          break;
        case 4: // Preview - fall back to full save
          await _save();
          setState(() => _saving = false);
          return;
        default:
          res = {'success': true};
      }

      // Always include extras / image / guests / budget if they belong to the
      // currently visible step. (Expected guests/budget live on step 0 via the
      // dynamic builder - fold them in for completeness.)
      if (_step == 0) {
        final expectedGuests = int.tryParse(_expectedGuestsCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
        final budget = double.tryParse(_budgetCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (expectedGuests != null || budget != null || _imagePath != null) {
          await EventsService.updateEvent(
            eventId,
            expectedGuests: expectedGuests,
            budget: budget,
            imagePath: _imagePath,
            dressCode: '',
            specialInstructions: '',
            reminderContactPhone: _reminderContactPhoneCtrl.text.trim().isEmpty ? null : _reminderContactPhoneCtrl.text.trim(),
            contributionPaymentInstructions: _contributionPaymentInstructionsCtrl.text.trim(),
            whatToExpect: _wtePayload(),
            whatToExpectNotes: _whatToExpectNotesCtrl.text.trim(),
            extraDetails: _extraDetailsPayload() ?? const [],
            guestOfHonor: _guestOfHonorCtrl.text.trim(),
          );
        }
      }
    } catch (_) {
      res = {'success': false, 'message': 'Unable to save changes'};
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      AppSnackbar.success(context, 'Saved');
    } else {
      AppSnackbar.error(context, res['message']?.toString() ?? 'Could not save');
    }
  }

  Widget _buildEventDetailsCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('event_type')),
      _typesLoading
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
          : _eventTypeGrid(),
      const SizedBox(height: 16),
      _label(context.tr('event_title')),
      _input(_titleCtrl, context.tr('give_event_name'), validator: (v) => v == null || v.isEmpty ? context.tr('required_field') : v.length > 100 ? 'Max 100' : null),
      const SizedBox(height: 16),
      _label(context.tr('description')),
      _input(_descCtrl, context.tr('describe_event'), maxLines: 4),
      const SizedBox(height: 16),
      _label('Guest of honor (optional)'),
      _input(_guestOfHonorCtrl, 'e.g. Hon. Jane Mwangi, Bishop Yusuf, Mr. & Mrs. Juma'),
      const SizedBox(height: 4),
      Text(
        'Shown on the public event page when filled.',
        style: appText(size: 11, color: AppColors.textTertiary),
      ),
    ]));
  }

  Widget _buildEventOwnerCard() {
    final highlight = _createdForSomeoneElse;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primarySoft : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? AppColors.primary.withOpacity(0.55) : AppColors.border.withOpacity(0.5),
          width: highlight ? 1.2 : 0.7,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('I am creating this event for someone else',
              style: appText(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Notifications and invitations will show the real event owner.',
              style: appText(size: 11.5, color: AppColors.textTertiary, height: 1.4)),
        ])),
        Switch.adaptive(
          value: _createdForSomeoneElse,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() {
            _createdForSomeoneElse = v;
            if (!v) {
              _eventOwner = null;
              _recognizableOwnerNameCtrl.clear();
              _ownerSearchCtrl.clear();
              _ownerSearchResults = [];
              _showOwnerRegister = false;
            }
          }),
        ),
      ]),
      if (_createdForSomeoneElse) ...[
        const SizedBox(height: 14),
        _label('Event owner'),
        if (_eventOwner != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              CircleAvatar(
                radius: 18, backgroundColor: AppColors.primary,
                backgroundImage: (_eventOwner!['avatar'] != null && _eventOwner!['avatar'].toString().isNotEmpty)
                    ? CachedNetworkImageProvider(_eventOwner!['avatar'].toString()) : null,
                child: (_eventOwner!['avatar'] == null || _eventOwner!['avatar'].toString().isEmpty)
                    ? Text(((_eventOwner!['first_name'] ?? 'U').toString().isEmpty ? 'U' : (_eventOwner!['first_name'] as String)[0]).toUpperCase(),
                        style: appText(size: 14, weight: FontWeight.w700, color: Colors.white))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  (_eventOwner!['full_name']?.toString().isNotEmpty == true
                      ? _eventOwner!['full_name']
                      : '${_eventOwner!['first_name'] ?? ''} ${_eventOwner!['last_name'] ?? ''}').toString().trim(),
                  style: appText(size: 14, weight: FontWeight.w600),
                ),
                if ((_eventOwner!['phone'] ?? '').toString().isNotEmpty)
                  Text(_eventOwner!['phone'].toString(), style: appText(size: 11, color: AppColors.textTertiary)),
              ])),
              GestureDetector(
                onTap: () => setState(() { _eventOwner = null; }),
                child: Text('Change', style: appText(size: 12, weight: FontWeight.w600, color: AppColors.primary)),
              ),
            ]),
          )
        else ...[
          TextField(
            controller: _ownerSearchCtrl,
            onChanged: _onOwnerSearchChanged,
            autocorrect: false,
            style: appText(size: 14),
            decoration: InputDecoration(
              hintText: 'Search by name, email or phone…',
              hintStyle: appText(size: 13, color: AppColors.textHint),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: SvgPicture.asset('assets/icons/search-icon.svg', width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(AppColors.textHint, BlendMode.srcIn)),
              ),
              suffixIcon: _ownerSearching
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                  : null,
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          if (_ownerSearchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _ownerSearchResults.length,
                itemBuilder: (_, i) {
                  final u = _ownerSearchResults[i];
                  final name = (u['full_name'] ?? '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}').toString().trim();
                  final sub = [
                    if ((u['username'] ?? '') != '') '@${u['username']}',
                    if ((u['phone'] ?? '') != '') u['phone'],
                  ].join(' · ');
                  final avatarUrl = (u['avatar'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary,
                      backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text((name.isNotEmpty ? name[0] : 'U').toUpperCase(),
                              style: appText(size: 12, weight: FontWeight.w700, color: Colors.white))
                          : null,
                    ),
                    title: Text(name.isNotEmpty ? name : 'Unknown', style: appText(size: 13, weight: FontWeight.w600)),
                    subtitle: sub.isNotEmpty ? Text(sub, style: appText(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    onTap: () => setState(() {
                      _eventOwner = u;
                      _ownerSearchResults = [];
                      _ownerSearchCtrl.clear();
                    }),
                  );
                },
              ),
            )
          else if (_ownerSearchCtrl.text.trim().length >= 2 && !_ownerSearching && !_showOwnerRegister) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showOwnerRegister = true),
              icon: SvgPicture.asset('assets/icons/user-add-icon.svg', width: 14, height: 14,
                  colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              label: Text('Register new owner', style: appText(size: 13, weight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          if (_showOwnerRegister) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Register new owner', style: appText(size: 13, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _input(_newOwnerFirstNameCtrl, 'First name *')),
                  const SizedBox(width: 8),
                  Expanded(child: _input(_newOwnerLastNameCtrl, 'Last name *')),
                ]),
                const SizedBox(height: 8),
                _input(_newOwnerPhoneCtrl, 'Phone *', keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: ElevatedButton(
                    onPressed: _registeringOwner ? null : _registerMissingOwner,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.textPrimary, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _registeringOwner
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : Text('Register & select', style: appText(size: 13, weight: FontWeight.w700)),
                  )),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _registeringOwner ? null : () => setState(() => _showOwnerRegister = false),
                    child: Text('Cancel', style: appText(size: 13, weight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('We will send an account-setup link by WhatsApp.', style: appText(size: 11, color: AppColors.textTertiary)),
              ]),
            ),
          ],
        ],
        const SizedBox(height: 14),
        _label('Recognizable owner name (optional)'),
        _input(_recognizableOwnerNameCtrl, 'e.g. Mwanaidi & Juma, Familia ya Kibwana'),
        const SizedBox(height: 4),
        Text('Shown in invitations and messages instead of the account name.',
            style: appText(size: 11, color: AppColors.textTertiary)),
      ],
    ]));
  }


  Widget _buildMapPickerButton() {
    return GestureDetector(
      onTap: _openMapPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _venueLatitude != null ? AppColors.primary.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _venueLatitude != null ? AppColors.primary.withOpacity(0.3) : AppColors.border),
        ),
        child: Row(children: [
          SvgPicture.asset('assets/icons/location-icon.svg', width: 18, height: 18,
              colorFilter: ColorFilter.mode(
                _venueLatitude != null ? AppColors.primary : AppColors.textTertiary,
                BlendMode.srcIn,
              )),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _venueLatitude != null ? context.tr('location_pinned') : context.tr('pick_location'),
              style: appText(size: 14, color: _venueLatitude != null ? AppColors.primary : AppColors.textHint, weight: _venueLatitude != null ? FontWeight.w600 : FontWeight.w400),
            ),
            if (_venueAddress != null && _venueAddress!.isNotEmpty)
              Text(_venueAddress!, style: appText(size: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (_venueLatitude != null)
            GestureDetector(
              onTap: () => setState(() { _venueLatitude = null; _venueLongitude = null; _venueAddress = null; }),
              child: SvgPicture.asset('assets/icons/close-icon.svg', width: 14, height: 14,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
            ),
        ]),
      ),
    );
  }

  Widget _buildDateTimeCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('date_and_time')),
      _datePicker(context.tr('start_date'), _startDate, (d) => setState(() => _startDate = d)),
      const SizedBox(height: 12),
      _timePicker(context.tr('start_time'), _startTime, (t) => setState(() => _startTime = t)),
      const SizedBox(height: 12),
      _datePicker(context.tr('end_date_optional'), _endDate, (d) => setState(() => _endDate = d)),
    ]));
  }

  Widget _buildGuestsBudgetCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('expected_guests')),
      _input(_expectedGuestsCtrl, 'e.g., 50', keyboardType: TextInputType.number, inputFormatters: amountFormatters),
      const SizedBox(height: 16),
      _label(context.tr('estimated_budget')),
      _input(_budgetCtrl, 'e.g., 5,000,000', keyboardType: TextInputType.number, inputFormatters: amountFormatters),
    ]));
  }

  Widget _buildCoverImageCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('cover_image')),
      GestureDetector(
        onTap: _pickImage,
        child: (_imagePath != null || _existingImageUrl != null)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(children: [
                  if (_imagePath != null)
                    Image.file(File(_imagePath!), width: double.infinity, height: 180, fit: BoxFit.cover)
                  else
                    Image.network(_existingImageUrl!, width: double.infinity, height: 180, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(height: 180, color: AppColors.surfaceVariant)),
                  Positioned(
                    top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() { _imagePath = null; _existingImageUrl = null; }),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: SvgPicture.asset('assets/icons/close-icon.svg', width: 14, height: 14,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: Text(_imagePath != null ? 'New' : 'Tap to replace',
                        style: appText(size: 11, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ]),
              )
            : CustomPaint(
                painter: _DashedBorderPainter(color: AppColors.primary.withOpacity(0.55), radius: 14, dash: 6, gap: 4, strokeWidth: 1.4),
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.04), borderRadius: BorderRadius.circular(14)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                      child: SvgPicture.asset('assets/icons/image-icon.svg', width: 22, height: 22,
                          colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                    ),
                    const SizedBox(height: 10),
                    Text(context.tr('tap_to_upload'), style: appText(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('PNG, JPG up to 5MB', style: appText(size: 11, color: AppColors.textTertiary)),
                  ]),
                ),
              ),
      ),
    ]));
  }

  Widget _buildVisibilityCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('visibility')),
      Row(children: ['private', 'public'].map((v) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _visibility = v;
            _isPublic = v == 'public';
          }),
          child: Container(
            margin: EdgeInsets.only(right: v == 'private' ? 8 : 0, left: v == 'public' ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _visibility == v ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _visibility == v ? AppColors.primary : AppColors.border, width: _visibility == v ? 1.5 : 1),
            ),
            child: Center(child: Text(
              v[0].toUpperCase() + v.substring(1),
              style: appText(size: 14, weight: _visibility == v ? FontWeight.w700 : FontWeight.w500, color: _visibility == v ? AppColors.primary : AppColors.textSecondary),
            )),
          ),
        ),
      )).toList()),
    ]));
  }

  Widget _buildOptionalDetailsCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context.tr('additional_details')),
      Text(
        'Add any extra rows guests should see · e.g. Dress code · Black tie, Parking · Free at venue, Gifts · Bring envelopes.',
        style: appText(size: 12, color: AppColors.textTertiary, height: 1.4),
      ),
      const SizedBox(height: 14),
      _extraDetailsEditor(),
      const SizedBox(height: 20),
      _label('Reminder contact phone (optional)'),
      _input(_reminderContactPhoneCtrl, 'e.g. +255712345678. Used in reminder messages instead of your number.', keyboardType: TextInputType.phone),
      const SizedBox(height: 16),
      _label('Contributor payment instructions (optional)'),
      _input(_contributionPaymentInstructionsCtrl, 'Explain how contributors should complete their payment. This will be included in contribution target messages.', maxLines: 3),
      const SizedBox(height: 20),
      _whatToExpectSection(),
    ]));
  }

  Widget _extraDetailsEditor() {
    OutlineInputBorder _border([Color? c]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c ?? AppColors.border),
    );

    Widget rowEditor(int i, Map<String, String> item) {
      final label = (item['label'] ?? '').trim();
      final details = (item['details'] ?? '').trim();
      final expanded = _extraExpandedIndex == i || label.isEmpty || details.isEmpty;

      if (!expanded) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('${i + 1}',
                  style: appText(size: 13, weight: FontWeight.w800, color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(size: 14.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(details, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: appText(size: 12.5, color: AppColors.textSecondary, height: 1.35)),
            ])),
            IconButton(
              onPressed: () => setState(() => _extraExpandedIndex = i),
              icon: SvgPicture.asset('assets/icons/pen-icon.svg',
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: () => setState(() {
                _extraDetailsItems.removeAt(i);
                if (_extraExpandedIndex == i) _extraExpandedIndex = null;
              }),
              icon: SvgPicture.asset('assets/icons/close-icon.svg',
                  width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              tooltip: 'Remove',
            ),
          ]),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('${i + 1}',
                  style: appText(size: 13, weight: FontWeight.w800, color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'Row ${i + 1}',
              style: appText(size: 12, weight: FontWeight.w700, color: AppColors.textTertiary),
            )),
            GestureDetector(
              onTap: () => setState(() {
                _extraDetailsItems.removeAt(i);
                if (_extraExpandedIndex == i) _extraExpandedIndex = null;
              }),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: SvgPicture.asset('assets/icons/close-icon.svg',
                    width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('extra_label_$i'),
            initialValue: item['label'],
            onChanged: (v) => item['label'] = v,
            style: appText(size: 15),
            decoration: InputDecoration(
              hintText: 'Label · e.g. Dress code, Parking, Gifts',
              hintStyle: appText(size: 14, color: AppColors.textHint),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('extra_details_$i'),
            initialValue: item['details'],
            onChanged: (v) => item['details'] = v,
            style: appText(size: 14, color: AppColors.textSecondary, height: 1.4),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Details · what guests should know about this row',
              hintStyle: appText(size: 13, color: AppColors.textHint),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: (label.trim().isEmpty || details.trim().isEmpty)
                  ? null
                  : () => setState(() => _extraExpandedIndex = null),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Done'),
            ),
          ]),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ..._extraDetailsItems.asMap().entries.map((e) => rowEditor(e.key, e.value)),
      if (_extraDetailsItems.length < 20)
        GestureDetector(
          onTap: () {
            final emptyIdx = _extraDetailsItems.indexWhere(
              (m) => (m['label'] ?? '').trim().isEmpty || (m['details'] ?? '').trim().isEmpty,
            );
            setState(() {
              if (emptyIdx >= 0) {
                _extraExpandedIndex = emptyIdx;
              } else {
                _extraDetailsItems.add({'label': '', 'details': ''});
                _extraExpandedIndex = _extraDetailsItems.length - 1;
              }
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/icons/plus-icon.svg', width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                const SizedBox(width: 8),
                Text(
                  _extraDetailsItems.isEmpty ? 'Add detail row' : 'Add another row',
                  style: appText(size: 14, weight: FontWeight.w800, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  List<Map<String, dynamic>>? _wtePayload() {
    final out = <Map<String, dynamic>>[];
    for (final it in _whatToExpectItems) {
      final label = (it['label'] ?? '').trim();
      if (label.isEmpty) continue;
      out.add({
        'icon': (it['icon'] ?? 'sparkle').trim(),
        'label': label,
        'description': (it['description'] ?? '').trim(),
      });
    }
    return out.isEmpty ? null : out;
  }

  List<Map<String, dynamic>>? _extraDetailsPayload() {
    final out = <Map<String, dynamic>>[];
    for (final it in _extraDetailsItems) {
      final label = (it['label'] ?? '').trim();
      final details = (it['details'] ?? '').trim();
      if (label.isEmpty || details.isEmpty) continue;
      out.add({'label': label, 'details': details});
    }
    return out.isEmpty ? null : out;
  }

  Widget _whatToExpectSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('What to expect (optional)'),
      Text(
        'Give guests a short preview of highlights. Leave blank to hide this section.',
        style: appText(size: 12, color: AppColors.textTertiary),
      ),
      const SizedBox(height: 14),
      ..._whatToExpectItems.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final iconName = (item['icon'] ?? 'star').toString();
        final isDefaultIcon = iconName == 'star' || iconName == 'sparkle';
        final label = (item['label'] ?? '').trim();
        final desc = (item['description'] ?? '').trim();
        final expanded = _wteExpandedIndex == i || label.isEmpty;

        Widget iconTile({double size = 44, double inner = 20}) => GestureDetector(
          onTap: () => _pickWteIcon(i),
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: isDefaultIcon
                  ? Text('${i + 1}', style: appText(size: 14, weight: FontWeight.w800, color: AppColors.primary))
                  : SvgPicture.asset('assets/icons/$iconName-icon.svg',
                      width: inner, height: inner,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
            ),
          ),
        );

        if (!expanded) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(children: [
              iconTile(size: 38, inner: 18),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: appText(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: appText(size: 12, color: AppColors.textTertiary)),
                ],
              ])),
              IconButton(
                onPressed: () => setState(() => _wteExpandedIndex = i),
                icon: SvgPicture.asset('assets/icons/pen-icon.svg',
                    width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                tooltip: 'Edit',
              ),
              IconButton(
                onPressed: () => setState(() {
                  _whatToExpectItems.removeAt(i);
                  if (_wteExpandedIndex == i) _wteExpandedIndex = null;
                }),
                icon: SvgPicture.asset('assets/icons/close-icon.svg',
                    width: 18, height: 18,
                    colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                tooltip: 'Remove',
              ),
            ]),
          );
        }

        // Expanded editor - flat surface, full-size inputs matching the rest of the form.
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              iconTile(),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Item ${i + 1} · tap icon to change',
                style: appText(size: 12, weight: FontWeight.w700, color: AppColors.textTertiary),
              )),
              GestureDetector(
                onTap: () => setState(() {
                  _whatToExpectItems.removeAt(i);
                  if (_wteExpandedIndex == i) _wteExpandedIndex = null;
                }),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: SvgPicture.asset('assets/icons/close-icon.svg',
                      width: 18, height: 18,
                      colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('wte_label_$i'),
              initialValue: item['label'],
              onChanged: (v) => item['label'] = v,
              style: appText(size: 15),
              decoration: InputDecoration(
                hintText: 'e.g. Live music',
                hintStyle: appText(size: 14, color: AppColors.textHint),
                filled: true, fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('wte_desc_$i'),
              initialValue: item['description'],
              onChanged: (v) => item['description'] = v,
              style: appText(size: 14, color: AppColors.textSecondary, height: 1.4),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Short description (optional)',
                hintStyle: appText(size: 13, color: AppColors.textHint),
                filled: true, fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: label.trim().isEmpty
                    ? null
                    : () => setState(() => _wteExpandedIndex = null),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('Done'),
              ),
            ]),
          ]),
        );
      }),
      if (_whatToExpectItems.length < 12)
        GestureDetector(
          onTap: () {
            // If user has an empty draft already, just focus it.
            final emptyIdx = _whatToExpectItems.indexWhere((m) => (m['label'] ?? '').trim().isEmpty);
            setState(() {
              if (emptyIdx >= 0) {
                _wteExpandedIndex = emptyIdx;
              } else {
                _whatToExpectItems.add({'icon': 'star', 'label': '', 'description': ''});
                _wteExpandedIndex = _whatToExpectItems.length - 1;
              }
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              SvgPicture.asset('assets/icons/plus-icon.svg', width: 18, height: 18,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Text(_whatToExpectItems.isEmpty ? 'Add first item' : 'Add another',
                  style: appText(size: 14, weight: FontWeight.w800, color: AppColors.primary)),
            ]),
          ),
        ),
      const SizedBox(height: 18),
      _label('Notes (optional)'),
      _input(_whatToExpectNotesCtrl, 'Anything else guests should know · schedule notes, parking, dress code, etc.', maxLines: 3),
    ]);
  }



  Future<void> _pickWteIcon(int index) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose an icon', style: appText(size: 16, weight: FontWeight.w800)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: _wteIconChoices.map((name) => GestureDetector(
            onTap: () => Navigator.pop(ctx, name),
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/$name-icon.svg',
                  width: 22, height: 22,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                ),
              ),
            ),
          )).toList()),
        ]),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _whatToExpectItems[index]['icon'] = picked);
    }
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: _saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_isEdit ? context.tr('save_changes') : context.tr('create_event'), style: appText(size: 16, weight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border.withOpacity(0.5), width: 0.7)),
    child: child,
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: appText(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary)),
  );

  Widget _input(TextEditingController ctrl, String hint, {String? Function(String?)? validator, int maxLines = 1, TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters}) {
    return TextFormField(
      controller: ctrl, maxLines: maxLines, validator: validator, keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: appText(size: 15),
      decoration: InputDecoration(
        hintText: hint, hintStyle: appText(size: 14, color: AppColors.textHint),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _eventTypeGrid() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _apiEventTypes.map((t) {
        final id = t['id']?.toString() ?? '';
        final name = extractStr(t['name'], fallback: id);
        final selected = _eventTypeId == id;
        return GestureDetector(
          onTap: () => setState(() => _eventTypeId = id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
            ),
            child: Text(name, style: appText(size: 13, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary)),
          ),
        );
      }).toList(),
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: appText(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle, style: appText(size: 11, color: AppColors.textTertiary)),
      ])),
      Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    ]);
  }

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return GestureDetector(
      onTap: () async {
        final date = await showNuruDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (date != null && mounted) onPick(date);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          SvgPicture.asset('assets/icons/calendar-icon.svg', width: 16, height: 16, colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            value != null ? _formatDate(value) : label,
            style: appText(size: 14, color: value != null ? AppColors.textPrimary : AppColors.textHint, weight: value != null ? FontWeight.w500 : FontWeight.w400),
          )),
        ]),
      ),
    );
  }

  Widget _timePicker(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPick) {
    return GestureDetector(
      onTap: () async {
        final time = await showNuruTimePicker(
          context: context,
          initialTime: value ?? TimeOfDay.now(),
        );
        if (time != null && mounted) onPick(time);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          SvgPicture.asset('assets/icons/clock-icon.svg', width: 16, height: 16, colorFilter: const ColorFilter.mode(AppColors.textTertiary, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            value != null ? value.format(context) : label,
            style: appText(size: 14, color: value != null ? AppColors.textPrimary : AppColors.textHint, weight: value != null ? FontWeight.w500 : FontWeight.w400),
          )),
        ]),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;
  _DashedBorderPainter({required this.color, required this.radius, required this.dash, required this.gap, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      double dist = 0;
      while (dist < m.length) {
        final next = (dist + dash).clamp(0, m.length).toDouble();
        canvas.drawPath(m.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.dash != dash || old.gap != gap || old.strokeWidth != strokeWidth;
}
