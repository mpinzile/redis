import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';

/// Modern, iOS-style emoji picker used globally across the app.
///
/// Fully responsive - adapts grid columns, font sizes, and rail width to the
/// available constraints to avoid pixel-overflow on small phones. The search
/// input has no inner border (the surrounding pill provides the only border).
class NuruEmojiPicker extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback? onClose;
  final double height;

  const NuruEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.onClose,
    this.height = 380,
  });

  /// Convenience: open the picker as a draggable modal sheet.
  static Future<String?> show(
    BuildContext context, {
    ValueChanged<String>? onEmojiSelected,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Material(
          color: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: NuruEmojiPicker(
            height: MediaQuery.of(ctx).size.height * 0.55,
            onEmojiSelected: (e) {
              onEmojiSelected?.call(e);
              Navigator.of(ctx).pop(e);
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  @override
  State<NuruEmojiPicker> createState() => _NuruEmojiPickerState();
}

class _NuruEmojiPickerState extends State<NuruEmojiPicker> {
  static const _kRecentKey = 'emoji_recent';
  static const _kFrequentKey = 'emoji_frequent';

  int _categoryIndex = 0;
  String _query = '';
  List<String> _recent = const [];
  Map<String, int> _frequencies = const {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_kRecentKey) ?? const [];
    final freqRaw = prefs.getStringList(_kFrequentKey) ?? const [];
    final freq = <String, int>{};
    for (final entry in freqRaw) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        freq[parts[0]] = int.tryParse(parts[1]) ?? 1;
      }
    }
    if (mounted) setState(() { _recent = recent; _frequencies = freq; });
  }

  Future<void> _trackUsage(String emoji) async {
    final prefs = await SharedPreferences.getInstance();
    final newRecent = [emoji, ..._recent.where((e) => e != emoji)].take(32).toList();
    final newFreq = Map<String, int>.from(_frequencies);
    newFreq[emoji] = (newFreq[emoji] ?? 0) + 1;
    await prefs.setStringList(_kRecentKey, newRecent);
    await prefs.setStringList(
      _kFrequentKey,
      newFreq.entries.map((e) => '${e.key}|${e.value}').toList(),
    );
    if (mounted) setState(() { _recent = newRecent; _frequencies = newFreq; });
  }

  List<String> get _frequentlyUsed {
    final entries = _frequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(7).map((e) => e.key).toList();
    if (top.isNotEmpty) return top;
    return const ['😂', '❤️', '🎉', '🙏', '😍', '🔥', '👍'];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Compact mode for narrow phones (most cases)
        final compact = w < 420;
        final veryShort = constraints.maxHeight < 280;
        final railWidth = compact ? 76.0 : 104.0;
        // Pick a grid column count from the available area for the right pane
        final gridArea = (w - railWidth - 16).clamp(120.0, double.infinity);
        final tile = compact ? 36.0 : 40.0;
        final columns = (gridArea / tile).floor().clamp(5, 10).toInt();

        final cat = _categories[_categoryIndex];
        final emojis = cat.emojis;

        return Container(
          height: widget.height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Top: search + frequently used + close
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 8 : 12, veryShort ? 6 : 8, compact ? 8 : 12, veryShort ? 6 : 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: veryShort ? 34 : 38,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFEDEDEF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, size: 18, color: Color(0xFF8E8E93)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setState(() => _query = v),
                                cursorColor: AppColors.primary,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  decoration: TextDecoration.none,
                                  decorationThickness: 0,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search',
                                  hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF8E8E93)),
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!compact && !veryShort) ...[
                      Text('Frequently Used',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                    ],
                    if (!veryShort)
                      ..._frequentlyUsed.take(compact ? 2 : 4).map((e) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: GestureDetector(
                              onTap: () => _onEmojiTap(e),
                              child: Text(e, style: const TextStyle(fontSize: 15)),
                            ),
                          )),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFEDEDEF)),
                        ),
                        child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),

              // Body: side rail + grid
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Side rail (responsive width, scrollable)
                    SizedBox(
                      width: railWidth,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        itemCount: _categories.length,
                        itemBuilder: (_, i) {
                          final c = _categories[i];
                          final selected = _categoryIndex == i;
                          return GestureDetector(
                            onTap: () => setState(() => _categoryIndex = i),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 8, compact ? 6 : 10, 8),
                              decoration: BoxDecoration(
                                color: selected ? const Color(0xFFFFF7E0) : Colors.transparent,
                                border: Border(
                                  right: BorderSide(
                                    color: selected ? AppColors.primary : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(c.icon,
                                      size: 16,
                                      color: selected ? AppColors.primary : AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(c.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                                        )),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Vertical divider
                    Container(width: 1, color: const Color(0xFFF0F0F2)),
                    // Grid
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: Text(cat.label,
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                              itemCount: emojis.length,
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => _onEmojiTap(emojis[i]),
                                child: Center(
                                  child: Text(emojis[i], style: TextStyle(fontSize: compact ? 20 : 22)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom action bar - Recent + Frequently Used (no GIF)
              if (!veryShort)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF0F0F2))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Recent',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const Spacer(),
                      const Icon(Icons.sentiment_satisfied_outlined, size: 16, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Frequently Used',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _onEmojiTap(String emoji) {
    _trackUsage(emoji);
    widget.onEmojiSelected(emoji);
  }
}

class _Category {
  final String label;
  final IconData icon;
  final List<String> emojis;
  const _Category(this.label, this.icon, this.emojis);
}

const _categories = <_Category>[
  _Category('Smileys', Icons.sentiment_satisfied_outlined, [
    '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙',
    '😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥',
    '😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓',
    '🧐','😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣',
    '😞','😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','☠️','💩','🤡','👹','👺','👻','👽','👾',
  ]),
  _Category('People', Icons.person_outline_rounded, [
    '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍',
    '👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦵','🦿','🦶','👂',
    '🧒','👦','👧','🧑','👨','👩','🧓','👴','👵','👮','🕵️','💂','👷','🤴','👸','👳','👲','🧕','🤵','👰',
  ]),
  _Category('Nature', Icons.eco_outlined, [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔','🐧','🐦','🐤','🐣',
    '🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🦟','🦗','🕷️','🐢','🐍','🦎',
    '🌵','🎄','🌲','🌳','🌴','🌱','🌿','☘️','🍀','🎍','🎋','🍃','🍂','🍁','🌾','🌺','🌻','🌹','🥀','🌷',
  ]),
  _Category('Food', Icons.local_cafe_outlined, [
    '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑',
    '🥦','🥬','🥒','🌶️','🫑','🌽','🥕','🫒','🧄','🧅','🥔','🍠','🥐','🥖','🍞','🥨','🥯','🥞','🧇','🧀',
    '☕','🍵','🍶','🍾','🍷','🍸','🍹','🍺','🍻','🥂','🥃','🥤','🧋','🧃','🧉','🍽️','🥢','🥄','🍴','🧂',
  ]),
  _Category('Activities', Icons.sports_basketball_outlined, [
    '⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🏑','🥍','🏏','🪃','🥅','⛳',
    '🪁','🏹','🎣','🤿','🥊','🥋','🎽','🛹','🛼','🛷','⛸️','🥌','🎿','⛷️','🏂','🪂','🏋️','🤼','🤸','🤺',
  ]),
  _Category('Travel', Icons.flight_outlined, [
    '🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🛵','🏍️','🛺','🚲','🛴','🛹',
    '🚂','🚆','🚇','🚊','🚉','✈️','🛫','🛬','🛩️','🚁','🚟','🚠','🚡','🛰️','🚀','🛸','🛶','⛵','🚤','🛥️',
  ]),
  _Category('Objects', Icons.lightbulb_outline, [
    '⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','🖲️','🕹️','🗜️','💽','💾','💿','📀','📼','📷','📸','📹','🎥','📽️',
    '🎬','📞','☎️','📟','📠','📺','📻','🎙️','🎚️','🎛️','🧭','⏱️','⏲️','⏰','🕰️','⌛','⏳','📡','🔋','🔌',
  ]),
  _Category('Symbols', Icons.favorite_border_rounded, [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','☮️',
    '✝️','☪️','🕉️','☸️','✡️','🔯','🕎','☯️','☦️','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐',
  ]),
  _Category('Flags', Icons.flag_outlined, [
    '🏁','🚩','🎌','🏴','🏳️','🏳️‍🌈','🏳️‍⚧️','🏴‍☠️','🇹🇿','🇰🇪','🇺🇬','🇷🇼','🇿🇦','🇳🇬','🇬🇭','🇪🇬','🇺🇸','🇬🇧','🇫🇷','🇩🇪',
    '🇮🇹','🇪🇸','🇨🇳','🇯🇵','🇰🇷','🇮🇳','🇧🇷','🇲🇽','🇨🇦','🇦🇺','🇷🇺','🇸🇦','🇦🇪','🇹🇷','🇳🇱','🇸🇪','🇳🇴','🇵🇱','🇵🇹','🇨🇭',
  ]),
];
