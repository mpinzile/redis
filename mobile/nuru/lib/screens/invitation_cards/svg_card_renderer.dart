// SvgCardRenderer (mobile) - mirror of src/components/invitation-cards/SvgCardRenderer.tsx
//
// Loads the raw SVG asset string, replaces the placeholder text content of
// each <text id="..."> we recognise (guest data + InvitationContent overrides),
// renders via flutter_svg, and overlays a real QR code on the placeholder rect.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'svg_template_registry.dart';

class SvgCardData {
  final String guestName;
  final String? secondName;     // groom for weddings
  final String eventTitle;
  final String date;
  final String time;
  final String venue;
  final String? address;
  final String? qrValue;

  const SvgCardData({
    required this.guestName,
    this.secondName,
    required this.eventTitle,
    required this.date,
    required this.time,
    required this.venue,
    this.address,
    this.qrValue,
  });
}

class SvgCardRenderer extends StatefulWidget {
  final SvgCardTemplate template;
  final SvgCardData data;
  final InvitationContent? contentOverrides;

  const SvgCardRenderer({
    super.key,
    required this.template,
    required this.data,
    this.contentOverrides,
  });

  @override
  State<SvgCardRenderer> createState() => _SvgCardRendererState();
}

class _SvgCardRendererState extends State<SvgCardRenderer> {
  late Future<_PreparedSvg> _future;

  @override
  void initState() {
    super.initState();
    _future = _prepare();
  }

  @override
  void didUpdateWidget(covariant SvgCardRenderer old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id ||
        old.data != widget.data ||
        old.contentOverrides != widget.contentOverrides) {
      _future = _prepare();
    }
  }

  Future<_PreparedSvg> _prepare() async {
    final raw = await rootBundle.loadString(widget.template.assetPath);
    var processed = _injectDynamicData(raw, widget.template, widget.data, widget.contentOverrides);
    // Apply hidden-text overrides (organiser stripped these from the card).
    final hidden = widget.contentOverrides?.hiddenIds ?? const [];
    if (hidden.isNotEmpty) processed = _stripTextIds(processed, hidden);
    // Manual QR rect override beats the auto-detected placeholder.
    final ov = widget.contentOverrides?.qrOverride;
    final qr = ov != null
        ? _QrPos(ov.x, ov.y, ov.size, ov.size)
        : _findQrPlaceholder(processed);
    return _PreparedSvg(processed, qr);
  }

  String _stripTextIds(String svg, List<String> ids) {
    for (final id in ids) {
      final re = RegExp(
        '<text[^>]*\\bid="${RegExp.escape(id)}"[^>]*>[^<]*</text>',
        multiLine: true,
      );
      svg = svg.replaceAll(re, '');
    }
    return svg;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 480 / 680,
      child: FutureBuilder<_PreparedSvg>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const ColoredBox(color: Color(0xFFF4EFE4));
          }
          final p = snap.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: SvgPicture.string(
                      p.svg,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (widget.data.qrValue != null && widget.template.hasQr && p.qr != null)
                    _qrOverlay(p.qr!, p.isDark, constraints),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _qrOverlay(_QrPos qr, bool isDark, BoxConstraints c) {
    const svgW = 480.0;
    const svgH = 680.0;
    // Account for BoxFit.contain letterboxing.
    final scale = (c.maxWidth / svgW).clamp(0, c.maxHeight / svgH).toDouble();
    final renderW = svgW * scale;
    final renderH = svgH * scale;
    final offsetX = (c.maxWidth - renderW) / 2;
    final offsetY = (c.maxHeight - renderH) / 2;

    // Fill the placeholder square edge-to-edge - no inset, no quiet zone.
    return Positioned(
      left: offsetX + qr.x * scale,
      top: offsetY + qr.y * scale,
      width: qr.w * scale,
      height: qr.h * scale,
      child: QrImageView(
        data: widget.data.qrValue!,
        version: QrVersions.auto,
        padding: EdgeInsets.zero,
        backgroundColor: isDark ? const Color(0xFF111111) : const Color(0xFFF5F0E8),
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: isDark ? const Color(0xFFC8A828) : const Color(0xFF3A2A18),
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: isDark ? const Color(0xFFC8A828) : const Color(0xFF3A2A18),
        ),
      ),
    );
  }
}

// ─────────────────────────── helpers ───────────────────────────

class _PreparedSvg {
  final String svg;
  final _QrPos? qr;
  _PreparedSvg(this.svg, this.qr);

  bool get isDark =>
      svg.contains('stop-color="#08') ||
      svg.contains('stop-color="#0d') ||
      svg.contains('stop-color="#0e') ||
      svg.contains('stop-color="#0a') ||
      svg.contains('stop-color="#1a') ||
      svg.contains('stop-color="#14');
}

