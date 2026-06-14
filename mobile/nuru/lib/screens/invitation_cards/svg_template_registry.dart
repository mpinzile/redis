// SVG Invitation Card Template Registry - mobile mirror of
// src/components/invitation-cards/SvgTemplateRegistry.ts
//
// Same template IDs, categories and field mapping so any choice an organiser
// saves on the web (events.invitation_template) renders identically on mobile.

class SvgCardFields {
  final String nameField;          // bride | honoree | couple | eventTitle
  final String? secondNameField;   // groom (weddings only)
  final String? dateField;
  final String? timeField;
  final String? venueField;
  final String? addressField;

  const SvgCardFields({
    required this.nameField,
    this.secondNameField,
    this.dateField = 'date',
    this.timeField = 'time',
    this.venueField = 'venue',
    this.addressField = 'address',
  });
}

class SvgCardTemplate {
  final String id;
  final String name;
  final String description;
  final List<String> category;
  /// Asset path inside mobile/nuru/assets/card-templates/
  final String assetPath;
  final bool hasQr;
  final SvgCardFields fields;

  const SvgCardTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.assetPath,
    required this.fields,
    this.hasQr = true,
  });
}

/// Manual QR placement override saved alongside invitation_content.
/// All values are in SVG user-units against the 480×680 canvas.
class QrOverride {
  final double x;
  final double y;
  final double size;
  const QrOverride({required this.x, required this.y, required this.size});

