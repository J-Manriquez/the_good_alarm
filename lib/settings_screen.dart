import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'dart:async'; // Required for Timer
import 'dart:convert';
import 'home_page.dart'; // To access Alarm model and potentially _formatDuration
import 'services/auth_service.dart';
import 'services/alarm_firebase_service.dart';
import 'services/sistema_firebase_service.dart';
import 'models/sistema_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  static const String defaultTempVolumeReductionKey = 'default_temp_volume_reduction_percent';
  static const String defaultTempVolumeReductionDurationKey = 'default_temp_volume_reduction_duration_seconds';

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

  final AuthService _authService = AuthService();
  final AlarmFirebaseService _alarmFirebaseService = AlarmFirebaseService();
  final SistemaFirebaseService _sistemaFirebaseService = SistemaFirebaseService();
  User? _currentUser;
  SistemaModel? _sistemaModel;

  // Countdown timer variables (similar to HomePage)
  Timer? _countdownTimer;
  Duration _timeUntilNextAlarm = Duration.zero;
  Alarm? _currentNextAlarmForCountdown;
  List<Alarm> _alarms = []; // To find the next alarm
  static const String _alarmsKey = 'alarms_list'; // Copied from HomePage

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
    
    // Cargar configuraciones de volumen
    final maxVolumePercent = prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100;
    final volumeRampUpDuration = prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30;
    final tempVolumeReduction = prefs.getInt(SettingsScreen.defaultTempVolumeReductionKey) ?? 30;
    final tempVolumeReductionDuration = prefs.getInt(SettingsScreen.defaultTempVolumeReductionDurationKey) ?? 60;

    // Verificar estado de autenticación
    _currentUser = FirebaseAuth.instance.currentUser;
    
    // Cargar datos del sistema si hay usuario autenticado
    if (_currentUser != null) {
      await _loadSistemaData();
    }

    // Load alarms to calculate next alarm countdown
    final alarmsString = prefs.getStringList(_alarmsKey);
    if (alarmsString != null) {
      _alarms = alarmsString.map((s) => Alarm.fromJson(jsonDecode(s))).toList();
      _alarms.sort((a, b) => a.time.compareTo(b.time));
    }

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
        _defaultTempVolumeReductionDurationSeconds = tempVolumeReductionDuration;
      });
    }
    _startOrUpdateCountdown(); // Start countdown after loading alarms
  }

  Future<void> _loadSistemaData() async {
    if (_currentUser == null) return;
    
    try {
      _sistemaModel = await _sistemaFirebaseService.getSistema(_currentUser!.uid);
      
      // Inicializar el estado de sincronización de alarmas si no existe
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('alarm_sync_enabled')) {
        // Buscar el dispositivo actual y usar su estado como valor inicial
        final currentDeviceName = prefs.getString('device_name') ?? 'Dispositivo';
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
    await prefs.setInt(SettingsScreen.defaultTempVolumeReductionKey, tempReduction);
    if (mounted) {
      setState(() {
        _defaultTempVolumeReductionPercent = tempReduction;
      });
    }
  }

  Future<void> _saveDefaultTempVolumeReductionDuration(int duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.defaultTempVolumeReductionDurationKey, duration);
    if (mounted) {
      setState(() {
        _defaultTempVolumeReductionDurationSeconds = duration;
      });
    }
  }

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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
                ? 'Sincronización de alarmas activada'
                : 'Sincronización de alarmas desactivada',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error al actualizar sincronización: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar la sincronización'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncAllAlarmsToCloud() async {
    try {
      if (_currentUser == null) return;

      // Obtener el ID de la colección del usuario
      final userData = await _authService.getUserData(_currentUser!.uid);
      if (userData == null) return;

      final userCollectionId =
          '${userData.name}_${userData.creationDate.millisecondsSinceEpoch}';

      // Actualizar todas las alarmas para que se sincronicen por defecto
      final prefs = await SharedPreferences.getInstance();
      final alarmsString = prefs.getStringList('alarms_list');
      if (alarmsString != null) {
        final alarms = alarmsString
            .map((s) => Alarm.fromJson(jsonDecode(s)))
            .toList();

        // Actualizar alarmas para sincronización
        final updatedAlarms = alarms
            .map(
              (alarm) => Alarm(
                id: alarm.id,
                time: alarm.time,
                title: alarm.title,
                message: alarm.message,
                isActive: alarm.isActive,
                repeatDays: alarm.repeatDays,
                snoozeDurationMinutes: alarm.snoozeDurationMinutes,
                maxSnoozes: alarm.maxSnoozes,
                snoozeCount: alarm.snoozeCount,
                requireGame: alarm.requireGame,
                gameConfig: alarm.gameConfig,
                syncToCloud: true, // Activar sincronización por defecto
              ),
            )
            .toList();

        // Guardar alarmas actualizadas localmente
        final updatedAlarmsString = updatedAlarms
            .map((alarm) => jsonEncode(alarm.toJson()))
            .toList();
        await prefs.setStringList('alarms_list', updatedAlarmsString);

        // Sincronizar con Firebase
        await _alarmFirebaseService.syncAllAlarms(
          updatedAlarms,
          userCollectionId,
        );
      }
    } catch (e) {
      print('Error al sincronizar alarmas: $e');
      // Mostrar mensaje de error al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al sincronizar alarmas con la nube'),
            backgroundColor: Colors.red,
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

  // funcion para cerrar sesion con AuthService
  Future<void> signOut() async {
    await AuthService().signOut();
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

  @override
  Widget build(BuildContext context) {
    // Slider values: 0 for none, 1 for twelveHour, ..., 4 for twoHour
    double sliderValue = _selectedGrouping.index.toDouble();
    final sliderDivisions = AlarmGroupingOption.values.length - 1; // 0 to 4

    // Verificar si hay alarmas activas
    final hasActiveAlarms = _alarms.any((alarm) => alarm.isActive);
    final nextAlarm = _getNextActiveAlarm();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
        title: Padding(
          padding: const EdgeInsets.only(left: 45),
          child: Text(
            'Configuración',
            style: TextStyle(
              fontSize: 25,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          if (_showNextAlarmSection &&
              _currentNextAlarmForCountdown !=
                  null) // Show only if enabled and an alarm exists
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              color: hasActiveAlarms ? Colors.green : Colors.black,
              child: Text(
                hasActiveAlarms
                    ? 'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}'
                    : 'No hay alarmas activas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color.fromARGB(255, 255, 255, 255),
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
                    activeColor: Colors.green,
                    inactiveThumbColor: Colors.black,
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
                          activeColor: Colors.green,
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
                          activeColor: Colors.green,
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
                          activeColor: Colors.green,
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
                              ?.copyWith(color: Colors.grey[600]),
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
                          activeColor: Colors.blue,
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
                          activeColor: Colors.blue,
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
                          activeColor: Colors.orange,
                        ),
                        const SizedBox(height: 16),

                        // Duración de reducción temporal
                        Text(
                          'Duración de reducción: $_defaultTempVolumeReductionDurationSeconds segundos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _defaultTempVolumeReductionDurationSeconds.toDouble(),
                          min: 15,
                          max: 300,
                          divisions: 19,
                          label: '$_defaultTempVolumeReductionDurationSeconds s',
                          onChanged: (double value) {
                            _saveDefaultTempVolumeReductionDuration(value.toInt());
                          },
                          activeColor: Colors.orange,
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
                            Icon(
                              Icons.login,
                              color: Colors.blue[600],
                              size: 28,
                            ),
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
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey[400],
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
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          if (_sistemaModel != null && _sistemaModel!.usuarios.isNotEmpty) ...
                            _sistemaModel!.usuarios.map((user) {
                              final deviceName = user['usuario'] as String? ?? 'Dispositivo sin nombre';
                              final isActive = user['isActive'] as bool? ?? true;
                              final cloudSyncEnabled = user['_cloudSyncEnabled'] as bool? ?? false;
                              
                              return FutureBuilder<String?>(
                                future: SharedPreferences.getInstance().then((prefs) => prefs.getString('device_name')),
                                builder: (context, snapshot) {
                                  final currentDeviceName = snapshot.data ?? 'Dispositivo';
                                  final isCurrentDevice = deviceName == currentDeviceName;
                                  
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8.0),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.phone_android,
                                        color: (isCurrentDevice ? cloudSyncEnabled : isActive) ? Colors.green : Colors.grey,
                                      ),
                                      title: Text(
                                        deviceName + (isCurrentDevice ? ' (Este dispositivo)' : ''),
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        (isCurrentDevice ? cloudSyncEnabled : isActive) 
                                            ? 'Sincronización activada' 
                                            : 'Sincronización desactivada',
                                        style: TextStyle(
                                          color: (isCurrentDevice ? cloudSyncEnabled : isActive) ? Colors.green : Colors.grey,
                                        ),
                                      ),
                                      trailing: Switch(
                                        value: _cloudSyncEnabled && _currentUser != null,
                                        activeColor: Colors.green,
                                        onChanged: isCurrentDevice ? (bool value) {
                                          _saveCloudSyncOption(value);
                                        } : null, // Solo el dispositivo actual puede cambiar
                                       ),
                                     ),
                                   );
                                 },
                               );
                            }).toList()
                          else
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No hay dispositivos conectados a esta cuenta',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
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
                              color: Colors.red[600],
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
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey[400],
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                // Add more settings here in separate Cards if needed
              ],
            ),
          ),
        ],
      ),
    );
  }
}