class _QrPos {
  final double x, y, w, h;
  _QrPos(this.x, this.y, this.w, this.h);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _injectDynamicData(
  String svg,
  SvgCardTemplate template,
  SvgCardData data,
  InvitationContent? overrides,
) {
  final f = template.fields;
  final repl = <String, String>{};

  // Name fields - match web mapping.
  if (f.nameField == 'bride' || f.nameField == 'honoree' || f.nameField == 'couple') {
    repl[f.nameField] = data.guestName;
  } else if (f.nameField == 'eventTitle') {
    repl[f.nameField] = data.eventTitle;
  }
  if (f.secondNameField != null && (data.secondName ?? '').isNotEmpty) {
    repl[f.secondNameField!] = data.secondName!;
  }
  if (f.dateField != null) repl[f.dateField!] = data.date;
  if (f.timeField != null) repl[f.timeField!] = data.time;
  if (f.venueField != null) repl[f.venueField!] = data.venue;
  if (f.addressField != null && (data.address ?? '').isNotEmpty) {
    repl[f.addressField!] = data.address!;
  }

  // InvitationContent overrides (events.invitation_content JSONB).
  if (overrides != null) {
    if ((overrides.headline ?? '').isNotEmpty) repl['headline'] = overrides.headline!;
    if ((overrides.subHeadline ?? '').isNotEmpty) repl['sub_headline'] = overrides.subHeadline!;
    if ((overrides.hostLine ?? '').isNotEmpty) repl['host_line'] = overrides.hostLine!;
    if ((overrides.body ?? '').isNotEmpty) repl['body'] = overrides.body!;
    if ((overrides.footerNote ?? '').isNotEmpty) repl['footer_note'] = overrides.footerNote!;
    if ((overrides.dressCodeLabel ?? '').isNotEmpty) repl['dress_code_label'] = overrides.dressCodeLabel!;
    if ((overrides.rsvpLabel ?? '').isNotEmpty) repl['rsvp_label'] = overrides.rsvpLabel!;
  }

  for (final entry in repl.entries) {
    if (entry.value.isEmpty) continue;
    final pattern = RegExp(
      '(<text[^>]*\\bid="${RegExp.escape(entry.key)}"[^>]*>)([^<]*)(</text>)',
      multiLine: true,
    );
    svg = svg.replaceAllMapped(pattern, (m) => '${m[1]}${_xmlEscape(entry.value)}${m[3]}');
  }
  return svg;
}

/// Find the QR placeholder rect - uniquely marked with opacity="0.001".
_QrPos? _findQrPlaceholder(String svg) {
  final re = RegExp(r'<rect\b([^>]*\bopacity="0\.001"[^>]*)\/>');
  double? attr(String attrs, String name) {
    final m = RegExp('\\b$name="(-?\\d+(?:\\.\\d+)?)"').firstMatch(attrs);
    return m == null ? null : double.parse(m.group(1)!);
  }
  for (final m in re.allMatches(svg)) {
    final attrs = m.group(1)!;
    final x = attr(attrs, 'x');
    final y = attr(attrs, 'y');
    final w = attr(attrs, 'width');
    final h = attr(attrs, 'height');
    if (x == null || y == null || w == null || h == null) continue;
    return _QrPos(x, y, w, h);
  }
  return null;
}

/// Public: load a template asset and extract every (id, sampleText) pair from
/// `<text id="…">…</text>` declarations. Used by the QR & Layout editor to
/// build per-element visibility toggles.
class SvgTextElement {
  final String id;
  final String sample;
  const SvgTextElement(this.id, this.sample);
}

Future<List<SvgTextElement>> loadSvgTextElements(SvgCardTemplate tpl) async {
  final raw = await rootBundle.loadString(tpl.assetPath);
  final re = RegExp(
    r'<text\b[^>]*\bid="([^"]+)"[^>]*>([^<]*)</text>',
    multiLine: true,
  );
  final out = <SvgTextElement>[];
  final seen = <String>{};
  for (final m in re.allMatches(raw)) {
    final id = m.group(1)!;
    if (!seen.add(id)) continue;
    out.add(SvgTextElement(id, (m.group(2) ?? '').trim()));
  }
  return out;
}

/// Auto-detected QR rect (used by the editor as the starting position when
/// the organiser has not yet manually placed the QR).
Future<({double x, double y, double size})?> autoQrRectFor(
    SvgCardTemplate tpl) async {
  final raw = await rootBundle.loadString(tpl.assetPath);
  final pos = _findQrPlaceholder(raw);
  if (pos == null) return null;
  return (x: pos.x, y: pos.y, size: pos.w < pos.h ? pos.w : pos.h);
}
