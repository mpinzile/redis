// Card Designer document model - serialisable JSON describing a fully custom
// invitation card (canvas + ordered layers). Stored on events.invitation_content
// under the 'design_doc' key so no backend schema change is required.
//
// Coordinates are in canvas user-units (matching canvas.width × canvas.height).
// The renderer scales everything uniformly to fit its allotted space.

import 'package:flutter/material.dart';

enum CanvasPreset { portrait, square, story, custom }

CanvasPreset canvasPresetFrom(String? s) {
  switch (s) {
    case 'square':
      return CanvasPreset.square;
    case 'story':
      return CanvasPreset.story;
    case 'custom':
      return CanvasPreset.custom;
    case 'portrait':
    default:
      return CanvasPreset.portrait;
  }
}

String canvasPresetName(CanvasPreset p) => p.name;

class CanvasSpec {
  final double width;
  final double height;
  final Color backgroundColor;
  final String? backgroundImageUrl;
  final CanvasPreset preset;

  const CanvasSpec({
    required this.width,
    required this.height,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.backgroundImageUrl,
    this.preset = CanvasPreset.portrait,
  });

  CanvasSpec copyWith({
    double? width,
    double? height,
    Color? backgroundColor,
    String? backgroundImageUrl,
    CanvasPreset? preset,
    bool clearBackgroundImage = false,
  }) =>
      CanvasSpec(
        width: width ?? this.width,
        height: height ?? this.height,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        backgroundImageUrl: clearBackgroundImage
            ? null
            : (backgroundImageUrl ?? this.backgroundImageUrl),
        preset: preset ?? this.preset,
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'background_color': _colorToHex(backgroundColor),
        if (backgroundImageUrl != null) 'background_image_url': backgroundImageUrl,
        'preset': canvasPresetName(preset),
      };

  factory CanvasSpec.fromJson(Map<String, dynamic> j) => CanvasSpec(
        width: (j['width'] as num?)?.toDouble() ?? 1080,
        height: (j['height'] as num?)?.toDouble() ?? 1350,
        backgroundColor: _hexToColor(j['background_color']?.toString()) ??
            const Color(0xFFFFFFFF),
        backgroundImageUrl: j['background_image_url']?.toString(),
        preset: canvasPresetFrom(j['preset']?.toString()),
      );

  static const portrait = CanvasSpec(width: 1080, height: 1350);
  static const square = CanvasSpec(
      width: 1080, height: 1080, preset: CanvasPreset.square);
  static const story =
      CanvasSpec(width: 1080, height: 1920, preset: CanvasPreset.story);
}

abstract class CardLayer {
  String get id;
  String get type;
  String get name;
  double get x;
  double get y;
  double get width;
  double get height;
  double get rotation; // degrees
  double get opacity;
  bool get locked;
  bool get hidden;

  Map<String, dynamic> toJson();
  CardLayer copyBase({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    bool? locked,
    bool? hidden,
    String? name,
  });

  static CardLayer? fromJson(Map<String, dynamic> j) {
    switch (j['type']?.toString()) {
      case 'text':
        return TextLayer.fromJson(j);
      case 'shape':
        return ShapeLayer.fromJson(j);
      case 'qr':
        return QrLayer.fromJson(j);
      case 'image':
        return ImageLayer.fromJson(j);
    }
    return null;
  }
}

class TextLayer extends CardLayer {
  @override final String id;
  @override final String name;
  @override final double x, y, width, height, rotation, opacity;
  @override final bool locked, hidden;
  /// Body text. May contain placeholders like {{guest_name}}.
  final String content;
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final bool italic;
  final Color color;
  final TextAlign textAlign;
  final double letterSpacing;
  final double lineHeight; // multiplier
  final Color? backgroundColor; // pill background, optional
  final double backgroundRadius;
  final bool shadow;
  /// When true, the text wraps across lines and grows vertically as needed.
  /// When false (default), the text is shrunk to fit its box (FittedBox).
  final bool wrap;

