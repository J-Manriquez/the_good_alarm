import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'dart:async'; // Required for Timer
import 'home_page.dart'; // To access Alarm model and potentially _formatDuration

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


  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlarmGroupingOption _selectedGrouping = AlarmGroupingOption.none;
  bool _showNextAlarmSection = true;


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
    final snoozeDuration =
        prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
    final maxSnoozes =
        prefs.getInt(SettingsScreen.maxSnoozesKey) ?? 3;

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
      
      });
    }
    _startOrUpdateCountdown(); // Start countdown after loading alarms
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
      );
    }
  }
  
  return nextAlarm;
}

DateTime _calculateNextOccurrence(Alarm alarm, DateTime now) {
  DateTime nextTime = alarm.time;
  
  if (alarm.isDaily) {
    if (nextTime.isBefore(now) || nextTime.isAtSameMomentAs(now)) {
      nextTime = DateTime(now.year, now.month, now.day, alarm.time.hour, alarm.time.minute)
          .add(const Duration(days: 1));
    }
  } else if (alarm.isWeekly) {
    final targetWeekday = alarm.time.weekday;
    int daysUntilNext = (targetWeekday - now.weekday) % 7;
    if (daysUntilNext == 0 && nextTime.isBefore(now)) {
      daysUntilNext = 7;
    }
    nextTime = DateTime(now.year, now.month, now.day, alarm.time.hour, alarm.time.minute)
        .add(Duration(days: daysUntilNext));
  } else if (alarm.isWeekend) {
    DateTime nextSaturday = now.add(Duration(days: (DateTime.saturday - now.weekday) % 7));
    DateTime nextSunday = now.add(Duration(days: (DateTime.sunday - now.weekday) % 7));
    
    if (nextSaturday.isBefore(now)) nextSaturday = nextSaturday.add(const Duration(days: 7));
    if (nextSunday.isBefore(now)) nextSunday = nextSunday.add(const Duration(days: 7));
    
    nextTime = nextSaturday.isBefore(nextSunday) ? 
        DateTime(nextSaturday.year, nextSaturday.month, nextSaturday.day, alarm.time.hour, alarm.time.minute) :
        DateTime(nextSunday.year, nextSunday.month, nextSunday.day, alarm.time.hour, alarm.time.minute);
  } else if (alarm.repeatDays.isNotEmpty) {
    int daysToAdd = 1;
    while (daysToAdd <= 7) {
      final testDate = now.add(Duration(days: daysToAdd));
      if (alarm.repeatDays.contains(testDate.weekday)) {
        nextTime = DateTime(testDate.year, testDate.month, testDate.day, alarm.time.hour, alarm.time.minute);
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

                // Add more settings here in separate Cards if needed
              ],
            ),
          ),
        ],
      ),
    );
  }
}
