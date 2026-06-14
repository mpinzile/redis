// CardRenderer - paints a CardDesignDoc into a fixed-size box. Used identically
// for organiser preview, full-screen preview, and per-guest PNG export. The
// only thing that changes between contexts is the CardRenderContext (real
// guest data + qr payload), so every invited guest gets a unique card.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'model.dart';

class CardRenderer extends StatelessWidget {
  final CardDesignDoc doc;
  final CardRenderContext context;

  /// Optional currently-selected layer id for editor overlays. The renderer
  /// itself doesn't draw selection chrome - see CardDesignerScreen.
  final String? selectedLayerId;

  const CardRenderer({
    super.key,
    required this.doc,
    required this.context,
    this.selectedLayerId,
  });

  @override
  Widget build(BuildContext bctx) {
    return AspectRatio(
      aspectRatio: doc.canvas.width / doc.canvas.height,
      child: LayoutBuilder(
        builder: (_, c) {
          final scale = c.maxWidth / doc.canvas.width;
          return ClipRect(
            child: Container(
              color: doc.canvas.backgroundColor,
              child: Stack(
                children: [
                  if (doc.canvas.backgroundImageUrl != null)
                    Positioned.fill(
                      child: _bgImage(doc.canvas.backgroundImageUrl!),
                    ),
                  for (final layer in doc.layers)
                    if (!layer.hidden) _renderLayer(layer, scale),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bgImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover);
    }
    if (url.startsWith('file://') || url.startsWith('/')) {
      final path = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return const SizedBox.shrink();
  }

  Widget _renderLayer(CardLayer layer, double scale) {
    final w = layer.width * scale;
    final h = layer.height * scale;
    Widget child;
    if (layer is TextLayer) {
      child = _textBody(layer, scale);
    } else if (layer is ShapeLayer) {
      child = _shapeBody(layer);
    } else if (layer is QrLayer) {
      child = _qrBody(layer, scale);
    } else if (layer is ImageLayer) {
      child = _imageBody(layer);
    } else {
      child = const SizedBox.shrink();
    }
    return Positioned(
      left: layer.x * scale,
      top: layer.y * scale,
      width: w,
      height: h,
      child: Opacity(
        opacity: layer.opacity.clamp(0.0, 1.0),
        child: layer.rotation == 0
            ? child
            : Transform.rotate(
                angle: layer.rotation * 3.1415926535 / 180,
                child: child,
              ),
      ),
    );
  }

  Widget _textBody(TextLayer t, double scale) {
    final resolved = context.apply(t.content);
    TextStyle style;
    try {
      style = GoogleFonts.getFont(
        t.fontFamily,
        fontSize: t.fontSize * scale,
        fontWeight: t.fontWeight,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        color: t.color,
        letterSpacing: t.letterSpacing * scale,
        height: t.lineHeight,
        decorationThickness: 0,
        shadows: t.shadow
            ? [
                Shadow(
                    color: const Color(0x66000000),
                    blurRadius: 8 * scale,
                    offset: Offset(0, 2 * scale)),
              ]
            : null,
      );
    } catch (_) {
      style = TextStyle(
        fontSize: t.fontSize * scale,
        fontWeight: t.fontWeight,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        color: t.color,
        letterSpacing: t.letterSpacing * scale,
        height: t.lineHeight,
        decorationThickness: 0,
      );
    }
    final textWidget = t.wrap
        ? Text(resolved,
            textAlign: t.textAlign, style: style, softWrap: true)
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _alignFromTextAlign(t.textAlign),
            child: Text(resolved, textAlign: t.textAlign, style: style),
          );
    if (t.backgroundColor == null) {
      return Align(
        alignment: _alignFromTextAlign(t.textAlign),
        child: textWidget,
      );
    }
    return Container(
      alignment: _alignFromTextAlign(t.textAlign),
      decoration: BoxDecoration(
        color: t.backgroundColor,
        borderRadius: BorderRadius.circular(t.backgroundRadius * scale),
      ),
      padding: EdgeInsets.symmetric(
          horizontal: 12 * scale, vertical: 6 * scale),
      child: textWidget,
    );
  }

  Widget _shapeBody(ShapeLayer s) {
    final border = s.borderWidth > 0
        ? Border.all(color: s.borderColor, width: s.borderWidth)
        : null;
    if (s.kind == ShapeKind.line) {
      return Container(
        decoration: BoxDecoration(color: s.fill),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: s.fill,
        border: border,
        borderRadius: s.kind == ShapeKind.ellipse
            ? null
            : BorderRadius.circular(s.borderRadius),
        shape: s.kind == ShapeKind.ellipse
            ? BoxShape.circle
            : BoxShape.rectangle,
      ),
    );
  }

  Widget _qrBody(QrLayer q, double scale) {
    final payload = context.qrPayload.isEmpty ? '-' : context.qrPayload;
    return ClipRRect(
      borderRadius: BorderRadius.circular(q.borderRadius * scale),
      child: Container(
        color: q.backgroundColor,
        padding: EdgeInsets.all(q.padding * scale),
        child: QrImageView(
          data: payload,
          version: QrVersions.auto,
          padding: EdgeInsets.zero,
          backgroundColor: q.backgroundColor,
          eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square, color: q.foregroundColor),
          dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: q.foregroundColor),
        ),
      ),
    );
  }

  Widget _imageBody(ImageLayer i) {
    final clip = i.borderRadius > 0
        ? BorderRadius.circular(i.borderRadius)
        : BorderRadius.zero;
    Widget img;
    if (i.url.startsWith('http')) {
      img = Image.network(i.url, fit: i.fit);
    } else if (i.url.startsWith('file://') || i.url.startsWith('/')) {
      final path = i.url.startsWith('file://') ? i.url.substring(7) : i.url;
      img = Image.file(File(path), fit: i.fit);
    } else {
      img = const SizedBox.shrink();
    }
    return ClipRRect(borderRadius: clip, child: img);
  }

  Alignment _alignFromTextAlign(TextAlign a) {
    switch (a) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }
}
