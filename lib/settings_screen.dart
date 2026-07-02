import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'dart:async'; // Required for Timer
import 'services/alarm_firebase_service.dart';
import 'services/alarm_local_service.dart';
import 'services/alarm_repository.dart';
import 'services/sistema_firebase_service.dart';
import 'models/sistema_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/app_theme_model.dart';
import 'models/piper_voice_catalog.dart';
import 'widgets/app_theme_provider.dart';
import 'widgets/color_input_widget.dart';
import 'widgets/voices_manager_modal.dart';
import 'services/app_theme_controller.dart';

enum AlarmGroupingOption {
  none,
  twelveHour, // 2 groups of 12 hrs
  sixHour, // 4 groups of 6 hrs
  fourHour, // 6 groups of 4 hrs
  twoHour, // 12 groups of 2 hrs
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String alarmGroupingKey = 'alarm_grouping_option';
  static const String showNextAlarmKey = 'show_next_alarm';
  static const String snoozeDurationKey = 'snooze_duration_minutes';
  static const String maxSnoozesKey = 'max_snoozes';
  static const String cloudSyncKey = 'cloud_sync_enabled';

  // Nuevas claves para configuraciones de volumen
  static const String defaultMaxVolumeKey = 'default_max_volume_percent';
  static const String defaultVolumeRampUpKey = 'default_volume_ramp_up_seconds';
  static const String defaultTempVolumeReductionKey =
      'default_temp_volume_reduction_percent';
  static const String defaultTempVolumeReductionDurationKey =
      'default_temp_volume_reduction_duration_seconds';
  static const String leftScreenSelectionKey = 'left_screen_selection';

  // Claves para configuración global TTS
  static const String defaultTtsPiperVoiceKey = 'default_tts_piper_voice';
  static const String defaultTtsLanguageKey = 'default_tts_language';
  static const String defaultTtsPitchKey = 'default_tts_pitch';
  static const String defaultTtsVolumeKey = 'default_tts_volume';
  static const String defaultTtsRepeatCountKey = 'default_tts_repeat_count';
  static const String defaultTtsRepeatDelayKey =
      'default_tts_repeat_delay_seconds';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlarmGroupingOption _selectedGrouping = AlarmGroupingOption.none;
  bool _showNextAlarmSection = true;
  int _defaultSnoozeDuration = 5;
  int _defaultMaxSnoozes = 3;
  bool _cloudSyncEnabled = false;

  // Nuevas variables para configuraciones de volumen
  int _defaultMaxVolumePercent = 100;
  int _defaultVolumeRampUpDurationSeconds = 30;
  int _defaultTempVolumeReductionPercent = 30;
  int _defaultTempVolumeReductionDurationSeconds = 60;
  String _leftScreen = 'habits';

  // Variables para configuración global TTS
  String? _defaultTtsPiperVoice;
  String _defaultTtsLanguage = 'es-MX';
  double _defaultTtsPitch = 1.0;
  int _defaultTtsVolume = 80;
  int _defaultTtsRepeatCount = 3;
  int _defaultTtsRepeatDelay = 1;

  final AlarmFirebaseService _alarmFirebaseService = AlarmFirebaseService();
  final AlarmLocalService _alarmLocalService = AlarmLocalService();
  late final AlarmRepository _alarmRepository = AlarmRepository(
    local: _alarmLocalService,
    cloud: _alarmFirebaseService,
  );
  final SistemaFirebaseService _sistemaFirebaseService =
      SistemaFirebaseService();
  User? _currentUser;
  SistemaModel? _sistemaModel;

  // Countdown timer variables (similar to HomePage)
  Timer? _countdownTimer;
  Duration _timeUntilNextAlarm = Duration.zero;
  Alarm? _currentNextAlarmForCountdown;
  List<Alarm> _alarms = []; // To find the next alarm
  AppTypographyScale? _typographyDraft;
  String? _typographyDraftThemeId;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndAlarms();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettingsAndAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final groupingIndex =
        prefs.getInt(SettingsScreen.alarmGroupingKey) ??
        AlarmGroupingOption.none.index;
    final showNextAlarm =
        prefs.getBool(SettingsScreen.showNextAlarmKey) ?? true;
    final snoozeDuration = prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
    final maxSnoozes = prefs.getInt(SettingsScreen.maxSnoozesKey) ?? 3;
    final cloudSync = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    final leftScreen =
        prefs.getString(SettingsScreen.leftScreenSelectionKey) ?? 'habits';

    // Cargar configuraciones de volumen
    final maxVolumePercent =
        prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100;
    final volumeRampUpDuration =
        prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30;
    final tempVolumeReduction =
        prefs.getInt(SettingsScreen.defaultTempVolumeReductionKey) ?? 30;
    final tempVolumeReductionDuration =
        prefs.getInt(SettingsScreen.defaultTempVolumeReductionDurationKey) ??
        60;

    // Cargar configuración global TTS
    final defaultTtsPiperVoice = prefs.getString(
      SettingsScreen.defaultTtsPiperVoiceKey,
    );
    final defaultTtsLanguage =
        prefs.getString(SettingsScreen.defaultTtsLanguageKey) ?? 'es-MX';
    final defaultTtsPitch =
        prefs.getDouble(SettingsScreen.defaultTtsPitchKey) ?? 1.0;
    final defaultTtsVolume =
        prefs.getInt(SettingsScreen.defaultTtsVolumeKey) ?? 80;
    final defaultTtsRepeatCount =
        prefs.getInt(SettingsScreen.defaultTtsRepeatCountKey) ?? 3;
    final defaultTtsRepeatDelay =
        prefs.getInt(SettingsScreen.defaultTtsRepeatDelayKey) ?? 1;

    // Verificar estado de autenticación
    _currentUser = FirebaseAuth.instance.currentUser;