  TextLayer({
    required this.id,
    this.name = 'Text',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.opacity = 1,
    this.locked = false,
    this.hidden = false,
    required this.content,
    this.fontFamily = 'Inter',
    this.fontSize = 32,
    this.fontWeight = FontWeight.w500,
    this.italic = false,
    this.color = const Color(0xFF111111),
    this.textAlign = TextAlign.center,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.backgroundColor,
    this.backgroundRadius = 0,
    this.shadow = false,
    this.wrap = false,
  });

  @override
  String get type => 'text';

  TextLayer copyWith({
    String? name,
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden,
    String? content,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    bool? italic,
    Color? color,
    TextAlign? textAlign,
    double? letterSpacing,
    double? lineHeight,
    Color? backgroundColor,
    double? backgroundRadius,
    bool? shadow,
    bool? wrap,
    bool clearBackground = false,
  }) =>
      TextLayer(
        id: id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        locked: locked ?? this.locked,
        hidden: hidden ?? this.hidden,
        content: content ?? this.content,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        italic: italic ?? this.italic,
        color: color ?? this.color,
        textAlign: textAlign ?? this.textAlign,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        lineHeight: lineHeight ?? this.lineHeight,
        backgroundColor:
            clearBackground ? null : (backgroundColor ?? this.backgroundColor),
        backgroundRadius: backgroundRadius ?? this.backgroundRadius,
        shadow: shadow ?? this.shadow,
        wrap: wrap ?? this.wrap,
      );

  @override
  CardLayer copyBase({
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden,
    String? name,
  }) =>
      copyWith(
        x: x, y: y, width: width, height: height, rotation: rotation,
        opacity: opacity, locked: locked, hidden: hidden, name: name,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name,
        'x': x, 'y': y, 'width': width, 'height': height,
        'rotation': rotation, 'opacity': opacity,
        'locked': locked, 'hidden': hidden,
        'content': content,
        'style': {
          'font_family': fontFamily,
          'font_size': fontSize,
          'font_weight': fontWeight.value,
          'italic': italic,
          'color': _colorToHex(color),
          'text_align': textAlign.name,
          'letter_spacing': letterSpacing,
          'line_height': lineHeight,
          if (backgroundColor != null)
            'background_color': _colorToHex(backgroundColor!),
          'background_radius': backgroundRadius,
          'shadow': shadow,
          'wrap': wrap,
        },
      };

  factory TextLayer.fromJson(Map<String, dynamic> j) {
    final s = (j['style'] as Map?) ?? const {};
    return TextLayer(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? 'Text',
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
      locked: j['locked'] == true,
      hidden: j['hidden'] == true,
      content: j['content']?.toString() ?? '',
      fontFamily: s['font_family']?.toString() ?? 'Inter',
      fontSize: (s['font_size'] as num?)?.toDouble() ?? 32,
      fontWeight: _fontWeightFromInt((s['font_weight'] as num?)?.toInt() ?? 500),
      italic: s['italic'] == true,
      color: _hexToColor(s['color']?.toString()) ?? const Color(0xFF111111),
      textAlign: _textAlignFromName(s['text_align']?.toString()),
      letterSpacing: (s['letter_spacing'] as num?)?.toDouble() ?? 0,
      lineHeight: (s['line_height'] as num?)?.toDouble() ?? 1.2,
      backgroundColor: _hexToColor(s['background_color']?.toString()),
      backgroundRadius: (s['background_radius'] as num?)?.toDouble() ?? 0,
      shadow: s['shadow'] == true,
      wrap: s['wrap'] == true,
    );
  }
}

enum ShapeKind { rectangle, ellipse, line }

ShapeKind shapeKindFrom(String? s) {
  switch (s) {
    case 'ellipse':
      return ShapeKind.ellipse;
    case 'line':
      return ShapeKind.line;
    case 'rectangle':
    default:
      return ShapeKind.rectangle;
  }
}

class ShapeLayer extends CardLayer {
  @override final String id;
  @override final String name;
  @override final double x, y, width, height, rotation, opacity;
  @override final bool locked, hidden;
  final ShapeKind kind;
  final Color fill;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;

