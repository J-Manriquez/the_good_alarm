import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'dart:async'; // Required for Timer
import 'dart:convert';
import 'home_page.dart'; // To access Alarm model and potentially _formatDuration
import 'services/auth_service.dart';
import 'services/alarm_firebase_service.dart';
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

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlarmGroupingOption _selectedGrouping = AlarmGroupingOption.none;
  bool _showNextAlarmSection = true;
  int _defaultSnoozeDuration = 5;
  int _defaultMaxSnoozes = 3;
  bool _cloudSyncEnabled = false;
  
  final AuthService _authService = AuthService();
  final AlarmFirebaseService _alarmFirebaseService = AlarmFirebaseService();
  User? _currentUser;

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
    
    // Verificar estado de autenticación
    _currentUser = FirebaseAuth.instance.currentUser;

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
      });
    }
    _startOrUpdateCountdown(); // Start countdown after loading alarms
  }

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

  Future<void> _saveCloudSyncOption(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsScreen.cloudSyncKey, value);
    
    if (mounted) {
      setState(() {
        _cloudSyncEnabled = value;
      });
    }
    
    // Notificar a HomePage sobre el cambio de configuración
    try {
      // Buscar la instancia de HomePage en el stack de navegación
      final navigator = Navigator.of(context);
      final route = ModalRoute.of(context);
      if (route != null) {
        // Usar un callback o estado global para notificar el cambio
        // Por ahora, el usuario tendrá que reiniciar la app o volver a home
        // para que los cambios tomen efecto
      }
    } catch (e) {
      print('Error al notificar cambio de sincronización: $e');
    }
    
    // Si se activa el guardado en la nube, sincronizar todas las alarmas
    if (value && _currentUser != null) {
      await _syncAllAlarmsToCloud();
    }
  }

  Future<void> _syncAllAlarmsToCloud() async {
    try {
      if (_currentUser == null) return;
      
      // Obtener el ID de la colección del usuario
      final userData = await _authService.getUserData(_currentUser!.uid);
      if (userData == null) return;
      
      final userCollectionId = '${userData.name}_${userData.creationDate.millisecondsSinceEpoch}';
      
      // Actualizar todas las alarmas para que se sincronicen por defecto
      final prefs = await SharedPreferences.getInstance();
      final alarmsString = prefs.getStringList('alarms_list');
      if (alarmsString != null) {
        final alarms = alarmsString.map((s) => Alarm.fromJson(jsonDecode(s))).toList();
        
        // Actualizar alarmas para sincronización
        final updatedAlarms = alarms.map((alarm) => Alarm(
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
        )).toList();
        
        // Guardar alarmas actualizadas localmente
        final updatedAlarmsString = updatedAlarms.map((alarm) => jsonEncode(alarm.toJson())).toList();
        await prefs.setStringList('alarms_list', updatedAlarmsString);
        
        // Sincronizar con Firebase
        await _alarmFirebaseService.syncAllAlarms(updatedAlarms, userCollectionId);
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
                // Card para guardado en la nube
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guardado en la Nube',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentUser != null
                              ? 'Sincroniza tus alarmas con Firebase'
                              : 'Inicia sesión para habilitar esta función',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: Text(
                            'Activar guardado en la nube',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            _currentUser != null
                                ? 'Las alarmas se guardarán automáticamente en Firebase'
                                : 'Requiere iniciar sesión',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          value: _cloudSyncEnabled && _currentUser != null,
                          activeColor: Colors.green,
                          inactiveThumbColor: Colors.grey,
                          onChanged: _currentUser != null
                              ? (bool value) {
                                  _saveCloudSyncOption(value);
                                }
                              : null,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_currentUser == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushNamed('/login');
                              },
                              icon: const Icon(Icons.login),
                              label: const Text('Iniciar Sesión'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Card para autenticación
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
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Accede a tu cuenta para sincronizar tus alarmas',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
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
                // Add more settings here in separate Cards if needed
              ],
            ),
          ),
        ],
      ),
    );
  }
}