  factory QrOverride.fromJson(Map<String, dynamic> j) => QrOverride(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        size: (j['size'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'size': size};
}

/// Editable copy persisted on events.invitation_content (JSONB).
class InvitationContent {
  final String? headline;
  final String? subHeadline;
  final String? hostLine;
  final String? body;
  final String? footerNote;
  final String? dressCodeLabel;
  final String? rsvpLabel;
  /// Manual QR rect override (organiser-positioned in the editor).
  final QrOverride? qrOverride;
  /// Ids of <text> elements the organiser chose to hide on the card.
  final List<String> hiddenIds;
  /// Full custom designer document (CardDesignDoc as JSON). When present, the
  /// renderer ignores the SVG template path and paints this design instead.
  /// Stored as opaque JSON so backend needs no schema change.
  final Map<String, dynamic>? designDoc;

  const InvitationContent({
    this.headline,
    this.subHeadline,
    this.hostLine,
    this.body,
    this.footerNote,
    this.dressCodeLabel,
    this.rsvpLabel,
    this.qrOverride,
    this.hiddenIds = const [],
    this.designDoc,
  });

  InvitationContent copyWith({
    String? headline,
    String? subHeadline,
    String? hostLine,
    String? body,
    String? footerNote,
    String? dressCodeLabel,
    String? rsvpLabel,
    QrOverride? qrOverride,
    List<String>? hiddenIds,
    Map<String, dynamic>? designDoc,
    bool clearQrOverride = false,
    bool clearDesignDoc = false,
  }) =>
      InvitationContent(
        headline: headline ?? this.headline,
        subHeadline: subHeadline ?? this.subHeadline,
        hostLine: hostLine ?? this.hostLine,
        body: body ?? this.body,
        footerNote: footerNote ?? this.footerNote,
        dressCodeLabel: dressCodeLabel ?? this.dressCodeLabel,
        rsvpLabel: rsvpLabel ?? this.rsvpLabel,
        qrOverride: clearQrOverride ? null : (qrOverride ?? this.qrOverride),
        hiddenIds: hiddenIds ?? this.hiddenIds,
        designDoc: clearDesignDoc ? null : (designDoc ?? this.designDoc),
      );

  factory InvitationContent.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InvitationContent();
    String? s(dynamic v) => v == null ? null : v.toString();
    QrOverride? qr;
    final qj = json['qr_override'];
    if (qj is Map) {
      try {
        qr = QrOverride.fromJson(Map<String, dynamic>.from(qj));
      } catch (_) {}
    }
    final hidden = <String>[];
    final hj = json['hidden_ids'];
    if (hj is List) {
      for (final v in hj) {
        if (v != null) hidden.add(v.toString());
      }
    }
    return InvitationContent(
      headline: s(json['headline']),
      subHeadline: s(json['sub_headline']),
      hostLine: s(json['host_line']),
      body: s(json['body']),
      footerNote: s(json['footer_note']),
      dressCodeLabel: s(json['dress_code_label']),
      rsvpLabel: s(json['rsvp_label']),
      qrOverride: qr,
      hiddenIds: hidden,
      designDoc: json['design_doc'] is Map
          ? Map<String, dynamic>.from(json['design_doc'] as Map)
          : null,
    );
  }

  bool get isEmpty =>
      headline == null &&
      subHeadline == null &&
      hostLine == null &&
      body == null &&
      footerNote == null &&
      dressCodeLabel == null &&
      rsvpLabel == null &&
      qrOverride == null &&
      hiddenIds.isEmpty &&
      designDoc == null;
}

const String _ap = 'assets/card-templates';

const List<SvgCardTemplate> kSvgTemplates = [
  SvgCardTemplate(
    id: 'wedding-botanical',
    name: 'Botanical Garden',
    description: 'Elegant eucalyptus watercolour with gold accents on warm cream',
    category: ['wedding'],
    assetPath: '$_ap/01-wedding-botanical.svg',
    fields: SvgCardFields(nameField: 'bride', secondNameField: 'groom'),
  ),
  SvgCardTemplate(
    id: 'birthday-constellation',
    name: 'Constellation Night',
    description: 'Deep midnight sky with silver star constellations',
    category: ['birthday'],
    assetPath: '$_ap/02-birthday-constellation.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'sendoff-terracotta',
    name: 'Terracotta Arch',
    description: 'Warm terracotta arch with olive branch details',
    category: ['sendoff'],
    assetPath: '$_ap/03-sendoff-terracotta.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'wedding-darkpeony',
    name: 'Dark Peony',
    description: 'Dramatic moody florals with blush peonies on noir background',
    category: ['wedding'],
    assetPath: '$_ap/04-wedding-darkpeony.svg',
    fields: SvgCardFields(nameField: 'bride', secondNameField: 'groom'),
  ),
  SvgCardTemplate(
    id: 'memorial-candle',
    name: 'Candlelight Glow',
    description: 'Single elegant candle flame on deep forest green',
    category: ['memorial'],
    assetPath: '$_ap/05-birthday-candle.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'gala-geometric',
    name: 'Geometric Diamond',
    description: 'Art deco geometric diamond on pure black with gold lines',
    category: ['corporate', 'conference'],
    assetPath: '$_ap/06-gala-geometric.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'wedding-artnouveau',
    name: 'Art Nouveau Rose',
    description: 'Art Nouveau vine corners with rose buds on linen texture',
    category: ['wedding'],
    assetPath: '$_ap/07-wedding-artnouveau.svg',
    fields: SvgCardFields(nameField: 'bride', secondNameField: 'groom'),
  ),
  SvgCardTemplate(
    id: 'sendoff-crane',
    name: 'Origami Crane',
    description: 'Minimalist origami crane in gold on charcoal, Japanese inspired',
    category: ['sendoff'],
    assetPath: '$_ap/08-sendoff-crane.svg',
    fields: SvgCardFields(nameField: 'honoree', addressField: null),
  ),
  SvgCardTemplate(
    id: 'birthday-inkwash',
    name: 'Ink Wash Editorial',
    description: 'Abstract watercolour ink blots with editorial asymmetric layout',
    category: ['birthday'],
    assetPath: '$_ap/09-birthday-inkwash.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'anniversary-magnolia',
    name: 'Magnolia Bloom',
    description: 'Luminous magnolia on deep teal with gold and ivory accents',
    category: ['anniversary'],
    assetPath: '$_ap/10-anniversary-magnolia.svg',
    fields: SvgCardFields(nameField: 'couple'),
  ),
  SvgCardTemplate(
    id: 'corporate-monolith',
    name: 'Monolith Black Tie',
    description: 'Architectural monolith on midnight navy with brushed-gold edge',
    category: ['corporate'],
    assetPath: '$_ap/11-corporate-monolith.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'conference-summit',
    name: 'Summit Editorial',
    description: 'Bold numeral statement on warm linen with deep forest accents',
    category: ['conference', 'corporate'],
    assetPath: '$_ap/12-conference-summit.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'graduation-laurel',
    name: 'Laurel & Cap',
    description: 'Classical laurel wreath with mortarboard on plum velvet',
    category: ['graduation'],
    assetPath: '$_ap/13-graduation-laurel.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'baby-balloon',
    name: 'Pastel Balloon',
    description: 'Hot-air balloon drifting through blush pastel skies',
    category: ['baby_shower'],
    assetPath: '$_ap/14-baby-balloon.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'wedding-tropical',
    name: 'Tropical Coast',
    description: 'Hand-drawn palm canopy on warm sand for a coastal wedding',
    category: ['wedding'],
    assetPath: '$_ap/15-wedding-tropical.svg',
    fields: SvgCardFields(nameField: 'bride', secondNameField: 'groom'),
  ),
  SvgCardTemplate(
    id: 'birthday-confetti',
    name: 'Confetti Cake',
    description: 'Tiered cake with playful confetti on a soft blush ground',
    category: ['birthday'],
    assetPath: '$_ap/16-birthday-confetti.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'sendoff-twilight',
    name: 'Twilight Mountain',
    description: 'Moonrise over silhouetted ridges for a quiet farewell',
    category: ['sendoff'],
    assetPath: '$_ap/17-sendoff-twilight.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'anniversary-golden',
    name: 'Golden Roman L',
    description: 'Roman numeral L with a heart for a fiftieth anniversary',
    category: ['anniversary'],
    assetPath: '$_ap/18-anniversary-golden.svg',
    fields: SvgCardFields(nameField: 'couple'),
  ),
  SvgCardTemplate(
    id: 'memorial-olive',
    name: 'Olive Wreath',
    description: 'Olive wreath on linen with quiet typographic dignity',
    category: ['memorial'],
    assetPath: '$_ap/19-memorial-olive.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'festival-poster',
    name: 'Festival Poster',
    description: 'Editorial sun poster with hand-drawn frame for festivals',
    category: ['corporate'],
    assetPath: '$_ap/20-festival-poster.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'corporate-launch',
    name: 'Wireframe Launch',
    description: 'Wireframe sphere on deep emerald for product unveilings',
    category: ['corporate'],
    assetPath: '$_ap/21-corporate-launch.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'birthday-sunshine',
    name: 'Sunshine Number',
    description: 'Big age numeral inside a sun for cheerful childrens birthdays',
    category: ['birthday'],
    assetPath: '$_ap/22-birthday-sunshine.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'graduation-script',
    name: 'Script Honours',
    description: 'Navy and gold script honouring a new graduate',
    category: ['graduation'],
    assetPath: '$_ap/23-graduation-script.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'graduation-bookstack',
    name: 'Library Stack',
    description: 'Stacked books on linen for a scholarly send-off',
    category: ['graduation'],
    assetPath: '$_ap/24-graduation-bookstack.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'baby-cloud',
    name: 'Soft Clouds',
    description: 'Drifting clouds in warm peach for a tender baby shower',
    category: ['baby_shower'],
    assetPath: '$_ap/25-baby-cloud.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'baby-moon',
    name: 'Moon and Stars',
    description: 'Gentle moon and stars for an evening baby celebration',
    category: ['baby_shower'],
    assetPath: '$_ap/26-baby-moon.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'conference-grid',
    name: 'Editorial Grid',
    description: 'Newsprint grid layout for serious conferences and summits',
    category: ['conference', 'corporate'],
    assetPath: '$_ap/27-conference-grid.svg',
    fields: SvgCardFields(nameField: 'eventTitle'),
  ),
  SvgCardTemplate(
    id: 'memorial-stillwater',
    name: 'Still Water',
    description: 'Single light over still water for a quiet remembrance',
    category: ['memorial'],
    assetPath: '$_ap/28-memorial-stillwater.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
  SvgCardTemplate(
    id: 'anniversary-pearl',
    name: 'Pearl Strand',
    description: 'Pearl strand and gold border for milestone anniversaries',
    category: ['anniversary'],
    assetPath: '$_ap/29-anniversary-pearl.svg',
    fields: SvgCardFields(nameField: 'couple'),
  ),
  SvgCardTemplate(
    id: 'sendoff-coast',
    name: 'Sunset Coast',
    description: 'Warm sunset and sailboat for a coastal farewell',
    category: ['sendoff'],
    assetPath: '$_ap/30-sendoff-coast.svg',
    fields: SvgCardFields(nameField: 'honoree'),
  ),
];

const Map<String, List<String>> _eventTypeCategoryMap = {
  'wedding': ['wedding'],
  'birthday': ['birthday'],
  'corporate': ['corporate', 'conference'],
  'memorial': ['memorial', 'anniversary'],
  'anniversary': ['anniversary'],
  'conference': ['conference', 'corporate'],
  'graduation': ['graduation'],
  'sendoff': ['sendoff'],
  'sendoff_': ['sendoff'],
  'send_off': ['sendoff'],
  'babyshower': ['baby_shower'],
  'baby_shower': ['baby_shower'],
  'productlaunch': ['corporate'],
  'product_launch': ['corporate'],
  'festival': ['corporate'],
  'exhibition': ['corporate'],
  'burial': ['memorial'],
};

List<SvgCardTemplate> templatesForEventType(String? eventType) {
  final normalized = (eventType ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  final cats = _eventTypeCategoryMap[normalized] ?? const ['wedding'];
  return kSvgTemplates.where((t) => t.category.any((c) => cats.contains(c))).toList();
}

SvgCardTemplate? templateById(String? id) {
  if (id == null) return null;
  try {
    return kSvgTemplates.firstWhere((t) => t.id == id);
  } catch (_) {
    return null;
  }
}

SvgCardTemplate randomTemplateForEvent(String? eventType) {
  final list = templatesForEventType(eventType);
  if (list.isEmpty) return kSvgTemplates.first;
  list.shuffle();
  return list.first;
}
