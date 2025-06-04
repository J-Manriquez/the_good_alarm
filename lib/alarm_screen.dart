import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/settings_screen.dart'; // Necesario para MethodChannel y PlatformException

class AlarmScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const AlarmScreen({super.key, this.arguments});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  int alarmId = 0;
  String title = 'Alarma';
  String message = '¡Es hora de despertar!';
  int snoozeCount = 0;
  int maxSnoozes = 3;
  int snoozeDurationMinutes = 5; // Valor por defecto
  static const platform = MethodChannel('com.example.the_good_alarm/alarm');

  @override
  void initState() {
    super.initState();
    _loadSnoozeSettings();

    if (widget.arguments != null) {
      alarmId = widget.arguments!['alarmId'] ?? 0;
      title = widget.arguments!['title'] ?? 'Alarma';
      message = widget.arguments!['message'] ?? '¡Es hora de despertar!';
      snoozeCount = widget.arguments!['snoozeCount'] ?? 0;
      maxSnoozes = widget.arguments!['maxSnoozes'] ?? 3;
      snoozeDurationMinutes = widget.arguments!['snoozeDurationMinutes']?? 5;

      // Cargar la duración del snooze desde SharedPreferences
      _loadSnoozeDuration();
      
      // NUEVO: Notificar que la alarma está sonando cuando se abre la pantalla
      _notifyAlarmRinging();
    }
  }

  // NUEVO: Método para notificar que la alarma está sonando
  Future<void> _notifyAlarmRinging() async {
    try {
      await platform.invokeMethod('notifyAlarmRinging', {
        'alarmId': alarmId,
        'title': title,
        'message': message,
        'snoozeCount': snoozeCount,
        'maxSnoozes': maxSnoozes,
        'snoozeDurationMinutes': snoozeDurationMinutes,
      });
    } catch (e) {
      print('Error notifying alarm ringing: $e');
    }
  }

  // NUEVO: Cargar configuración de snooze
  Future<void> _loadSnoozeSettings() async {
    print('=== LOAD SNOOZE SETTINGS START ===');
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeDuration = prefs.getInt('snooze_duration_minutes') ?? 5;

      setState(() {
        snoozeDurationMinutes = snoozeDuration;
      });

      print('Loaded snooze duration: $snoozeDurationMinutes minutes');
    } catch (e) {
      print('Error loading snooze settings: $e');
    }
    print('=== LOAD SNOOZE SETTINGS END ===');
  }

  Future<void> _loadSnoozeDuration() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        snoozeDurationMinutes = prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
      });
    }
  }

  Future<void> _stopAlarm() async {
    if (alarmId != 0) {
      try {
        await platform.invokeMethod('stopAlarm', {'alarmId': alarmId});
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al detener alarma: ${e.message}')),
        );
      }
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  
  Future<void> _snoozeAlarm() async {
    print('=== SNOOZE ALARM START ===');
    print('Snoozing alarm ID: $alarmId for $snoozeDurationMinutes minutes');
    print('Current snooze count: $snoozeCount, max: $maxSnoozes');
    
    if (snoozeCount >= maxSnoozes) {
      print('Maximum snoozes reached, cannot snooze anymore');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo de posposiciones alcanzado')),
      );
      return;
    }
    
    try {
      await platform.invokeMethod('snoozeAlarm', {
        'alarmId': alarmId,
        'maxSnoozes': maxSnoozes,  // AGREGAR
        'snoozeDurationMinutes': snoozeDurationMinutes,  // AGREGAR
      });
      print('Snooze command sent to native code');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error snoozing alarm: $e');
    }
    print('=== SNOOZE ALARM END ===');
  }

  @override
  Widget build(BuildContext context) {
    // Determinar si se puede posponer
    final canSnooze = snoozeCount < maxSnoozes;
    print('Can snooze: $canSnooze (count: $snoozeCount, max: $maxSnoozes)');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 85.0),
          child: Text(
            'Alarma Activa',
            style: TextStyle(
              fontSize: 25,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white, size: 30),
            onPressed: () {
              // MODIFICADO: Usar pop en lugar de pushNamed para volver a la instancia existente
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromARGB(255, 255, 255, 255),
              Color.fromARGB(255, 255, 255, 255),
            ],
          ),
        ),
        child: Center(
          child: Card(
            color: const Color.fromARGB(255, 0, 0, 0),
            margin: const EdgeInsets.all(30.0),
            elevation: 8.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color.fromARGB(255, 255, 255, 255),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double
                        .infinity, // Esto hace que el botón ocupe todo el ancho disponible
                    child: ElevatedButton(
                      onPressed: _stopAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Apagar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (canSnooze)
                    // En el método build
                    ElevatedButton(
                      onPressed: _snoozeAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          255,
                          255,
                          255,
                        ),
                        foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Posponer $snoozeDurationMinutes min',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Mostrar un mensaje si se ha alcanzado el máximo de snoozes
                  if (!canSnooze)
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        'Número máximo de alarmas pospuestas alcanzado \n($snoozeCount/$maxSnoozes)',
                        style: TextStyle(
                          color: Colors.white,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