  ShapeLayer({
    required this.id,
    this.name = 'Shape',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.opacity = 1,
    this.locked = false,
    this.hidden = false,
    this.kind = ShapeKind.rectangle,
    this.fill = const Color(0xFFD4AF37),
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.borderRadius = 0,
  });

  @override
  String get type => 'shape';

  ShapeLayer copyWith({
    String? name,
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden,
    ShapeKind? kind,
    Color? fill,
    Color? borderColor,
    double? borderWidth,
    double? borderRadius,
  }) =>
      ShapeLayer(
        id: id,
        name: name ?? this.name,
        x: x ?? this.x, y: y ?? this.y,
        width: width ?? this.width, height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        locked: locked ?? this.locked, hidden: hidden ?? this.hidden,
        kind: kind ?? this.kind,
        fill: fill ?? this.fill,
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  CardLayer copyBase({
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden, String? name,
  }) =>
      copyWith(
        x: x, y: y, width: width, height: height,
        rotation: rotation, opacity: opacity,
        locked: locked, hidden: hidden, name: name,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name,
        'x': x, 'y': y, 'width': width, 'height': height,
        'rotation': rotation, 'opacity': opacity,
        'locked': locked, 'hidden': hidden,
        'kind': kind.name,
        'style': {
          'fill': _colorToHex(fill),
          'border_color': _colorToHex(borderColor),
          'border_width': borderWidth,
          'border_radius': borderRadius,
        },
      };

  factory ShapeLayer.fromJson(Map<String, dynamic> j) {
    final s = (j['style'] as Map?) ?? const {};
    return ShapeLayer(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? 'Shape',
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
      locked: j['locked'] == true,
      hidden: j['hidden'] == true,
      kind: shapeKindFrom(j['kind']?.toString()),
      fill: _hexToColor(s['fill']?.toString()) ?? const Color(0xFFD4AF37),
      borderColor:
          _hexToColor(s['border_color']?.toString()) ?? const Color(0x00000000),
      borderWidth: (s['border_width'] as num?)?.toDouble() ?? 0,
      borderRadius: (s['border_radius'] as num?)?.toDouble() ?? 0,
    );
  }
}

class QrLayer extends CardLayer {
  @override final String id;
  @override final String name;
  @override final double x, y, width, height, rotation, opacity;
  @override final bool locked, hidden;
  final Color foregroundColor;
  final Color backgroundColor;
  final double padding;
  final double borderRadius;

  QrLayer({
    required this.id,
    this.name = 'QR Code',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.opacity = 1,
    this.locked = false,
    this.hidden = false,
    this.foregroundColor = const Color(0xFF111111),
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.padding = 12,
    this.borderRadius = 12,
  });

  @override
  String get type => 'qr';

  QrLayer copyWith({
    String? name,
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden,
    Color? foregroundColor,
    Color? backgroundColor,
    double? padding,
    double? borderRadius,
  }) =>
      QrLayer(
        id: id,
        name: name ?? this.name,
        x: x ?? this.x, y: y ?? this.y,
        width: width ?? this.width, height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        locked: locked ?? this.locked, hidden: hidden ?? this.hidden,
        foregroundColor: foregroundColor ?? this.foregroundColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        padding: padding ?? this.padding,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  CardLayer copyBase({
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden, String? name,
  }) =>
      copyWith(
        x: x, y: y, width: width, height: height,
        rotation: rotation, opacity: opacity,
        locked: locked, hidden: hidden, name: name,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name,
        'x': x, 'y': y, 'width': width, 'height': height,
        'rotation': rotation, 'opacity': opacity,
        'locked': locked, 'hidden': hidden,
        'style': {
          'foreground_color': _colorToHex(foregroundColor),
          'background_color': _colorToHex(backgroundColor),
          'padding': padding,
          'border_radius': borderRadius,
        },
      };

  factory QrLayer.fromJson(Map<String, dynamic> j) {
    final s = (j['style'] as Map?) ?? const {};
    return QrLayer(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? 'QR Code',
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
      locked: j['locked'] == true,
      hidden: j['hidden'] == true,
      foregroundColor:
          _hexToColor(s['foreground_color']?.toString()) ?? const Color(0xFF111111),
      backgroundColor:
          _hexToColor(s['background_color']?.toString()) ?? const Color(0xFFFFFFFF),
      padding: (s['padding'] as num?)?.toDouble() ?? 12,
      borderRadius: (s['border_radius'] as num?)?.toDouble() ?? 12,
    );
  }
}

/// Image layer - currently used only for background images uploaded from
/// device. Stored as a remote URL once the image is uploaded; v1 also accepts
/// a local file:// path for preview before upload.
class ImageLayer extends CardLayer {
  @override final String id;
  @override final String name;
  @override final double x, y, width, height, rotation, opacity;
  @override final bool locked, hidden;
  final String url;
  final BoxFit fit;
  final double borderRadius;

