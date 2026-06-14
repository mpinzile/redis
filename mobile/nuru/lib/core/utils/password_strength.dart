/// Shared password strength validation — mirrors web app and backend rules.
/// Requirements:
///   - At least 8 characters
///   - At least one uppercase letter
///   - At least one lowercase letter
///   - At least one number
///   - At least one special character
class PasswordStrength {
  static final _specials =
      RegExp(r'[!@#\$%\^&\*\(\),\.?":{}|<>_\-\+=\[\]\\\/~`]');

  static bool hasMinLength(String p) => p.length >= 8;
  static bool hasUpper(String p) => RegExp(r'[A-Z]').hasMatch(p);
  static bool hasLower(String p) => RegExp(r'[a-z]').hasMatch(p);
  static bool hasDigit(String p) => RegExp(r'\d').hasMatch(p);
  static bool hasSpecial(String p) => _specials.hasMatch(p);

  static bool isStrong(String p) =>
      hasMinLength(p) &&
      hasUpper(p) &&
      hasLower(p) &&
      hasDigit(p) &&
      hasSpecial(p);

  /// Returns null if strong, otherwise a human-readable error message.
  static String? firstError(String p) {
    if (!hasMinLength(p)) return 'Password must be at least 8 characters';
    if (!hasUpper(p)) return 'Password must include an uppercase letter';
    if (!hasLower(p)) return 'Password must include a lowercase letter';
    if (!hasDigit(p)) return 'Password must include a number';
    if (!hasSpecial(p)) return 'Password must include a special character';
    return null;
  }
}
