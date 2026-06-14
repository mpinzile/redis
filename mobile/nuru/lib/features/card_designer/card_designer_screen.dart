// CardDesignerScreen - premium mobile invitation card designer.
//
// Editor architecture
//  - State holds a CardDesignDoc and a undo/redo stack (cap 50).
//  - Canvas is a Stack inside an InteractiveViewer. Each layer is wrapped in
//    a GestureDetector for selection + onPanUpdate to translate, and a
//    bottom-right resize handle for proportional resize.
//  - Bottom toolbar adds layers (text, shape, QR, image bg, dynamic field).
//  - Selection inspector is a draggable bottom sheet exposing per-type style
//    controls (font, size, weight, colour, alignment, shape fill/border, QR
//    colours, opacity, rotation, lock, hide, duplicate, delete).
//  - Layers sheet for reorder/hide/lock/rename/delete.
//  - Save callback returns the doc JSON to the host screen, which persists it
//    on events.invitation_content under the 'design_doc' key.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import 'card_renderer.dart';
import 'model.dart';

class CardDesignerScreen extends StatefulWidget {
  final CardDesignDoc initial;
  final CardRenderContext sampleContext;
  final ValueChanged<CardDesignDoc> onSave;

  const CardDesignerScreen({
    super.key,
    required this.initial,
    required this.sampleContext,
    required this.onSave,
  });

  @override
  State<CardDesignerScreen> createState() => _CardDesignerScreenState();
}

