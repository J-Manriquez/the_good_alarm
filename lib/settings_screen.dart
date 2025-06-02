import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  int _snoozeDuration = 5; // Valor predeterminado: 5 minutos
  int _maxSnoozes = 3; // Valor predeterminado: 3 veces

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
        _snoozeDuration = snoozeDuration;
        _maxSnoozes = maxSnoozes;
      
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

  Future<void> _saveSnoozeDuration(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.snoozeDurationKey, minutes);
    if (mounted) {
      setState(() {
        _snoozeDuration = minutes;
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

  Future<void> _saveMaxSnoozes(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.maxSnoozesKey, count);
    if (mounted) {
      setState(() {
        _maxSnoozes = count;
      });
    }
  }

  // --- Countdown Logic (adapted from HomePage) ---
  Alarm? _getNextActiveAlarm() {
    final activeAlarms = _alarms.where((a) => a.isActive).toList();
    if (activeAlarms.isEmpty) return null;
    // Already sorted in _loadSettingsAndAlarms, but good to ensure
    activeAlarms.sort((a, b) => a.time.compareTo(b.time));
    return activeAlarms.first;
  }

  void _startOrUpdateCountdown() {
    _countdownTimer?.cancel();
    _currentNextAlarmForCountdown = _getNextActiveAlarm();

    if (_currentNextAlarmForCountdown != null) {
      _updateCountdown();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    if (_currentNextAlarmForCountdown == null ||
        !_currentNextAlarmForCountdown!.isActive) {
      _startOrUpdateCountdown(); // Re-evaluate if current alarm is no longer valid
      return;
    }
    final now = DateTime.now();
    final difference = _currentNextAlarmForCountdown!.time.isAfter(now)
        ? _currentNextAlarmForCountdown!.time.difference(now)
        : Duration.zero;

    if (mounted) {
      setState(() {
        _timeUntilNextAlarm = difference;
      });
    }

    // If time has passed, and it's not just a brief moment (e.g. due to app resume)
    if (difference == Duration.zero &&
        _currentNextAlarmForCountdown!.time.isBefore(
          now.subtract(const Duration(seconds: 1)),
        )) {
      _startOrUpdateCountdown(); // Refresh to find next alarm or clear countdown
    }
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) {
      return "--:--:--";
    }
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours.remainder(24));
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inDays > 0) {
      String days = duration.inDays.toString();
      return "$days Días: $hours:$minutes:$seconds";
    }
    return "$hours:$minutes:$seconds";
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
              color: Colors.green, // Or your preferred color
              child: Text(
                'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
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
                // Tarjeta para configuración de Snooze
                Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuración de Posponer (Snooze)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        
                        // Duración del Snooze
                        Text(
                          'Duración: $_snoozeDuration minutos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _snoozeDuration.toDouble(),
                          min: 1,
                          max: 30,
                          divisions: 29,
                          label: '$_snoozeDuration min',
                          onChanged: (double value) {
                            _saveSnoozeDuration(value.toInt());
                          },
                          activeColor: Colors.green,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('1 min'),
                            Text('15 min'),
                            Text('30 min'),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Número máximo de Snoozes
                        Text(
                          'Número máximo: $_maxSnoozes veces',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: _maxSnoozes.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_maxSnoozes veces',
                          onChanged: (double value) {
                            _saveMaxSnoozes(value.toInt());
                          },
                          activeColor: Colors.green,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('1 vez'),
                            Text('5 veces'),
                            Text('10 veces'),
                          ],
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
