import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// ExpandingSearchAction - AppBar action that toggles between a search icon
/// and an inline debounced text input. Use as one of the [actions] on a
/// [NuruSubPageAppBar] / [AppBar].
///
/// Behaviour:
///  - Tap the icon → expands into a rounded input that takes the available
///    horizontal space in the AppBar.
///  - Typing is debounced (default 300ms) before [onChanged] is called.
///  - Clearing/closing emits an empty string so callers can reset filters.
class ExpandingSearchAction extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hintText;
  final Duration debounce;

  const ExpandingSearchAction({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Search…',
    this.debounce = const Duration(milliseconds: 300),
  });

  @override
  State<ExpandingSearchAction> createState() => _ExpandingSearchActionState();
}

class _ExpandingSearchActionState extends State<ExpandingSearchAction> {
  bool _open = false;
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _open = widget.value.isNotEmpty;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => widget.onChanged(v));
  }

  void _expand() {
    setState(() => _open = true);
    Future.delayed(const Duration(milliseconds: 30), () => _focus.requestFocus());
  }

  void _collapse() {
    _ctrl.clear();
    widget.onChanged('');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return IconButton(
        icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary, size: 22),
        tooltip: 'Search',
        onPressed: _expand,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, minWidth: 180),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _onTextChanged,
          onSubmitted: widget.onChanged,
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textTertiary),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
              onPressed: _collapse,
              splashRadius: 18,
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.4)),
            ),
          ),
        ),
      ),
    );
  }
}
