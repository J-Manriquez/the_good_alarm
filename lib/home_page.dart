import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación

// Modelo simple para la alarma
class Alarm {
  final int id;
  final DateTime time;
  final String title;
  final String message;
  bool isActive; // Para saber si la alarma está activa o ya sonó

  Alarm({
    required this.id,
    required this.time,
    required this.title,
    required this.message,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'title': title,
        'message': message,
        'isActive': isActive,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'] as int,
        time: DateTime.parse(json['time'] as String),
        title: json['title'] as String,
        message: json['message'] as String,
        isActive: json['isActive'] as bool? ?? true, // Valor por defecto si no existe
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Alarm> _alarms = [];
  static const String _alarmsKey = 'alarms_list';
  static const platform = MethodChannel('com.example.the_good_alarm/alarm'); // Mover el MethodChannel aquí si solo se usa en HomePage

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler(_handleNativeCalls);
    _loadAlarms();
  }

  Future<void> _handleNativeCalls(MethodCall call) async {
    final args = call.arguments != null ? Map<String, dynamic>.from(call.arguments) : {};
    final alarmId = args['alarmId'] as int?;

    switch (call.method) {
      case 'showAlarmScreen':
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/alarm',
            (route) => false,
            arguments: args,
          );
        }
        break;
      case 'alarmManuallyStopped':
        if (alarmId != null) {
          _markAlarmAsInactive(alarmId);
        }
        break;
      case 'alarmManuallySnoozed':
        if (alarmId != null) {
          final newTimeInMillis = args['newTimeInMillis'] as int?;
          if (newTimeInMillis != null) {
            _updateAlarmTime(alarmId, DateTime.fromMillisecondsSinceEpoch(newTimeInMillis));
          }
        }
        break;
      case 'closeAlarmScreenIfOpen':
        // Lógica para cerrar AlarmScreen si es necesario
        break;
    }
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmsString = prefs.getStringList(_alarmsKey);
    if (alarmsString != null) {
      setState(() {
        _alarms.clear();
        _alarms.addAll(alarmsString.map((s) => Alarm.fromJson(jsonDecode(s))));
      });
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmsString = _alarms.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(_alarmsKey, alarmsString);
  }

  Future<void> _setAlarm() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null && mounted) {
      final now = DateTime.now();
      var alarmTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      if (alarmTime.isBefore(now)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000; // ID único
      const title = 'Alarma';
      const message = '¡Es hora de despertar!';

      try {
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': alarmTime.millisecondsSinceEpoch,
          'alarmId': alarmId,
          'title': title,
          'message': message,
          'screenRoute': '/alarm',
        });

        final newAlarm = Alarm(
          id: alarmId,
          time: alarmTime,
          title: title,
          message: message,
        );
        setState(() {
          _alarms.add(newAlarm);
        });
        await _saveAlarms();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma configurada')), 
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al configurar alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _cancelAlarm(int alarmId) async {
    try {
      await platform.invokeMethod('cancelAlarm', {'alarmId': alarmId});
      setState(() {
        _alarms.removeWhere((alarm) => alarm.id == alarmId);
      });
      await _saveAlarms();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarma cancelada')), 
      );
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cancelar alarma: ${e.message}')),
      );
    }
  }

  Future<void> _markAlarmAsInactive(int alarmId) async {
    setState(() {
      final index = _alarms.indexWhere((a) => a.id == alarmId);
      if (index != -1) {
        _alarms[index].isActive = false;
      }
    });
    await _saveAlarms();
  }

  Future<void> _updateAlarmTime(int alarmId, DateTime newTime) async {
    setState(() {
      final index = _alarms.indexWhere((a) => a.id == alarmId);
      if (index != -1) {
        _alarms[index] = Alarm(
          id: _alarms[index].id,
          time: newTime,
          title: _alarms[index].title,
          message: _alarms[index].message,
          isActive: true,
        );
      }
    });
    await _saveAlarms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('The Good Alarm'),
      ),
      body: _alarms.isEmpty
          ? const Center(child: Text('No hay alarmas configuradas'))
          : ListView.builder(
              itemCount: _alarms.length,
              itemBuilder: (context, index) {
                final alarm = _alarms[index];
                return ListTile(
                  title: Text(alarm.title),
                  subtitle: Text(
                    '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')} - ${alarm.isActive ? "Activa" : "Sonó"}',
                  ),
                  trailing: alarm.isActive 
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _cancelAlarm(alarm.id),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () { /* Lógica para reactivar o borrar */ },
                      ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _setAlarm,
        tooltip: 'Añadir alarma',
        child: const Icon(Icons.add),
      ),
    );
  }
}