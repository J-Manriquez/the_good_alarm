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
    this.isActive = true, // Por defecto, la alarma está activa al crearse
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
        isActive: json['isActive'] as bool? ?? true, 
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
  static const platform = MethodChannel('com.example.the_good_alarm/alarm');

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
      case 'alarmManuallyStopped': // Cuando la alarma suena y se detiene desde la pantalla de alarma o notificación
        if (alarmId != null) {
          _toggleAlarmState(alarmId, false); // Marcar como inactiva
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

      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000;
      const title = 'Alarma';
      const message = '¡Es hora de despertar!';

      // La alarma se crea activa por defecto (isActive = true en el constructor de Alarm)
      final newAlarm = Alarm(
        id: alarmId,
        time: alarmTime,
        title: title,
        message: message,
      );

      try {
        // Solo se programa en Android si está activa
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': alarmTime.millisecondsSinceEpoch,
          'alarmId': alarmId,
          'title': title,
          'message': message,
          'screenRoute': '/alarm',
        });

        setState(() {
          _alarms.add(newAlarm);
        });
        await _saveAlarms();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma configurada y activa')),
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al configurar alarma: ${e.message}')),
        );
      }
    }
  }

  // Modificado para manejar la activación/desactivación de la alarma
  Future<void> _toggleAlarmState(int alarmId, bool isActive) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      setState(() {
        alarm.isActive = isActive;
      });

      try {
        if (isActive) {
          // Si se activa, programar la alarma
          await platform.invokeMethod('setAlarm', {
            'timeInMillis': alarm.time.millisecondsSinceEpoch,
            'alarmId': alarm.id,
            'title': alarm.title,
            'message': alarm.message,
            'screenRoute': '/alarm',
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarma activada')),
          );
        } else {
          // Si se desactiva, cancelar la alarma programada
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarma desactivada')),
          );
        }
        await _saveAlarms();
      } on PlatformException catch (e) {
        // Revertir el estado si hay un error con la plataforma nativa
        setState(() {
          alarm.isActive = !isActive;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ${isActive ? "activar" : "desactivar"} alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _deleteAlarm(int alarmId) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      try {
        // Si la alarma estaba activa, también cancelarla en la plataforma nativa
        if (alarm.isActive) {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
        }
        setState(() {
          _alarms.removeAt(index);
        });
        await _saveAlarms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma eliminada')),
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar alarma: ${e.message}')),
        );
      }
    }
  }

  // Ya no se usa _markAlarmAsInactive, se usa _toggleAlarmState
  // Future<void> _markAlarmAsInactive(int alarmId) async { ... }

  Future<void> _updateAlarmTime(int alarmId, DateTime newTime) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final oldAlarm = _alarms[index];
      final newAlarmData = Alarm(
        id: oldAlarm.id,
        time: newTime,
        title: oldAlarm.title, 
        message: oldAlarm.message,
        isActive: true, // Al posponer, la alarma se reactiva
      );

      try {
        // Cancelar la anterior si estaba activa
        if (oldAlarm.isActive) {
          await platform.invokeMethod('cancelAlarm', {'alarmId': oldAlarm.id});
        }
        // Programar la nueva
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': newAlarmData.time.millisecondsSinceEpoch,
          'alarmId': newAlarmData.id,
          'title': newAlarmData.title,
          'message': newAlarmData.message,
          'screenRoute': '/alarm',
        });

        setState(() {
          _alarms[index] = newAlarmData;
        });
        await _saveAlarms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma pospuesta y reactivada')),
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al posponer alarma: ${e.message}')),
        );
      }
    }
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
                  leading: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String result) {
                      if (result == 'delete') {
                        _deleteAlarm(alarm.id);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Eliminar'),
                      ),
                    ],
                  ),
                  title: Text(alarm.title),
                  subtitle: Text(
                    '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: Switch(
                    value: alarm.isActive,
                    onChanged: (bool value) {
                      _toggleAlarmState(alarm.id, value);
                    },
                    activeColor: Colors.green, // Color cuando está activo
                    inactiveThumbColor: Colors.black, // Color del "pulgar" cuando está inactivo
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