    // Cargar datos del sistema si hay usuario autenticado
    if (_currentUser != null) {
      await _loadSistemaData();
    }

    await _alarmRepository.ensureMigrated();
    _alarms = await _alarmRepository.loadLocalAlarms();

    if (mounted) {
      setState(() {
        _selectedGrouping = AlarmGroupingOption.values[groupingIndex];
        _showNextAlarmSection = showNextAlarm;
        _defaultSnoozeDuration = snoozeDuration;
        _defaultMaxSnoozes = maxSnoozes;
        _cloudSyncEnabled = cloudSync;
        _defaultMaxVolumePercent = maxVolumePercent;
        _defaultVolumeRampUpDurationSeconds = volumeRampUpDuration;
        _defaultTempVolumeReductionPercent = tempVolumeReduction;
        _defaultTempVolumeReductionDurationSeconds =
            tempVolumeReductionDuration;
        _leftScreen = leftScreen;
        _defaultTtsPiperVoice = defaultTtsPiperVoice;
        _defaultTtsLanguage = defaultTtsLanguage;
        _defaultTtsPitch = defaultTtsPitch;
        _defaultTtsVolume = defaultTtsVolume;
        _defaultTtsRepeatCount = defaultTtsRepeatCount;
        _defaultTtsRepeatDelay = defaultTtsRepeatDelay;
      });
    }
    _startOrUpdateCountdown(); // Start countdown after loading alarms
  }

  Future<void> _saveLeftScreen(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsScreen.leftScreenSelectionKey, screen);
    print('[SettingsScreen] pantalla izquierda guardada: $screen');
    if (mounted) {
      setState(() {
        _leftScreen = screen;
      });
    }
  }

  Future<void> _loadSistemaData() async {
    if (_currentUser == null) return;

    try {
      _sistemaModel = await _sistemaFirebaseService.getSistema(
        _currentUser!.uid,
      );

      // Inicializar el estado de sincronización de alarmas si no existe
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('alarm_sync_enabled')) {
        // Buscar el dispositivo actual y usar su estado como valor inicial
        final currentDeviceName =
            prefs.getString('device_name') ?? 'Dispositivo';
        final currentDevice = _sistemaModel?.usuarios.firstWhere(
          (user) => user['usuario'] == currentDeviceName,
          orElse: () => {'isActive': false},
        );
        final isCurrentDeviceActive = currentDevice?['isActive'] ?? false;
        await prefs.setBool('alarm_sync_enabled', isCurrentDeviceActive);
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error al cargar datos del sistema: $e');
    }
  }

  // Función _updateDeviceActiveState eliminada - ya no se usa

  // Agregar estos métodos
  Future<void> _saveSnoozeDuration(int duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.snoozeDurationKey, duration);
    if (mounted) {
      setState(() {
        _defaultSnoozeDuration = duration;
      });
    }
  }

  Future<void> _saveMaxSnoozes(int maxSnoozes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.maxSnoozesKey, maxSnoozes);
    if (mounted) {
      setState(() {
        _defaultMaxSnoozes = maxSnoozes;
      });
    }
  }

  // Métodos para guardar configuraciones de volumen
  Future<void> _saveDefaultMaxVolume(int maxVolume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultMaxVolumeKey, maxVolume);
    if (mounted) {
      setState(() {
        _defaultMaxVolumePercent = maxVolume;
      });
    }
  }

  Future<void> _saveDefaultVolumeRampUp(int rampUpDuration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultVolumeRampUpKey, rampUpDuration);
    if (mounted) {
      setState(() {
        _defaultVolumeRampUpDurationSeconds = rampUpDuration;
      });
    }
  }

  Future<void> _saveDefaultTempVolumeReduction(int tempReduction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      SettingsScreen.defaultTempVolumeReductionKey,
      tempReduction,
    );
    if (mounted) {
      setState(() {
        _defaultTempVolumeReductionPercent = tempReduction;
      });
    }
  }

  Future<void> _saveDefaultTempVolumeReductionDuration(int duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      SettingsScreen.defaultTempVolumeReductionDurationKey,
      duration,
    );
    if (mounted) {
      setState(() {
        _defaultTempVolumeReductionDurationSeconds = duration;
      });
    }
  }

  // ── Guardar configuración global TTS ──────────────────────────────────────

  Future<void> _saveTtsPiperVoice(String? voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (voiceId == null) {
      await prefs.remove(SettingsScreen.defaultTtsPiperVoiceKey);
    } else {
      await prefs.setString(SettingsScreen.defaultTtsPiperVoiceKey, voiceId);
    }
    if (mounted) setState(() => _defaultTtsPiperVoice = voiceId);
  }

  Future<void> _saveTtsLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsScreen.defaultTtsLanguageKey, language);
    if (mounted) setState(() => _defaultTtsLanguage = language);
  }

  Future<void> _saveTtsPitch(double pitch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsScreen.defaultTtsPitchKey, pitch);
    if (mounted) setState(() => _defaultTtsPitch = pitch);
  }

  Future<void> _saveTtsVolume(int volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultTtsVolumeKey, volume);
    if (mounted) setState(() => _defaultTtsVolume = volume);
  }

  Future<void> _saveTtsRepeatCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultTtsRepeatCountKey, count);
    if (mounted) setState(() => _defaultTtsRepeatCount = count);
  }

  Future<void> _saveTtsRepeatDelay(int delay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultTtsRepeatDelayKey, delay);
    if (mounted) setState(() => _defaultTtsRepeatDelay = delay);
  }

  Future<void> _openTtsVoicesManager() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =>
          VoicesManagerModal(selectedVoiceId: _defaultTtsPiperVoice),
    );
    if (!mounted) return;
    // result puede ser: String (voz seleccionada), '' (quitar), null (sin cambios)
    await _saveTtsPiperVoice(result?.isEmpty ?? false ? null : result);
  }

  // ─────────────────────────────────────────────────────────────────────────

  String _piperVoiceDisplayName(String voiceId) {
    try {
      final v = piperVoiceCatalog.firstWhere((v) => v.id == voiceId);
      return '${v.displayName} · ${v.locale} · ${v.qualityLabel}';
    } catch (_) {
      return voiceId;
    }
  }

  String _ttsLanguageLabel(String locale) {
    const names = {
      'es-MX': 'Español (México)',
      'es-ES': 'Español (España)',
      'es-US': 'Español (EE.UU.)',
      'en-US': 'English (US)',
      'en-GB': 'English (UK)',
      'pt-BR': 'Português (Brasil)',
      'fr-FR': 'Français',
      'de-DE': 'Deutsch',
      'it-IT': 'Italiano',
    };
    return names[locale] ?? locale;
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveCloudSyncOption(bool value) async {
    if (_currentUser == null) return;

    try {
      // Actualizar localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsScreen.cloudSyncKey, value);

      // Actualizar en Firebase para el dispositivo actual
      final currentDeviceName = prefs.getString('device_name') ?? 'Dispositivo';
      await _sistemaFirebaseService.updateDeviceCloudSync(
        _currentUser!.uid,
        currentDeviceName,
        value,
      );

      if (mounted) {
        setState(() {
          _cloudSyncEnabled = value;
        });
      }

      // Notificar a HomePage sobre el cambio de configuración
      await prefs.setBool('alarm_sync_enabled', value);

      // Si se activa el guardado en la nube, sincronizar todas las alarmas
      if (value) {
        await _syncAllAlarmsToCloud();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Sincronización de alarmas activada'
                : 'Sincronización de alarmas desactivada',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Error al actualizar sincronización: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al actualizar la sincronización'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _syncAllAlarmsToCloud() async {
    try {
      if (_currentUser == null) return;
      await _alarmRepository.ensureMigrated();
      await _alarmRepository.pullOnce(userId: _currentUser!.uid);
      final alarms = await _alarmRepository.loadLocalAlarms(
        includeDeleted: true,
      );

      for (final alarm in alarms) {
        final updated = alarm.copyWith(syncToCloud: true);
        await _alarmLocalService.upsertAlarm(updated);
        final json = Map<String, dynamic>.from(updated.toJson());
        json.remove('createdAt');
        json.remove('updatedAt');
        json.remove('revision');
        json.remove('fieldUpdatedAt');
        await _alarmLocalService.markDirtyFields(updated.id, json.keys.toSet());
      }

      await _alarmRepository.pushPendingChanges(userId: _currentUser!.uid);
      _alarms = await _alarmRepository.loadLocalAlarms();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error al sincronizar alarmas: $e');
      // Mostrar mensaje de error al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al sincronizar alarmas con la nube'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _saveGroupingOption(AlarmGroupingOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.alarmGroupingKey, option.index);
    if (mounted) {
      setState(() {
        _selectedGrouping = option;
      });
    }
  }

  Future<void> _saveShowNextAlarmOption(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsScreen.showNextAlarmKey, value);
    if (mounted) {
      setState(() {
        _showNextAlarmSection = value;
      });
    }
  }

  // --- Countdown Logic (adapted from HomePage) ---
  // Agregar estos métodos a la clase _SettingsScreenState

  void _startOrUpdateCountdown() {
    _countdownTimer?.cancel();

    final nextAlarm = _getNextActiveAlarm();
    _currentNextAlarmForCountdown = nextAlarm;

    if (nextAlarm != null) {
      _updateCountdown();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateCountdown();
      });
    } else {
      if (mounted) {
        setState(() {
          _timeUntilNextAlarm = Duration.zero;
        });
      }
    }
  }

  void _updateCountdown() {
    if (_currentNextAlarmForCountdown != null) {
      final now = DateTime.now();
      final difference = _currentNextAlarmForCountdown!.time.difference(now);

      if (difference.isNegative) {
        _startOrUpdateCountdown();
      } else {
        if (mounted) {
          setState(() {
            _timeUntilNextAlarm = difference;
          });
        }
      }
    }
  }

  Alarm? _getNextActiveAlarm() {
    final now = DateTime.now();
    final activeAlarms = _alarms.where((alarm) => alarm.isActive).toList();

    if (activeAlarms.isEmpty) return null;

    Alarm? nextAlarm;
    Duration? shortestDuration;

    for (final alarm in activeAlarms) {
      DateTime nextAlarmTime;

      if (alarm.isRepeating()) {
        nextAlarmTime = _calculateNextOccurrence(alarm, now);
      } else {
        nextAlarmTime = alarm.time;

        // Si la hora ya pasó hoy, programar para mañana
        if (nextAlarmTime.isBefore(now)) {
          nextAlarmTime = DateTime(
            now.year,
            now.month,
            now.day,
            alarm.time.hour,
            alarm.time.minute,
          ).add(const Duration(days: 1));
        }
      }

      final duration = nextAlarmTime.difference(now);
      if (duration.isNegative) continue;

      if (shortestDuration == null || duration < shortestDuration) {
        shortestDuration = duration;
        nextAlarm = Alarm(
          id: alarm.id,
          time: nextAlarmTime,
          title: alarm.title,
          message: alarm.message,
          isActive: alarm.isActive,
          repeatDays: alarm.repeatDays,
          isDaily: alarm.isDaily,
          isWeekly: alarm.isWeekly,
          isWeekend: alarm.isWeekend,
          snoozeCount: alarm.snoozeCount,
          maxSnoozes: alarm.maxSnoozes,
          snoozeDurationMinutes: alarm.snoozeDurationMinutes,
          requireGame: alarm.requireGame,
          gameConfig: alarm.gameConfig,
          syncToCloud: alarm.syncToCloud,
        );
      }
    }

    return nextAlarm;
  }

  DateTime _calculateNextOccurrence(Alarm alarm, DateTime now) {
    DateTime nextTime = alarm.time;

    if (alarm.isDaily) {
      if (nextTime.isBefore(now) || nextTime.isAtSameMomentAs(now)) {
        nextTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.time.hour,
          alarm.time.minute,
        ).add(const Duration(days: 1));
      }
    } else if (alarm.isWeekly) {
      final targetWeekday = alarm.time.weekday;
      int daysUntilNext = (targetWeekday - now.weekday) % 7;
      if (daysUntilNext == 0 && nextTime.isBefore(now)) {
        daysUntilNext = 7;
      }
      nextTime = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.time.hour,
        alarm.time.minute,
      ).add(Duration(days: daysUntilNext));
    } else if (alarm.isWeekend) {
      DateTime nextSaturday = now.add(
        Duration(days: (DateTime.saturday - now.weekday) % 7),
      );
      DateTime nextSunday = now.add(
        Duration(days: (DateTime.sunday - now.weekday) % 7),
      );

      if (nextSaturday.isBefore(now)) {
        nextSaturday = nextSaturday.add(const Duration(days: 7));
      }
      if (nextSunday.isBefore(now)) {
        nextSunday = nextSunday.add(const Duration(days: 7));
      }

      nextTime = nextSaturday.isBefore(nextSunday)
          ? DateTime(
              nextSaturday.year,
              nextSaturday.month,
              nextSaturday.day,
              alarm.time.hour,
              alarm.time.minute,
            )
          : DateTime(
              nextSunday.year,
              nextSunday.month,
              nextSunday.day,
              alarm.time.hour,
              alarm.time.minute,
            );
    } else if (alarm.repeatDays.isNotEmpty) {
      int daysToAdd = 1;
      while (daysToAdd <= 7) {
        final testDate = now.add(Duration(days: daysToAdd));
        if (alarm.repeatDays.contains(testDate.weekday)) {
          nextTime = DateTime(
            testDate.year,
            testDate.month,
            testDate.day,
            alarm.time.hour,
            alarm.time.minute,
          );
          break;
        }
        daysToAdd++;
      }
    }

    return nextTime;
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) {
      return '--:--:--';
    }

    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) {
      // Formato: dd:hh:mm:ss
      return '${days.toString().padLeft(2, '0')}:${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (hours > 0) {
      // Formato: hh:mm:ss
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      // Formato: mm:ss
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
  // --- End Countdown Logic ---

  String _groupingOptionToString(
    AlarmGroupingOption option, {
    bool short = false,
  }) {
    switch (option) {
      case AlarmGroupingOption.none:
        return short ? 'Ninguna' : 'Sin agrupar';
      case AlarmGroupingOption.twelveHour:
        return short ? '12 hs' : '2 grupos (12 hs c/u)';
      case AlarmGroupingOption.sixHour:
        return short ? '6 hs' : '4 grupos (6 hs c/u)';
      case AlarmGroupingOption.fourHour:
        return short ? '4 hs' : '6 grupos (4 hs c/u)';
      case AlarmGroupingOption.twoHour:
        return short ? '2 hs' : '12 grupos (2 hs c/u)';
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  // Helper to get tooltip for slider division
  String _getTooltipForSliderValue(double value) {
    int index = value.toInt();
    if (index >= 0 && index < AlarmGroupingOption.values.length) {
      return _groupingOptionToString(AlarmGroupingOption.values[index]);
    }
    return '';
  }

  Future<void> _openThemeEditorScreen({
    required AppThemeController controller,
    required AppThemeModel theme,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            ThemeEditorScreen(controller: controller, theme: theme),
      ),
    );
  }

  AppTypographyScale _effectiveTypography(AppThemeModel activeTheme) {
    final source =
        (_typographyDraftThemeId == activeTheme.id && _typographyDraft != null)
        ? _typographyDraft!
        : activeTheme.typography;
    return source.normalized();
  }

  void _updateTypographyDraft({
    required AppThemeModel activeTheme,
    required AppTypographyScale typography,
  }) {
    setState(() {
      _typographyDraftThemeId = activeTheme.id;
      _typographyDraft = typography.normalized();
    });
  }

  Future<void> _persistTypographyDraft({
    required AppThemeController controller,
    required AppThemeModel activeTheme,
    required AppTypographyScale typography,
  }) async {
    final normalized = typography.normalized();
    if (normalized.toMap().toString() ==
        activeTheme.typography.normalized().toMap().toString()) {
      return;
    }
    await controller.updateTheme(activeTheme.copyWith(typography: normalized));
    if (!mounted) return;
    setState(() {
      _typographyDraftThemeId = activeTheme.id;
      _typographyDraft = normalized;
    });
  }

  Widget _buildTypographyCard(
    BuildContext context,
    AppThemeController controller,
    AppThemeModel activeTheme,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final typography = _effectiveTypography(activeTheme);
    final previewTheme = activeTheme
        .copyWith(typography: typography)
        .toThemeData();
    final previewScaler = AppTypographyTextScaler(
      typography: typography,
      textScale: activeTheme.textScale,
    );

    Widget buildSlider({
      required String label,
      required double value,
      required double min,
      required double max,
      required int divisions,
      required AppTypographyScale Function(double value) update,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ${value.round()} pt',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.round()} pt',
            activeColor: scheme.primary,
            onChanged: (nextValue) {
              _updateTypographyDraft(
                activeTheme: activeTheme,
                typography: update(nextValue),
              );
            },
            onChangeEnd: (nextValue) {
              _persistTypographyDraft(
                controller: controller,
                activeTheme: activeTheme,
                typography: update(nextValue),
              );
            },
          ),
        ],
      );
    }

    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipografía', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Toda la app se unifica en 5 tamaños globales. Ajusta estos valores y verás la vista previa en tiempo real.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            buildSlider(
              label: 'Pequeño',
              value: typography.small,
              min: 10,
              max: 16,
              divisions: 6,
              update: (value) => typography.copyWith(small: value),
            ),
            buildSlider(
              label: 'Cuerpo',
              value: typography.body,
              min: typography.small + 1,
              max: 20,
              divisions: (20 - (typography.small + 1)).round().clamp(1, 20),
              update: (value) => typography.copyWith(body: value),
            ),
            buildSlider(
              label: 'Mediano',
              value: typography.medium,
              min: typography.body + 1,
              max: 24,
              divisions: (24 - (typography.body + 1)).round().clamp(1, 20),
              update: (value) => typography.copyWith(medium: value),
            ),
            buildSlider(
              label: 'Título',
              value: typography.title,
              min: typography.medium + 1,
              max: 36,
              divisions: (36 - (typography.medium + 1)).round().clamp(1, 20),
              update: (value) => typography.copyWith(title: value),
            ),
            buildSlider(
              label: 'Display',
              value: typography.display,
              min: typography.title + 1,
              max: 60,
              divisions: (60 - (typography.title + 1)).round().clamp(1, 24),
              update: (value) => typography.copyWith(display: value),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outline),
              ),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: previewScaler),
                child: Theme(
                  data: previewTheme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Display para alertas importantes',
                        style: TextStyle(
                          fontSize: typography.display,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Título de pantalla o sección',
                        style: TextStyle(
                          fontSize: typography.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Texto mediano para botones y datos destacados',
                        style: TextStyle(
                          fontSize: typography.medium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Texto de cuerpo para la mayoría del contenido',
                        style: TextStyle(fontSize: typography.body),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Texto pequeño para ayudas, chips y detalles secundarios',
                        style: TextStyle(
                          fontSize: typography.small,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesCard(AppThemeController controller) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final themes = controller.themes;
        final activeId =
            controller.activeThemeId ??
            (themes.isNotEmpty ? themes.first.id : null);
        final activeTheme = controller.activeTheme;

        return Card(
          elevation: 2.0,
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Temas', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Crea, duplica y aplica temas; también puedes asignarlos por dispositivo.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: activeId,
                  decoration: const InputDecoration(labelText: 'Tema activo'),
                  items: themes
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.id, child: Text(t.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    controller.setActiveThemeId(v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final created = await controller.createTheme(
                            name: 'Nuevo tema',
                          );
                          await _openThemeEditorScreen(
                            controller: controller,
                            theme: created,
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                        child: const Text('Crear'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            (activeTheme.id == AppThemeModel.defaultDark().id)
                            ? null
                            : () => controller.deleteTheme(activeTheme.id),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error),
                        ),
                        child: const Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _openThemeEditorScreen(
                          controller: controller,
                          theme: activeTheme,
                        ),
                        child: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: activeId == null
                            ? null
                            : () async {
                                final duplicated = await controller
                                    .duplicateTheme(activeId);
                                if (duplicated == null) return;
                                await _openThemeEditorScreen(
                                  controller: controller,
                                  theme: duplicated,
                                );
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                        child: const Text('Duplicar'),
                      ),
                    ),
                  ],
                ),
                if (_currentUser != null && _sistemaModel != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Asignación por dispositivo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._sistemaModel!.usuarios.map((u) {
                    final deviceName =
                        (u['usuario'] as String?) ?? 'Dispositivo';
                    final deviceThemeId = (u['activeThemeId'] as String?)
                        ?.trim();
                    final selected =
                        (deviceThemeId != null && deviceThemeId.isNotEmpty)
                        ? deviceThemeId
                        : activeId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        value: selected,
                        decoration: InputDecoration(labelText: deviceName),
                        items: themes
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(t.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          if (v == null || _currentUser == null) return;
                          await controller.assignThemeToDevice(
                            userId: _currentUser!.uid,
                            deviceName: deviceName,
                            themeId: v,
                          );
                          await _loadSistemaData();
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeController = AppThemeProvider.of(context);

    // Slider values: 0 for none, 1 for twelveHour, ..., 4 for twoHour
    double sliderValue = _selectedGrouping.index.toDouble();
    final sliderDivisions = AlarmGroupingOption.values.length - 1; // 0 to 4

    // Verificar si hay alarmas activas
    final hasActiveAlarms = _alarms.any((alarm) => alarm.isActive);
    final nextAlarm = _getNextActiveAlarm();

    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 45),
          child: Text('Configuración'),
        ),
      ),
      body: Column(
        children: [
          if (_showNextAlarmSection &&
              _currentNextAlarmForCountdown !=
                  null) // Show only if enabled and an alarm exists
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              color: hasActiveAlarms ? scheme.primary : scheme.surface,
              child: Text(
                hasActiveAlarms
                    ? 'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}'
                    : 'No hay alarmas activas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: hasActiveAlarms ? scheme.onPrimary : scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: <Widget>[
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: SwitchListTile(
                    title: const Text(
                      'Mostrar sección "Próxima Alarma" en Inicio',
                    ),
                    subtitle: const Text(
                      'Permite ver detalles de la siguiente alarma programada en la pantalla principal.',
                    ),
                    value: _showNextAlarmSection,
                    activeColor: scheme.primary,
                    inactiveThumbColor: scheme.onSurface,
                    onChanged: (bool value) {
                      _saveShowNextAlarmOption(value);
                    },
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildThemesCard(themeController),
                const SizedBox(height: 16),
                _buildTypographyCard(
                  context,
                  themeController,
                  themeController.activeTheme,
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agrupación de Alarmas',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Intervalo: ${_groupingOptionToString(_selectedGrouping)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: sliderValue,
                          min: 0,
                          max: sliderDivisions.toDouble(),
                          divisions: sliderDivisions,
                          label: _getTooltipForSliderValue(
                            sliderValue,
                          ), // Dynamic label
                          onChanged: (double value) {
                            _saveGroupingOption(
                              AlarmGroupingOption.values[value.toInt()],
                            );
                          },
                          activeColor: scheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: AlarmGroupingOption.values.map((option) {
                            return Text(
                              _groupingOptionToString(option, short: true),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Agregar esta nueva card después de la card de agrupación
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuración de Posposición',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // Duración de posposición
                        Text(
                          'Duración de posposición: $_defaultSnoozeDuration minutos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultSnoozeDuration.toDouble(),
                          min: 1,
                          max: 30,
                          divisions: 29,
                          label: '$_defaultSnoozeDuration min',
                          onChanged: (double value) {
                            _saveSnoozeDuration(value.toInt());
                          },
                          activeColor: scheme.primary,
                        ),
                        const SizedBox(height: 16),

                        // Máximo número de posposiciones
                        Text(
                          'Máximo de posposiciones: $_defaultMaxSnoozes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultMaxSnoozes.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_defaultMaxSnoozes',
                          onChanged: (double value) {
                            _saveMaxSnoozes(value.toInt());
                          },
                          activeColor: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Nueva Card para configuraciones de volumen
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuración de Volumen',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Configuraciones predeterminadas para el control de volumen de las alarmas',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 16),

                        // Volumen máximo
                        Text(
                          'Volumen máximo: $_defaultMaxVolumePercent%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultMaxVolumePercent.toDouble(),
                          min: 10,
                          max: 100,
                          divisions: 18,
                          label: '$_defaultMaxVolumePercent%',
                          onChanged: (double value) {
                            _saveDefaultMaxVolume(value.toInt());
                          },
                          activeColor: scheme.primary,
                        ),
                        const SizedBox(height: 16),

                        // Duración de escalado de volumen
                        Text(
                          'Duración de escalado: $_defaultVolumeRampUpDurationSeconds segundos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultVolumeRampUpDurationSeconds.toDouble(),
                          min: 0,
                          max: 120,
                          divisions: 24,
                          label: '$_defaultVolumeRampUpDurationSeconds s',
                          onChanged: (double value) {
                            _saveDefaultVolumeRampUp(value.toInt());
                          },
                          activeColor: scheme.secondary,
                        ),
                        const SizedBox(height: 16),

                        // Porcentaje de reducción temporal
                        Text(
                          'Reducción temporal: $_defaultTempVolumeReductionPercent%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultTempVolumeReductionPercent.toDouble(),
                          min: 10,
                          max: 80,
                          divisions: 14,
                          label: '$_defaultTempVolumeReductionPercent%',
                          onChanged: (double value) {
                            _saveDefaultTempVolumeReduction(value.toInt());
                          },
                          activeColor: scheme.tertiary,
                        ),
                        const SizedBox(height: 16),

                        // Duración de reducción temporal
                        Text(
                          'Duración de reducción: $_defaultTempVolumeReductionDurationSeconds segundos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultTempVolumeReductionDurationSeconds
                              .toDouble(),
                          min: 15,
                          max: 300,
                          divisions: 19,
                          label:
                              '$_defaultTempVolumeReductionDurationSeconds s',
                          onChanged: (double value) {
                            _saveDefaultTempVolumeReductionDuration(
                              value.toInt(),
                            );
                          },
                          activeColor: scheme.tertiary,
                        ),
                      ],
                    ),
                  ),
                ),
                // Card para configuración global TTS
                const SizedBox(height: 16),
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuración TTS por defecto',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Valores predeterminados para el texto a voz en alarmas y recordatorios. Cada alarma o recordatorio puede sobrescribir esta configuración.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 16),

                        // Voz Piper
                        Text(
                          'Voz Piper',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_defaultTtsPiperVoice != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.record_voice_over,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _piperVoiceDisplayName(
                                      _defaultTtsPiperVoice!,
                                    ),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: scheme.error,
                                  ),
                                  tooltip: 'Quitar voz',
                                  onPressed: () => _saveTtsPiperVoice(null),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            'Sin voz Piper — se usará la voz del sistema',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _openTtsVoicesManager,
                          icon: const Icon(Icons.library_music, size: 18),
                          label: const Text('Gestionar voces Piper'),
                        ),
                        const SizedBox(height: 16),

                        // Idioma (solo si no hay voz Piper)
                        if (_defaultTtsPiperVoice == null) ...[
                          Text(
                            'Idioma: ${_ttsLanguageLabel(_defaultTtsLanguage)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          DropdownButton<String>(
                            value: _defaultTtsLanguage,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'es-MX',
                                child: Text('Español (México)'),
                              ),
                              DropdownMenuItem(
                                value: 'es-ES',
                                child: Text('Español (España)'),
                              ),
                              DropdownMenuItem(
                                value: 'es-US',
                                child: Text('Español (EE.UU.)'),
                              ),
                              DropdownMenuItem(
                                value: 'en-US',
                                child: Text('English (US)'),
                              ),
                              DropdownMenuItem(
                                value: 'en-GB',
                                child: Text('English (UK)'),
                              ),
                              DropdownMenuItem(
                                value: 'pt-BR',
                                child: Text('Português (Brasil)'),
                              ),
                              DropdownMenuItem(
                                value: 'fr-FR',
                                child: Text('Français'),
                              ),
                              DropdownMenuItem(
                                value: 'de-DE',
                                child: Text('Deutsch'),
                              ),
                              DropdownMenuItem(
                                value: 'it-IT',
                                child: Text('Italiano'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) _saveTtsLanguage(v);
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Tono
                        Text(
                          'Tono: ${_defaultTtsPitch.toStringAsFixed(1)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultTtsPitch,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: _defaultTtsPitch.toStringAsFixed(1),
                          onChanged: (v) =>
                              _saveTtsPitch(double.parse(v.toStringAsFixed(1))),
                          activeColor: scheme.primary,
                        ),
                        const SizedBox(height: 16),

                        // Volumen TTS
                        Text(
                          'Volumen TTS: $_defaultTtsVolume%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultTtsVolume.toDouble(),
                          min: 10,
                          max: 100,
                          divisions: 18,
                          label: '$_defaultTtsVolume%',
                          onChanged: (v) => _saveTtsVolume(v.toInt()),
                          activeColor: scheme.secondary,
                        ),
                        const SizedBox(height: 16),

                        // Repeticiones
                        Text(
                          'Repeticiones',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final entry in const [
                              (1, '1 vez'),
                              (3, '3 veces'),
                              (5, '5 veces'),
                              (-1, 'Indefinido'),
                            ])
                              ChoiceChip(
                                label: Text(entry.$2),
                                selected: _defaultTtsRepeatCount == entry.$1,
                                selectedColor: scheme.tertiary,
                                labelStyle: TextStyle(
                                  color: _defaultTtsRepeatCount == entry.$1
                                      ? scheme.onTertiary
                                      : scheme.onSurface,
                                ),
                                onSelected: (_) =>
                                    _saveTtsRepeatCount(entry.$1),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Pausa entre repeticiones
                        Text(
                          'Pausa entre repeticiones',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final s in const [1, 3, 5, 10, 15])
                              ChoiceChip(
                                label: Text('${s}s'),
                                selected: _defaultTtsRepeatDelay == s,
                                selectedColor: scheme.tertiary,
                                labelStyle: TextStyle(
                                  color: _defaultTtsRepeatDelay == s
                                      ? scheme.onTertiary
                                      : scheme.onSurface,
                                ),
                                onSelected: (_) => _saveTtsRepeatDelay(s),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Card para selección de pantalla izquierda del menú
                const SizedBox(height: 16),
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pantalla del menú izquierdo',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selecciona qué pantalla se muestra a la izquierda del menú principal. Las dos pantallas restantes aparecerán juntas en la vista dual del lado derecho.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        RadioListTile<String>(
                          title: const Text('Hábitos'),
                          value: 'habits',
                          groupValue: _leftScreen,
                          activeColor: scheme.primary,
                          onChanged: (v) {
                            if (v != null) _saveLeftScreen(v);
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Calendario'),
                          value: 'calendar',
                          groupValue: _leftScreen,
                          activeColor: scheme.primary,
                          onChanged: (v) {
                            if (v != null) _saveLeftScreen(v);
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Medicamentos'),
                          value: 'medications',
                          groupValue: _leftScreen,
                          activeColor: scheme.primary,
                          onChanged: (v) {
                            if (v != null) _saveLeftScreen(v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Card para autenticación
                if (_currentUser == null) ...[
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2.0,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pushNamed('/login');
                      },
                      borderRadius: BorderRadius.circular(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.login, color: scheme.primary, size: 28),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Iniciar Sesión',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Accede a tu cuenta para sincronizar tus alarmas',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: scheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: scheme.onSurface,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                // Card para gestión de dispositivos eliminada la card de guardado en la nube
                if (_currentUser != null) ...[
                  const SizedBox(height: 16),
                  // Card(
                  //   elevation: 2.0,
                  //   margin: const EdgeInsets.symmetric(vertical: 8.0),
                  //   child: Padding(
                  //     padding: const EdgeInsets.all(16.0),
                  //     child: Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         Text(
                  //           'Guardado en la Nube',
                  //           style: Theme.of(context).textTheme.titleLarge,
                  //         ),
                  //         const SizedBox(height: 8),
                  //         Text(
                  //           _currentUser != null
                  //               ? 'Sincroniza tus alarmas con Firebase'
                  //               : 'Inicia sesión para habilitar esta función',
                  //           style: Theme.of(context).textTheme.bodyMedium
                  //               ?.copyWith(color: Colors.grey[600]),
                  //         ),
                  //         const SizedBox(height: 16),
                  //         SwitchListTile(
                  //           title: Text(
                  //             'Activar guardado en la nube',
                  //             style: Theme.of(context).textTheme.titleMedium,
                  //           ),
                  //           subtitle: Text(
                  //             _currentUser != null
                  //                 ? 'Las alarmas se guardarán automáticamente en Firebase'
                  //                 : 'Requiere iniciar sesión',
                  //             style: Theme.of(context).textTheme.bodySmall
                  //                 ?.copyWith(color: Colors.grey[600]),
                  //           ),
                  //           value: _cloudSyncEnabled && _currentUser != null,
                  //           activeColor: Colors.green,
                  //           inactiveThumbColor: Colors.grey,
                  //           onChanged: _currentUser != null
                  //               ? (bool value) {
                  //                   _saveCloudSyncOption(value);
                  //                 }
                  //               : null,
                  //           contentPadding: EdgeInsets.zero,
                  //         ),
                  //         // if (_currentUser == null)
                  //         //   Padding(
                  //         //     padding: const EdgeInsets.only(top: 8.0),
                  //         //     child: ElevatedButton.icon(
                  //         //       onPressed: () {
                  //         //         Navigator.of(context).pushNamed('/login');
                  //         //       },
                  //         //       icon: const Icon(Icons.login),
                  //         //       label: const Text('Iniciar Sesión'),
                  //         //       style: ElevatedButton.styleFrom(
                  //         //         backgroundColor: Colors.blue,
                  //         //         foregroundColor: Colors.white,
                  //         //       ),
                  //         //     ),
                  //         //   ),
                  //       ],
                  //     ),
                  //   ),
                  // ),
                  // // Card para gestión de dispositivos
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2.0,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sincronización entre Dispositivos',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Controla la sincronización de alarmas entre tus dispositivos conectados',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 16),
                          if (_sistemaModel != null &&
                              _sistemaModel!.usuarios.isNotEmpty)
                            ..._sistemaModel!.usuarios.map((user) {
                              final deviceName =
                                  user['usuario'] as String? ??
                                  'Dispositivo sin nombre';
                              final isActive =
                                  user['isActive'] as bool? ?? true;
                              final cloudSyncEnabled =
                                  user['_cloudSyncEnabled'] as bool? ?? false;

                              return FutureBuilder<String?>(
                                future: SharedPreferences.getInstance().then(
                                  (prefs) => prefs.getString('device_name'),
                                ),
                                builder: (context, snapshot) {
                                  final currentDeviceName =
                                      snapshot.data ?? 'Dispositivo';
                                  final isCurrentDevice =
                                      deviceName == currentDeviceName;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8.0),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: scheme.primary),
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.phone_android,
                                        color:
                                            (isCurrentDevice
                                                ? cloudSyncEnabled
                                                : isActive)
                                            ? scheme.primary
                                            : scheme.onSurface,
                                      ),
                                      title: Text(
                                        deviceName +
                                            (isCurrentDevice
                                                ? ' (Este dispositivo)'
                                                : ''),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      subtitle: Text(
                                        (isCurrentDevice
                                                ? cloudSyncEnabled
                                                : isActive)
                                            ? 'Sincronización activada'
                                            : 'Sincronización desactivada',
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      trailing: Switch(
                                        value:
                                            _cloudSyncEnabled &&
                                            _currentUser != null,
                                        activeColor: scheme.primary,
                                        onChanged: isCurrentDevice
                                            ? (bool value) {
                                                _saveCloudSyncOption(value);
                                              }
                                            : null, // Solo el dispositivo actual puede cambiar
                                      ),
                                    ),
                                  );
                                },
                              );
                            })
                          else
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: scheme.primary),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: scheme.onSurface,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No hay dispositivos conectados a esta cuenta',
                                      style: TextStyle(color: scheme.onSurface),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                // Card para cerrar sesión
                if (_currentUser != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2.0,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: InkWell(
                      onTap: () {
                        signOut();
                      },
                      borderRadius: BorderRadius.circular(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout,
                              color: scheme.error,
                              size: 28,
                            ), // Icono de cerrar sesión
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cerrar Sesión', // Texto para cerrar sesión
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cierra tu sesión actual', // Descripción para cerrar sesión
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: scheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: scheme.onSurface,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                // ── Módulo IA ────────────────────────────────────────────
                const SizedBox(height: 16),
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamed('/ai'),
                    borderRadius: BorderRadius.circular(8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.smart_toy_outlined, color: scheme.tertiary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Módulo IA Local',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Descarga y gestiona modelos de lenguaje 100 % locales',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: scheme.onSurface),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: scheme.onSurface, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                // Add more settings here in separate Cards if needed
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeEditorScreen extends StatefulWidget {
  final AppThemeController controller;
  final AppThemeModel theme;

  const ThemeEditorScreen({
    super.key,
    required this.controller,
    required this.theme,
  });

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late final TextEditingController _nameController;
  late String _backgroundColor;
  late String _surfaceColor;
  late String _textColor;
  late String _primaryColor;
  late String _secondaryColor;
  late String _tertiaryColor;
  late double _textScale;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.theme.name);
    _backgroundColor = widget.theme.backgroundColor;
    _surfaceColor = widget.theme.surfaceColor;
    _textColor = widget.theme.textColor;
    _primaryColor = widget.theme.primaryColor;
    _secondaryColor = widget.theme.secondaryColor;
    _tertiaryColor = widget.theme.tertiaryColor;
    _textScale = widget.theme.textScale;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final updated = widget.theme.copyWith(
      name: name.isEmpty ? widget.theme.name : name,
      backgroundColor: _backgroundColor,
      surfaceColor: _surfaceColor,
      textColor: _textColor,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      tertiaryColor: _tertiaryColor,
      textScale: _textScale,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await widget.controller.updateTheme(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tema')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _backgroundColor,
                label: 'Fondo',
                onColorChanged: (v) => setState(() {
                  _backgroundColor = v ?? _backgroundColor;
                }),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _surfaceColor,
                label: 'Superficie',
                onColorChanged: (v) => setState(() {
                  _surfaceColor = v ?? _surfaceColor;
                }),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _textColor,
                label: 'Texto',
                onColorChanged: (v) => setState(() {
                  _textColor = v ?? _textColor;
                }),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _primaryColor,
                label: 'Resalte principal',
                onColorChanged: (v) => setState(() {
                  _primaryColor = v ?? _primaryColor;
                }),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _secondaryColor,
                label: 'Resalte secundario',
                onColorChanged: (v) => setState(() {
                  _secondaryColor = v ?? _secondaryColor;
                }),
              ),
              const SizedBox(height: 12),
              ColorInputWidget(
                initialColor: _tertiaryColor,
                label: 'Resalte terciario',
                onColorChanged: (v) => setState(() {
                  _tertiaryColor = v ?? _tertiaryColor;
                }),
              ),
              const SizedBox(height: 16),
              Text('Tamaño de texto: ${(_textScale * 100).round()}%'),
              Slider(
                value: _textScale,
                min: 0.8,
                max: 1.4,
                divisions: 12,
                label: '${(_textScale * 100).round()}%',
                onChanged: (v) => setState(() => _textScale = v),
                activeColor: scheme.primary,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
