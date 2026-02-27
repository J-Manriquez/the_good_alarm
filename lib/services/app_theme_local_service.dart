import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_theme_model.dart';

class AppThemeLocalService {
  static const _themesKey = 'app_themes_v1';
  static const _activeThemeIdKey = 'app_active_theme_id_v1';

  Future<List<AppThemeModel>> loadThemes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themesKey);
    if (raw == null || raw.trim().isEmpty) {
      return [AppThemeModel.defaultDark()];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [AppThemeModel.defaultDark()];
      final items = decoded.whereType<Map>().map((m) {
        return AppThemeModel.fromMap(Map<String, dynamic>.from(m));
      }).toList();
      if (items.isEmpty) return [AppThemeModel.defaultDark()];
      return items;
    } catch (_) {
      return [AppThemeModel.defaultDark()];
    }
  }

  Future<void> saveThemes(List<AppThemeModel> themes) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(themes.map((t) => t.toMap()).toList());
    await prefs.setString(_themesKey, payload);
  }

  Future<String?> loadActiveThemeId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeThemeIdKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  Future<void> saveActiveThemeId(String? themeId) async {
    final prefs = await SharedPreferences.getInstance();
    if (themeId == null || themeId.trim().isEmpty) {
      await prefs.remove(_activeThemeIdKey);
      return;
    }
    await prefs.setString(_activeThemeIdKey, themeId);
  }
}

