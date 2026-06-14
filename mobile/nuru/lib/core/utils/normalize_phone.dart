/// Pre-clean a phone value before validation.
///
/// Strips spaces, brackets, dots and hyphens. Preserves a leading '+' only;
/// any '+' that appears inside the number is removed.
String normalizePhoneNumber(dynamic value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return '';
  final keepsLeadingPlus = raw.startsWith('+');
  var cleaned = raw
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[().\-]'), '')
      .replaceAll('+', '');
  return keepsLeadingPlus ? '+$cleaned' : cleaned;
}
