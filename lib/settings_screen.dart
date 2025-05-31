import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlarmGroupingOption {
  none,
  twelveHour, // 2 groups of 12 hrs
  sixHour,    // 4 groups of 6 hrs
  fourHour,   // 6 groups of 4 hrs
  twoHour     // 12 groups of 2 hrs
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String alarmGroupingKey = 'alarm_grouping_option';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlarmGroupingOption _selectedGrouping = AlarmGroupingOption.none;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final groupingIndex = prefs.getInt(SettingsScreen.alarmGroupingKey) ?? AlarmGroupingOption.none.index;
    setState(() {
      _selectedGrouping = AlarmGroupingOption.values[groupingIndex];
    });
  }

  Future<void> _saveGroupingOption(AlarmGroupingOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.alarmGroupingKey, option.index);
    setState(() {
      _selectedGrouping = option;
    });
  }

  String _groupingOptionToString(AlarmGroupingOption option) {
    switch (option) {
      case AlarmGroupingOption.none:
        return 'Sin agrupar';
      case AlarmGroupingOption.twelveHour:
        return '2 grupos (12 hs c/u)';
      case AlarmGroupingOption.sixHour:
        return '4 grupos (6 hs c/u)';
      case AlarmGroupingOption.fourHour:
        return '6 grupos (4 hs c/u)';
      case AlarmGroupingOption.twoHour:
        return '12 grupos (2 hs c/u)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          Text(
            'Agrupación de Alarmas en Pantalla Principal',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Activar agrupación de alarmas'),
            value: _selectedGrouping != AlarmGroupingOption.none,
            onChanged: (bool value) {
              _saveGroupingOption(value ? AlarmGroupingOption.twelveHour : AlarmGroupingOption.none); // Default to 12hr if enabling
            },
          ),
          if (_selectedGrouping != AlarmGroupingOption.none)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Intervalo de agrupación:', style: Theme.of(context).textTheme.titleMedium),
                  RadioListTile<AlarmGroupingOption>(
                    title: Text(_groupingOptionToString(AlarmGroupingOption.twelveHour)),
                    value: AlarmGroupingOption.twelveHour,
                    groupValue: _selectedGrouping,
                    onChanged: (AlarmGroupingOption? value) {
                      if (value != null) _saveGroupingOption(value);
                    },
                  ),
                  RadioListTile<AlarmGroupingOption>(
                    title: Text(_groupingOptionToString(AlarmGroupingOption.sixHour)),
                    value: AlarmGroupingOption.sixHour,
                    groupValue: _selectedGrouping,
                    onChanged: (AlarmGroupingOption? value) {
                      if (value != null) _saveGroupingOption(value);
                    },
                  ),
                  RadioListTile<AlarmGroupingOption>(
                    title: Text(_groupingOptionToString(AlarmGroupingOption.fourHour)),
                    value: AlarmGroupingOption.fourHour,
                    groupValue: _selectedGrouping,
                    onChanged: (AlarmGroupingOption? value) {
                      if (value != null) _saveGroupingOption(value);
                    },
                  ),
                  RadioListTile<AlarmGroupingOption>(
                    title: Text(_groupingOptionToString(AlarmGroupingOption.twoHour)),
                    value: AlarmGroupingOption.twoHour,
                    groupValue: _selectedGrouping,
                    onChanged: (AlarmGroupingOption? value) {
                      if (value != null) _saveGroupingOption(value);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}