class _CardDesignerScreenState extends State<CardDesignerScreen> {
  late CardDesignDoc _doc;
  String? _selectedId;
  final List<CardDesignDoc> _undo = [];
  final List<CardDesignDoc> _redo = [];
  static const int _historyCap = 50;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.initial;
  }

  // ───── undo/redo / mutation helpers ─────

  void _commit(CardDesignDoc next) {
    setState(() {
      _undo.add(_doc);
      if (_undo.length > _historyCap) _undo.removeAt(0);
      _redo.clear();
      _doc = next;
      _dirty = true;
    });
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_doc);
      _doc = _undo.removeLast();
    });
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_doc);
      _doc = _redo.removeLast();
    });
  }

  CardLayer? get _selected =>
      _doc.layers.firstWhere((l) => l.id == _selectedId,
          orElse: () => _doc.layers.isEmpty
              ? throw StateError('no layers')
              : _doc.layers.first);

  void _replaceLayer(CardLayer next) {
    final list = _doc.layers
        .map((l) => l.id == next.id ? next : l)
        .toList(growable: false);
    _commit(_doc.copyWith(layers: list));
  }

  void _addLayer(CardLayer layer) {
    _commit(_doc.copyWith(layers: [..._doc.layers, layer]));
    setState(() => _selectedId = layer.id);
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    final list =
        _doc.layers.where((l) => l.id != _selectedId).toList(growable: false);
    _commit(_doc.copyWith(layers: list));
    setState(() => _selectedId = null);
  }

  void _duplicateSelected() {
    if (_selectedId == null) return;
    final l = _doc.layers.firstWhere((l) => l.id == _selectedId);
    final newId = '${l.id}-${DateTime.now().millisecondsSinceEpoch}';
    final dup = _cloneWithId(l, newId)
        .copyBase(x: l.x + 24, y: l.y + 24);
    _commit(_doc.copyWith(layers: [..._doc.layers, dup]));
    setState(() => _selectedId = dup.id);
  }

  void _bringForward() {
    if (_selectedId == null) return;
    final list = [..._doc.layers];
    final i = list.indexWhere((l) => l.id == _selectedId);
    if (i < 0 || i == list.length - 1) return;
    final tmp = list.removeAt(i);
    list.insert(i + 1, tmp);
    _commit(_doc.copyWith(layers: list));
  }

  void _sendBackward() {
    if (_selectedId == null) return;
    final list = [..._doc.layers];
    final i = list.indexWhere((l) => l.id == _selectedId);
    if (i <= 0) return;
    final tmp = list.removeAt(i);
    list.insert(i - 1, tmp);
    _commit(_doc.copyWith(layers: list));
  }

  CardLayer _cloneWithId(CardLayer l, String id) {
    if (l is TextLayer) return TextLayer(
        id: id, name: l.name, x: l.x, y: l.y, width: l.width, height: l.height,
        rotation: l.rotation, opacity: l.opacity, locked: l.locked, hidden: l.hidden,
        content: l.content, fontFamily: l.fontFamily, fontSize: l.fontSize,
        fontWeight: l.fontWeight, italic: l.italic, color: l.color,
        textAlign: l.textAlign, letterSpacing: l.letterSpacing,
        lineHeight: l.lineHeight, backgroundColor: l.backgroundColor,
        backgroundRadius: l.backgroundRadius, shadow: l.shadow);
    if (l is ShapeLayer) return ShapeLayer(
        id: id, name: l.name, x: l.x, y: l.y, width: l.width, height: l.height,
        rotation: l.rotation, opacity: l.opacity, locked: l.locked, hidden: l.hidden,
        kind: l.kind, fill: l.fill, borderColor: l.borderColor,
        borderWidth: l.borderWidth, borderRadius: l.borderRadius);
    if (l is QrLayer) return QrLayer(
        id: id, name: l.name, x: l.x, y: l.y, width: l.width, height: l.height,
        rotation: l.rotation, opacity: l.opacity, locked: l.locked, hidden: l.hidden,
        foregroundColor: l.foregroundColor, backgroundColor: l.backgroundColor,
        padding: l.padding, borderRadius: l.borderRadius);
    if (l is ImageLayer) return ImageLayer(
        id: id, name: l.name, x: l.x, y: l.y, width: l.width, height: l.height,
        rotation: l.rotation, opacity: l.opacity, locked: l.locked, hidden: l.hidden,
        url: l.url, fit: l.fit, borderRadius: l.borderRadius);
    return l;
  }

  // ───── add-layer helpers ─────

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  void _addText({String content = 'Tap to edit'}) {
    final cw = _doc.canvas.width;
    _addLayer(TextLayer(
      id: _nextId('text'),
      name: 'Text',
      x: cw * 0.1, y: _doc.canvas.height * 0.45,
      width: cw * 0.8, height: 120,
      content: content,
      fontSize: 40,
    ));
  }


  void _addShape(ShapeKind kind) {
    final cw = _doc.canvas.width;
    _addLayer(ShapeLayer(
      id: _nextId('shape'),
      name: kind == ShapeKind.ellipse ? 'Circle' : 'Rectangle',
      x: cw * 0.25, y: _doc.canvas.height * 0.4,
      width: cw * 0.5, height: 200,
      kind: kind,
      fill: const Color(0xFFD4AF37),
      borderRadius: kind == ShapeKind.rectangle ? 16 : 0,
    ));
  }

  void _addQr() {
    final has = _doc.layers.any((l) => l is QrLayer);
    if (has) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Card already has a QR layer'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final cw = _doc.canvas.width;
    _addLayer(QrLayer(
      id: _nextId('qr'),
      x: cw * 0.35, y: _doc.canvas.height * 0.65,
      width: cw * 0.3, height: cw * 0.3,
    ));
  }

  Future<void> _addBackgroundImage() async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (f == null) return;
      final url = 'file://${f.path}';
      _commit(_doc.copyWith(
        canvas: _doc.canvas.copyWith(backgroundImageUrl: url),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load image: $e')));
      }
    }
  }

  /// Standalone image layer - draggable, resizable, rotatable. NOT a
  /// background. Place anywhere on the canvas; reorder via the layers panel.
  Future<void> _addImage() async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (f == null) return;
      final cw = _doc.canvas.width;
      _addLayer(ImageLayer(
        id: _nextId('image'),
        name: 'Photo',
        x: cw * 0.2,
        y: _doc.canvas.height * 0.3,
        width: cw * 0.6,
        height: cw * 0.6,
        url: 'file://${f.path}',
        fit: BoxFit.cover,
        borderRadius: 16,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load image: $e')));
      }
    }
  }

  // ───── canvas gestures ─────

  void _onLayerDrag(CardLayer l, DragUpdateDetails d, double scale) {
    if (l.locked) return;
    final next = l.copyBase(
      x: (l.x + d.delta.dx / scale).clamp(0, _doc.canvas.width - 10),
      y: (l.y + d.delta.dy / scale).clamp(0, _doc.canvas.height - 10),
    );
    _replaceLayer(next);
  }

  void _onResize(CardLayer l, DragUpdateDetails d, double scale) {
    if (l.locked) return;
    final next = l.copyBase(
      width: math.max(40, l.width + d.delta.dx / scale),
      height: math.max(40, l.height + d.delta.dy / scale),
    );
    _replaceLayer(next);
  }

  // ───── build ─────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvoked: (didPop) async {
        if (didPop || !_dirty) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Discard changes?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Your unsaved design changes will be lost.',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          setState(() => _dirty = false);
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(child: _canvas()),
              if (_selectedId != null) _selectionBar(),
              _bottomToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.undo_rounded,
                color: _undo.isEmpty ? Colors.white24 : Colors.white),
            onPressed: _undo.isEmpty ? null : _undoOnce,
          ),
          IconButton(
            icon: Icon(Icons.redo_rounded,
                color: _redo.isEmpty ? Colors.white24 : Colors.white),
            onPressed: _redo.isEmpty ? null : _redoOnce,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.layers_outlined, color: Colors.white),
            onPressed: _showLayersSheet,
          ),
          IconButton(
            icon: const Icon(Icons.remove_red_eye_outlined,
                color: Colors.white),
            onPressed: _showPreview,
            tooltip: 'Preview',
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () {
              widget.onSave(_doc);
              setState(() => _dirty = false);
              Navigator.of(context).maybePop();
            },
            child: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _canvas() {
    return GestureDetector(
      onTap: () => setState(() => _selectedId = null),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: AspectRatio(
            aspectRatio: _doc.canvas.width / _doc.canvas.height,
            child: LayoutBuilder(builder: (_, c) {
              final scale = c.maxWidth / _doc.canvas.width;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0x66000000),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Render via the same widget guests will see.
                      CardRenderer(
                        doc: _doc,
                        context: widget.sampleContext,
                      ),
                      // Selection overlays
                      for (final layer in _doc.layers)
                        if (!layer.hidden) _layerHandle(layer, scale),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _layerHandle(CardLayer layer, double scale) {
    final selected = layer.id == _selectedId;
    return Positioned(
      left: layer.x * scale,
      top: layer.y * scale,
      width: layer.width * scale,
      height: layer.height * scale,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _selectedId = layer.id),
        onDoubleTap: () {
          setState(() => _selectedId = layer.id);
          if (layer is TextLayer) _showStyleSheet();
        },
        onPanStart: (_) {
          if (!selected) setState(() => _selectedId = layer.id);
        },
        onPanUpdate: (d) {
          if (selected) _onLayerDrag(layer, d, scale);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: selected
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                  ),
                ),
              ),
            ),
            if (selected) ...[
              Positioned(
                right: -10, bottom: -10,
                child: GestureDetector(
                  onPanUpdate: (d) => _onResize(layer, d, scale),
                  child: _handleDot(Icons.open_in_full_rounded),
                ),
              ),
              Positioned(
                right: -10, top: -10,
                child: GestureDetector(
                  onPanUpdate: (d) => _onRotate(layer, d, scale),
                  child: _handleDot(Icons.rotate_right_rounded),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _handleDot(IconData icon) => Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, size: 12, color: Colors.white),
      );

  void _onRotate(CardLayer l, DragUpdateDetails d, double scale) {
    if (l.locked) return;
    // Drag delta is converted to a rotation delta. 4° per CSS pixel of
    // horizontal drag feels natural on phone screens.
    final next =
        l.copyBase(rotation: (l.rotation + d.delta.dx * 0.8) % 360);
    _replaceLayer(next);
  }

  Widget _selectionBar() {
    final l = _doc.layers.firstWhere((l) => l.id == _selectedId,
        orElse: () => _doc.layers.first);
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text('${l.name}  •  ${l.type.toUpperCase()}',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decorationThickness: 0)),
          ),
          IconButton(
            icon: Icon(l.locked ? Icons.lock : Icons.lock_open,
                color: Colors.white, size: 20),
            onPressed: () => _replaceLayer(l.copyBase(locked: !l.locked)),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded,
                color: Colors.white, size: 20),
            onPressed: _duplicateSelected,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded,
                color: Colors.white, size: 20),
            onPressed: _bringForward,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward_rounded,
                color: Colors.white, size: 20),
            onPressed: _sendBackward,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded,
                color: Colors.white, size: 20),
            onPressed: _showStyleSheet,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 20),
            onPressed: _deleteSelected,
          ),
        ],
      ),
    );
  }

  Widget _bottomToolbar() {
    Widget tool(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 64, height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        decorationThickness: 0)),
              ],
            ),
          ),
        );
    return Container(
      color: const Color(0xFF111111),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tool(Icons.text_fields_rounded, 'Text', () => _addText()),
            tool(Icons.code_rounded, 'Field', _showDynamicSheet),
            tool(Icons.add_photo_alternate_outlined, 'Photo', _addImage),
            tool(Icons.qr_code_2_rounded, 'QR', _addQr),
            tool(Icons.crop_square_rounded, 'Rect',
                () => _addShape(ShapeKind.rectangle)),
            tool(Icons.circle_outlined, 'Circle',
                () => _addShape(ShapeKind.ellipse)),
            tool(Icons.wallpaper_rounded, 'Background', _addBackgroundImage),
            tool(Icons.palette_outlined, 'Canvas', _showCanvasSheet),
            tool(Icons.aspect_ratio_rounded, 'Size', _showSizeSheet),
          ],
        ),
      ),
    );
  }

  // ───── sheets ─────

  void _showDynamicSheet() {
    const fields = <(String, String)>[
      ('Guest name', '{{guest_name}}'),
      ('Event title', '{{event_title}}'),
      ('Event date', '{{event_date}}'),
      ('Event time', '{{event_time}}'),
      ('Location', '{{event_location}}'),
      ('Organizer', '{{organizer_name}}'),
      ('Invite code', '{{invite_code}}'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Insert dynamic field',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decorationThickness: 0)),
            ),
            for (final f in fields)
              ListTile(
                title: Text(f.$1, style: const TextStyle(color: Colors.white)),
                subtitle: Text(f.$2,
                    style: const TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(context);
                  _addText(content: f.$2);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showCanvasSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (_) => _CanvasStyleSheet(
        canvas: _doc.canvas,
        onChanged: (next) => _commit(_doc.copyWith(canvas: next)),
      ),
    );
  }

  void _showSizeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Canvas size',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decorationThickness: 0)),
            ),
            for (final preset in [
              ('Portrait  1080×1350', CanvasSpec.portrait),
              ('Square  1080×1080', CanvasSpec.square),
              ('Story  1080×1920', CanvasSpec.story),
            ])
              ListTile(
                title: Text(preset.$1,
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _commit(_doc.copyWith(
                      canvas: preset.$2.copyWith(
                          backgroundColor: _doc.canvas.backgroundColor,
                          backgroundImageUrl: _doc.canvas.backgroundImageUrl)));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: SizedBox(
            height: 480,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Layers',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decorationThickness: 0)),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _doc.layers.length,
                    onReorder: (oldI, newI) {
                      final list = [..._doc.layers];
                      if (newI > oldI) newI -= 1;
                      final item = list.removeAt(oldI);
                      list.insert(newI, item);
                      _commit(_doc.copyWith(layers: list));
                      setSheet(() {});
                    },
                    itemBuilder: (_, i) {
                      // Render top of stack at top of list (reverse).
                      final layer = _doc.layers[_doc.layers.length - 1 - i];
                      return ListTile(
                        key: ValueKey(layer.id),
                        leading: Icon(_iconFor(layer), color: Colors.white70),
                        title: Text(layer.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(layer.type,
                            style: const TextStyle(color: Colors.white54)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                  layer.hidden
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: Colors.white70, size: 20),
                              onPressed: () {
                                _replaceLayer(
                                    layer.copyBase(hidden: !layer.hidden));
                                setSheet(() {});
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                  layer.locked
                                      ? Icons.lock
                                      : Icons.lock_open_rounded,
                                  color: Colors.white70, size: 20),
                              onPressed: () {
                                _replaceLayer(
                                    layer.copyBase(locked: !layer.locked));
                                setSheet(() {});
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedId = layer.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  IconData _iconFor(CardLayer l) {
    if (l is TextLayer) return Icons.text_fields_rounded;
    if (l is ShapeLayer) {
      return l.kind == ShapeKind.ellipse
          ? Icons.circle_outlined
          : Icons.crop_square_rounded;
    }
    if (l is QrLayer) return Icons.qr_code_2_rounded;
    if (l is ImageLayer) return Icons.image_outlined;
    return Icons.layers;
  }

  void _showStyleSheet() {
    final l = _selected;
    if (l == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        if (l is TextLayer) {
          return _TextStyleSheet(
            layer: l,
            onChanged: _replaceLayer,
          );
        }
        if (l is ShapeLayer) {
          return _ShapeStyleSheet(layer: l, onChanged: _replaceLayer);
        }
        if (l is QrLayer) {
          return _QrStyleSheet(layer: l, onChanged: _replaceLayer);
        }
        if (l is ImageLayer) {
          return _ImageStyleSheet(layer: l, onChanged: _replaceLayer);
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Full-screen preview using the same renderer guests will see at download.
  void _showPreview() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Preview'),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: AspectRatio(
                aspectRatio: _doc.canvas.width / _doc.canvas.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CardRenderer(
                    doc: _doc,
                    context: widget.sampleContext,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

// ───────────────────────── style sheets ─────────────────────────

const _palette = <Color>[
  Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFD4AF37),
  Color(0xFFB22222), Color(0xFF1F4E79), Color(0xFF2E7D32),
  Color(0xFF6A1B9A), Color(0xFFEF6C00), Color(0xFF455A64),
  Color(0xFFF5F0E8), Color(0xFF8B5E34), Color(0xFFC0392B),
];

class _Swatches extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color> onPick;
  const _Swatches({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        for (final c in _palette)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected?.value == c.value
                        ? Colors.white
                        : const Color(0x33FFFFFF),
                    width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _CanvasStyleSheet extends StatelessWidget {
  final CanvasSpec canvas;
  final ValueChanged<CanvasSpec> onChanged;
  const _CanvasStyleSheet({required this.canvas, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Background colour',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decorationThickness: 0)),
            const SizedBox(height: 12),
            _Swatches(
              selected: canvas.backgroundColor,
              onPick: (c) => onChanged(canvas.copyWith(backgroundColor: c)),
            ),
            if (canvas.backgroundImageUrl != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () =>
                    onChanged(canvas.copyWith(clearBackgroundImage: true)),
                icon: const Icon(Icons.close, color: Colors.redAccent),
                label: const Text('Remove background image',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextStyleSheet extends StatefulWidget {
  final TextLayer layer;
  final ValueChanged<CardLayer> onChanged;
  const _TextStyleSheet({required this.layer, required this.onChanged});
  @override
  State<_TextStyleSheet> createState() => _TextStyleSheetState();
}

class _TextStyleSheetState extends State<_TextStyleSheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.layer.content);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _push(TextLayer next) => widget.onChanged(next);

  @override
  Widget build(BuildContext context) {
    final l = widget.layer;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Content',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: null,
                style: const TextStyle(
                    color: Colors.white, decorationThickness: 0),
                maxLines: 3,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF222222),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
                onChanged: (v) => _push(l.copyWith(content: v)),
              ),
              const SizedBox(height: 16),
              _row('Font size', '${l.fontSize.round()}'),
              Slider(
                min: 12, max: 160, value: l.fontSize,
                onChanged: (v) => _push(l.copyWith(fontSize: v)),
              ),
              _row('Letter spacing', l.letterSpacing.toStringAsFixed(1)),
              Slider(
                min: -2, max: 12, value: l.letterSpacing,
                onChanged: (v) => _push(l.copyWith(letterSpacing: v)),
              ),
              _row('Line height', l.lineHeight.toStringAsFixed(2)),
              Slider(
                min: 0.8, max: 2.4, value: l.lineHeight,
                onChanged: (v) => _push(l.copyWith(lineHeight: v)),
              ),
              _row('Opacity', '${(l.opacity * 100).round()}%'),
              Slider(
                min: 0.05, max: 1, value: l.opacity,
                onChanged: (v) => _push(l.copyWith(opacity: v)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final w in [
                    FontWeight.w300,
                    FontWeight.w500,
                    FontWeight.w700,
                    FontWeight.w900,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(w.value.toString()),
                        selected: l.fontWeight == w,
                        onSelected: (_) => _push(l.copyWith(fontWeight: w)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: const Text('Italic'),
                      selected: l.italic,
                      onSelected: (v) => _push(l.copyWith(italic: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final a in [
                    TextAlign.left,
                    TextAlign.center,
                    TextAlign.right,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Icon(
                            a == TextAlign.left
                                ? Icons.format_align_left
                                : a == TextAlign.center
                                    ? Icons.format_align_center
                                    : Icons.format_align_right,
                            size: 16),
                        selected: l.textAlign == a,
                        onSelected: (_) => _push(l.copyWith(textAlign: a)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Text colour',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              _Swatches(
                selected: l.color,
                onPick: (c) => _push(l.copyWith(color: c)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Shadow'),
                    selected: l.shadow,
                    onSelected: (v) => _push(l.copyWith(shadow: v)),
                  ),
                  ChoiceChip(
                    label: Text(l.wrap ? 'Wrap lines' : 'Auto-fit'),
                    selected: l.wrap,
                    onSelected: (v) => _push(l.copyWith(wrap: v)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decorationThickness: 0)),
            Text(b,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    decorationThickness: 0)),
          ],
        ),
      );
}

class _ShapeStyleSheet extends StatelessWidget {
  final ShapeLayer layer;
  final ValueChanged<CardLayer> onChanged;
  const _ShapeStyleSheet({required this.layer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Fill colour',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              _Swatches(
                selected: layer.fill,
                onPick: (c) => onChanged(layer.copyWith(fill: c)),
              ),
              const SizedBox(height: 12),
              const Text('Border colour',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              _Swatches(
                selected: layer.borderColor,
                onPick: (c) => onChanged(layer.copyWith(borderColor: c)),
              ),
              const SizedBox(height: 8),
              Text('Border width  ${layer.borderWidth.round()}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0, max: 24, value: layer.borderWidth,
                onChanged: (v) => onChanged(layer.copyWith(borderWidth: v)),
              ),
              Text('Corner radius  ${layer.borderRadius.round()}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0, max: 200, value: layer.borderRadius,
                onChanged: (v) => onChanged(layer.copyWith(borderRadius: v)),
              ),
              Text('Opacity  ${(layer.opacity * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0.05, max: 1, value: layer.opacity,
                onChanged: (v) => onChanged(layer.copyWith(opacity: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrStyleSheet extends StatelessWidget {
  final QrLayer layer;
  final ValueChanged<CardLayer> onChanged;
  const _QrStyleSheet({required this.layer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final small = layer.width < 200;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (small)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFB300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'QR is small · guests may struggle to scan it. Resize on canvas.',
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 12,
                        decorationThickness: 0),
                  ),
                ),
              const Text('QR colour',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              _Swatches(
                selected: layer.foregroundColor,
                onPick: (c) => onChanged(layer.copyWith(foregroundColor: c)),
              ),
              const SizedBox(height: 12),
              const Text('Background',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              _Swatches(
                selected: layer.backgroundColor,
                onPick: (c) => onChanged(layer.copyWith(backgroundColor: c)),
              ),
              Text('Padding  ${layer.padding.round()}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0, max: 60, value: layer.padding,
                onChanged: (v) => onChanged(layer.copyWith(padding: v)),
              ),
              Text('Corner radius  ${layer.borderRadius.round()}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0, max: 80, value: layer.borderRadius,
                onChanged: (v) => onChanged(layer.copyWith(borderRadius: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageStyleSheet extends StatelessWidget {
  final ImageLayer layer;
  final ValueChanged<CardLayer> onChanged;
  const _ImageStyleSheet({required this.layer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Image fit',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final fit in [
                    BoxFit.cover,
                    BoxFit.contain,
                    BoxFit.fill,
                    BoxFit.fitWidth,
                    BoxFit.fitHeight,
                  ])
                    ChoiceChip(
                      label: Text(fit.name),
                      selected: layer.fit == fit,
                      onSelected: (_) => onChanged(layer.copyWith(fit: fit)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Corner radius  ${layer.borderRadius.round()}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0, max: 200, value: layer.borderRadius,
                onChanged: (v) =>
                    onChanged(layer.copyWith(borderRadius: v)),
              ),
              Text('Opacity  ${(layer.opacity * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: 0.05, max: 1, value: layer.opacity,
                onChanged: (v) => onChanged(layer.copyWith(opacity: v)),
              ),
              Text('Rotation  ${layer.rotation.round()}°',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decorationThickness: 0)),
              Slider(
                min: -180, max: 180, value: layer.rotation.clamp(-180, 180),
                onChanged: (v) => onChanged(layer.copyWith(rotation: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