  ImageLayer({
    required this.id,
    this.name = 'Image',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.opacity = 1,
    this.locked = false,
    this.hidden = false,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
  });

  @override
  String get type => 'image';

  ImageLayer copyWith({
    String? name,
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden,
    String? url,
    BoxFit? fit,
    double? borderRadius,
  }) =>
      ImageLayer(
        id: id,
        name: name ?? this.name,
        x: x ?? this.x, y: y ?? this.y,
        width: width ?? this.width, height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        locked: locked ?? this.locked, hidden: hidden ?? this.hidden,
        url: url ?? this.url,
        fit: fit ?? this.fit,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  CardLayer copyBase({
    double? x, double? y, double? width, double? height, double? rotation, double? opacity,
    bool? locked, bool? hidden, String? name,
  }) =>
      copyWith(
        x: x, y: y, width: width, height: height,
        rotation: rotation, opacity: opacity,
        locked: locked, hidden: hidden, name: name,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name,
        'x': x, 'y': y, 'width': width, 'height': height,
        'rotation': rotation, 'opacity': opacity,
        'locked': locked, 'hidden': hidden,
        'url': url,
        'style': {
          'fit': fit.name,
          'border_radius': borderRadius,
        },
      };

  factory ImageLayer.fromJson(Map<String, dynamic> j) {
    final s = (j['style'] as Map?) ?? const {};
    return ImageLayer(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? 'Image',
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
      locked: j['locked'] == true,
      hidden: j['hidden'] == true,
      url: j['url']?.toString() ?? '',
      fit: _boxFitFromName(s['fit']?.toString()),
      borderRadius: (s['border_radius'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CardDesignDoc {
  final int version;
  final CanvasSpec canvas;
  final List<CardLayer> layers;

  const CardDesignDoc({
    this.version = 1,
    required this.canvas,
    required this.layers,
  });

  CardDesignDoc copyWith({CanvasSpec? canvas, List<CardLayer>? layers}) =>
      CardDesignDoc(
        version: version,
        canvas: canvas ?? this.canvas,
        layers: layers ?? this.layers,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'canvas': canvas.toJson(),
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory CardDesignDoc.fromJson(Map<String, dynamic> j) {
    final layers = <CardLayer>[];
    final raw = j['layers'];
    if (raw is List) {
      for (final l in raw) {
        if (l is Map) {
          final layer = CardLayer.fromJson(Map<String, dynamic>.from(l));
          if (layer != null) layers.add(layer);
        }
      }
    }
    return CardDesignDoc(
      version: (j['version'] as num?)?.toInt() ?? 1,
      canvas: CanvasSpec.fromJson(
          Map<String, dynamic>.from((j['canvas'] as Map?) ?? const {})),
      layers: layers,
    );
  }

  /// Truly blank canvas - no preset layers. User builds everything from
  /// scratch. Useful for the "Blank Canvas" entry on the designer launcher.
  factory CardDesignDoc.blank({CanvasSpec canvas = CanvasSpec.portrait}) {
    return CardDesignDoc(canvas: canvas, layers: const []);
  }

  /// Default starter doc (portrait 1080×1350 with a centred title + QR).
  factory CardDesignDoc.starter({
    required Color accent,
    String title = '{{event_title}}',
  }) {
    return CardDesignDoc(
      canvas: const CanvasSpec(
        width: 1080,
        height: 1350,
        backgroundColor: Color(0xFFF7F1E7),
      ),
      layers: [
        ShapeLayer(
          id: 'bg-band',
          name: 'Accent band',
          x: 80, y: 80, width: 920, height: 1190,
          fill: const Color(0x00000000),
          borderColor: accent,
          borderWidth: 4,
          borderRadius: 24,
        ),
        TextLayer(
          id: 'title',
          name: 'Event title',
          x: 120, y: 240, width: 840, height: 160,
          content: title,
          fontFamily: 'Playfair Display',
          fontSize: 72,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1B1B1B),
        ),
        TextLayer(
          id: 'guest',
          name: 'Guest name',
          x: 120, y: 460, width: 840, height: 100,
          content: '{{guest_name}}',
          fontFamily: 'Inter',
          fontSize: 44,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
        TextLayer(
          id: 'date',
          name: 'Date and time',
          x: 120, y: 600, width: 840, height: 80,
          content: '{{event_date}}  •  {{event_time}}',
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF333333),
        ),
        TextLayer(
          id: 'venue',
          name: 'Venue',
          x: 120, y: 690, width: 840, height: 80,
          content: '{{event_location}}',
          fontFamily: 'Inter',
          fontSize: 28,
          color: const Color(0xFF555555),
        ),
        QrLayer(
          id: 'qr',
          name: 'QR Code',
          x: 420, y: 900, width: 240, height: 240,
          foregroundColor: const Color(0xFF111111),
          backgroundColor: const Color(0xFFFFFFFF),
          padding: 14,
          borderRadius: 16,
        ),
        TextLayer(
          id: 'invite-code',
          name: 'Invite code',
          x: 120, y: 1180, width: 840, height: 60,
          content: 'CODE  {{invite_code}}',
          fontFamily: 'Inter',
          fontSize: 22,
          letterSpacing: 4,
          color: const Color(0xFF777777),
        ),
      ],
    );
  }
}

/// Render context - real values used to substitute placeholders and provide
/// the QR payload at render time. Built once per render (preview or download).
class CardRenderContext {
  final String guestName;
  final String eventTitle;
  final String eventDate;
  final String eventTime;
  final String eventLocation;
  final String organizerName;
  final String inviteCode;
  final String qrPayload;

  const CardRenderContext({
    this.guestName = 'Your Guest',
    this.eventTitle = 'Your Event',
    this.eventDate = '',
    this.eventTime = '',
    this.eventLocation = '',
    this.organizerName = '',
    this.inviteCode = '',
    this.qrPayload = '',
  });

  String apply(String input) {
    return input
        .replaceAll('{{guest_name}}', guestName)
        .replaceAll('{{event_title}}', eventTitle)
        .replaceAll('{{event_date}}', eventDate)
        .replaceAll('{{event_time}}', eventTime)
        .replaceAll('{{event_location}}', eventLocation)
        .replaceAll('{{organizer_name}}', organizerName)
        .replaceAll('{{invite_code}}', inviteCode);
  }
}

// ───────── helpers ─────────

String _colorToHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

Color? _hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

FontWeight _fontWeightFromInt(int v) {
  for (final w in FontWeight.values) {
    if (w.value == v) return w;
  }
  return FontWeight.w500;
}

TextAlign _textAlignFromName(String? n) {
  switch (n) {
    case 'left':
      return TextAlign.left;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    case 'center':
    default:
      return TextAlign.center;
  }
}

BoxFit _boxFitFromName(String? n) {
  switch (n) {
    case 'contain':
      return BoxFit.contain;
    case 'fill':
      return BoxFit.fill;
    case 'fitWidth':
      return BoxFit.fitWidth;
    case 'fitHeight':
      return BoxFit.fitHeight;
    case 'none':
      return BoxFit.none;
    case 'scaleDown':
      return BoxFit.scaleDown;
    case 'cover':
    default:
      return BoxFit.cover;
  }
}
