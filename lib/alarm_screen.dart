import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para MethodChannel y PlatformException

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
  static const platform = MethodChannel('com.example.the_good_alarm/alarm'); // Mover el MethodChannel aquí si solo se usa en AlarmScreen

  @override
  void initState() {
    super.initState();
    if (widget.arguments != null) {
        alarmId = widget.arguments!['alarmId'] ?? 0;
        title = widget.arguments!['title'] ?? 'Alarma';
        message = widget.arguments!['message'] ?? '¡Es hora de despertar!';
    }
  }

  Future<void> _stopAlarm() async {
    if (alarmId != 0) {
      try {
        await platform.invokeMethod('stopAlarm', {'alarmId': alarmId});
      } on PlatformException catch (e) {
        // Manejar el error, por ejemplo, mostrar un SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al detener alarma: ${e.message}')),
        );
      }
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _snoozeAlarm() async {
    if (alarmId != 0) {
      try {
        await platform.invokeMethod('snoozeAlarm', {'alarmId': alarmId});
      } on PlatformException catch (e) {
        // Manejar el error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al posponer alarma: ${e.message}')),
        );
      }
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