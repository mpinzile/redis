import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _keyLocale = 'app_locale';
  
  Locale _locale = const Locale('en');
  
  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isSwahili => _locale.languageCode == 'sw';
  bool get isEnglish => _locale.languageCode == 'en';

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLocale) ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    if (_locale.languageCode == languageCode) return;
    _locale = Locale(languageCode);
    notifyListeners(); // Notify immediately for instant UI update
    // Persist in background - don't block UI
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, languageCode);
  }

  void toggleLocale() {
    setLocale(isEnglish ? 'sw' : 'en');
  }
}
