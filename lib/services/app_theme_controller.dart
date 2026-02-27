import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_theme_model.dart';
import '../models/sistema_model.dart';
import 'app_theme_firebase_service.dart';
import 'app_theme_local_service.dart';
import 'sistema_firebase_service.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController({
    AppThemeLocalService? local,
    AppThemeFirebaseService? cloud,
    SistemaFirebaseService? sistemaCloud,
  })  : _local = local ?? AppThemeLocalService(),
        _cloud = cloud ?? AppThemeFirebaseService(),
        _sistemaCloud = sistemaCloud ?? SistemaFirebaseService();

  final AppThemeLocalService _local;
  final AppThemeFirebaseService _cloud;
  final SistemaFirebaseService _sistemaCloud;

  bool _initialized = false;
  bool get initialized => _initialized;

  List<AppThemeModel> _themes = const [];
  List<AppThemeModel> get themes => List.unmodifiable(_themes);

  String? _activeThemeId;
  String? get activeThemeId => _activeThemeId;

  ThemeData _themeData = AppThemeModel.defaultDark().toThemeData();
  ThemeData get themeData => _themeData;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<AppThemeModel>>? _themesCloudSub;
  StreamSubscription<SistemaModel?>? _sistemaCloudSub;

  Future<void> init() async {
    if (_initialized) return;
    final loaded = await _local.loadThemes();
    final activeId = await _local.loadActiveThemeId();

    _themes = loaded.where((t) => t.id.trim().isNotEmpty).toList();
    if (_themes.isEmpty) _themes = [AppThemeModel.defaultDark()];

    if (activeId != null && _themes.any((t) => t.id == activeId)) {
      _activeThemeId = activeId;
    } else {
      _activeThemeId = _themes.first.id;
      await _local.saveActiveThemeId(_activeThemeId);
    }

    _rebuildThemeData();
    _initialized = true;
    notifyListeners();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _handleAuthChanged(user);
    });

    await _handleAuthChanged(FirebaseAuth.instance.currentUser);
  }

  Future<void> _handleAuthChanged(User? user) async {
    await stopCloudSync();
    if (user == null) return;
    final deviceName = await _getDeviceName();
    await startCloudSync(userId: user.uid, deviceName: deviceName);
  }

  Future<String> _getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_name');
    if (deviceName != null && deviceName.trim().isNotEmpty) return deviceName.trim();
    return 'dispositivo_sin_nombre';
  }

  AppThemeModel get activeTheme {
    final id = _activeThemeId;
    final match = (id == null) ? null : _themes.where((t) => t.id == id).toList();
    if (match != null && match.isNotEmpty) return match.first;
    return _themes.isNotEmpty ? _themes.first : AppThemeModel.defaultDark();
  }

  Future<void> setActiveThemeId(String themeId) async {
    if (themeId.trim().isEmpty) return;
    if (!_themes.any((t) => t.id == themeId)) return;
    _activeThemeId = themeId;
    await _local.saveActiveThemeId(themeId);
    _rebuildThemeData();
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final deviceName = await _getDeviceName();
      await assignThemeToDevice(
        userId: user.uid,
        deviceName: deviceName,
        themeId: themeId,
      );
    }
  }

  Future<AppThemeModel> createTheme({
    required String name,
    AppThemeModel? base,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'theme_$now';
    final seed = base ?? activeTheme;
    final theme = seed.copyWith(
      id: id,
      name: name.trim().isEmpty ? 'Tema $now' : name.trim(),
      updatedAtMs: now,
    );
    _themes = [..._themes, theme];
    await _local.saveThemes(_themes);
    _rebuildThemeData();
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final deviceName = await _getDeviceName();
      await _cloud.upsertTheme(userId: user.uid, theme: theme, deviceId: deviceName);
    }
    return theme;
  }

  Future<AppThemeModel?> duplicateTheme(String sourceThemeId, {String? name}) async {
    final src = _themes.where((t) => t.id == sourceThemeId).toList();
    if (src.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final duplicated = src.first.copyWith(
      id: 'theme_$now',
      name: (name?.trim().isNotEmpty == true) ? name!.trim() : '${src.first.name} (copia)',
      updatedAtMs: now,
    );
    _themes = [..._themes, duplicated];
    await _local.saveThemes(_themes);
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final deviceName = await _getDeviceName();
      await _cloud.upsertTheme(userId: user.uid, theme: duplicated, deviceId: deviceName);
    }
    return duplicated;
  }

  Future<void> updateTheme(AppThemeModel updated) async {
    final idx = _themes.indexWhere((t) => t.id == updated.id);
    if (idx == -1) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = updated.copyWith(updatedAtMs: now);
    final copy = [..._themes];
    copy[idx] = next;
    _themes = copy;
    await _local.saveThemes(_themes);
    _rebuildThemeData();
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final deviceName = await _getDeviceName();
      await _cloud.upsertTheme(userId: user.uid, theme: next, deviceId: deviceName);
    }
  }

  Future<void> deleteTheme(String themeId) async {
    if (themeId == AppThemeModel.defaultDark().id) return;
    final nextThemes = _themes.where((t) => t.id != themeId).toList();
    if (nextThemes.isEmpty) return;
    _themes = nextThemes;
    if (_activeThemeId == themeId) {
      _activeThemeId = _themes.first.id;
      await _local.saveActiveThemeId(_activeThemeId);
    }
    await _local.saveThemes(_themes);
    _rebuildThemeData();
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final deviceName = await _getDeviceName();
      await _cloud.deleteTheme(userId: user.uid, themeId: themeId, deviceId: deviceName);
    }
  }

  Future<void> startCloudSync({
    required String userId,
    required String deviceName,
  }) async {
    _themesCloudSub = _cloud.watchThemes(userId).listen((remoteThemes) async {
      await _mergeRemoteThemes(userId: userId, deviceName: deviceName, remoteThemes: remoteThemes);
    });

    _sistemaCloudSub = _sistemaCloud.watchSistema(userId).listen((sistema) async {
      final id = sistema?.activeThemeIdForDevice(deviceName);
      if (id == null || id.trim().isEmpty) return;
      if (_themes.any((t) => t.id == id) && _activeThemeId != id) {
        _activeThemeId = id;
        await _local.saveActiveThemeId(id);
        _rebuildThemeData();
        notifyListeners();
      }
    });

    final sistema = await _sistemaCloud.getSistema(userId);
    final remoteActive = sistema?.activeThemeIdForDevice(deviceName);
    if (remoteActive != null &&
        remoteActive.trim().isNotEmpty &&
        _themes.any((t) => t.id == remoteActive) &&
        _activeThemeId != remoteActive) {
      _activeThemeId = remoteActive;
      await _local.saveActiveThemeId(remoteActive);
      _rebuildThemeData();
      notifyListeners();
    } else if (_activeThemeId != null) {
      await assignThemeToDevice(
        userId: userId,
        deviceName: deviceName,
        themeId: _activeThemeId!,
      );
    }
  }

  Future<void> _mergeRemoteThemes({
    required String userId,
    required String deviceName,
    required List<AppThemeModel> remoteThemes,
  }) async {
    final remote = remoteThemes.where((t) => t.id.trim().isNotEmpty).toList();

    final localById = {for (final t in _themes) t.id: t};
    final remoteById = {for (final t in remote) t.id: t};

    final merged = <AppThemeModel>[];
    final ids = {...localById.keys, ...remoteById.keys};

    for (final id in ids) {
      final l = localById[id];
      final r = remoteById[id];
      if (l == null && r != null) {
        merged.add(r);
        continue;
      }
      if (r == null && l != null) {
        merged.add(l);
        continue;
      }
      if (l != null && r != null) {
        merged.add((r.updatedAtMs >= l.updatedAtMs) ? r : l);
      }
    }

    merged.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _themes = merged.isEmpty ? [AppThemeModel.defaultDark()] : merged;
    if (_activeThemeId == null || !_themes.any((t) => t.id == _activeThemeId)) {
      _activeThemeId = _themes.first.id;
      await _local.saveActiveThemeId(_activeThemeId);
    }

    await _local.saveThemes(_themes);
    _rebuildThemeData();
    notifyListeners();

    for (final t in _themes) {
      final rt = remoteById[t.id];
      if (rt == null || t.updatedAtMs > rt.updatedAtMs) {
        await _cloud.upsertTheme(userId: userId, theme: t, deviceId: deviceName);
      }
    }
  }

  Future<void> assignThemeToDevice({
    required String userId,
    required String deviceName,
    required String themeId,
  }) async {
    if (themeId.trim().isEmpty) return;
    await _sistemaCloud.updateDeviceTheme(userId, deviceName, themeId);
  }

  Future<void> stopCloudSync() async {
    await _themesCloudSub?.cancel();
    _themesCloudSub = null;
    await _sistemaCloudSub?.cancel();
    _sistemaCloudSub = null;
  }

  void _rebuildThemeData() {
    _themeData = activeTheme.toThemeData();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    stopCloudSync();
    super.dispose();
  }
}
