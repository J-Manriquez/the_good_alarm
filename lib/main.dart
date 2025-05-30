import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';

const platform = MethodChannel('com.example.the_good_alarm/alarm');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Good Alarm',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        // Asegúrate de que AlarmScreen pueda manejar argumentos nulos si se navega directamente
        '/alarm': (context) => AlarmScreen(
          arguments: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?,
        ),
      },
    );
  }
}

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
  // List<Map<String, String>> _systemSounds = []; // Si aún lo usas
  static const String _alarmsKey = 'alarms_list';

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
        // Asegúrate de que el contexto es válido antes de navegar
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
         // Si la pantalla de alarma está abierta y coincide el ID, ciérrala.
         // Esto es un poco más complejo de implementar directamente aquí
         // ya que necesitarías una forma de que AlarmScreen escuche este evento.
         // Por ahora, la navegación desde AlarmScreen se encarga de cerrarla.
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
        // Opcional: Re-programar alarmas activas si la app se reinició
        // _rescheduleActiveAlarms(); 
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

  // Marcar alarma como inactiva en lugar de borrarla
  Future<void> _markAlarmAsInactive(int alarmId) async {
    setState(() {
      final index = _alarms.indexWhere((a) => a.id == alarmId);
      if (index != -1) {
        _alarms[index].isActive = false;
      }
    });
    await _saveAlarms();
  }

  // Actualizar la hora de una alarma (para posponer)
  Future<void> _updateAlarmTime(int alarmId, DateTime newTime) async {
    setState(() {
      final index = _alarms.indexWhere((a) => a.id == alarmId);
      if (index != -1) {
        _alarms[index] = Alarm(
          id: _alarms[index].id,
          time: newTime,
          title: _alarms[index].title, // O actualizar si es necesario
          message: _alarms[index].message,
          isActive: true, // Se reactiva al posponer
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
                    : IconButton( // Opción para reactivar o borrar alarmas pasadas
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

class AlarmScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const AlarmScreen({Key? key, this.arguments}) : super(key: key);

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  int alarmId = 0;
  String title = 'Alarma';
  String message = '¡Es hora de despertar!';
  // bool initialized = false; // No es necesario con el constructor

  @override
  void initState() {
    super.initState();
    if (widget.arguments != null) {
        alarmId = widget.arguments!['alarmId'] ?? 0;
        title = widget.arguments!['title'] ?? 'Alarma';
        message = widget.arguments!['message'] ?? '¡Es hora de despertar!';
    }
  }

  // @override
  // void didChangeDependencies() {
  //   super.didChangeDependencies();
  //   if (!initialized) {
  //     final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
  //     if (args != null) {
  //       alarmId = args['alarmId'] ?? 0;
  //       title = args['title'] ?? 'Alarma';
  //       message = args['message'] ?? '¡Es hora de despertar!';
  //     }
  //     initialized = true;
  //   }
  // }

  Future<void> _stopAlarm() async {
    if (alarmId != 0) {
      await platform.invokeMethod('stopAlarm', {'alarmId': alarmId});
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _snoozeAlarm() async {
    if (alarmId != 0) {
      await platform.invokeMethod('snoozeAlarm', {'alarmId': alarmId});
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _stopAlarm,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
              child: const Text('Apagar', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _snoozeAlarm,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
              child: const Text('Retrasar 1 minuto', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
