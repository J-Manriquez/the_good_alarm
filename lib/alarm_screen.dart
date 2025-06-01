import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para MethodChannel y PlatformException

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
  static const platform = MethodChannel('com.example.the_good_alarm/alarm');

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
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 85.0),
          child: Text('Alarma Activa', style: TextStyle(fontSize: 25, color: Colors.white, fontWeight: FontWeight.bold),),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white, size: 30,),
            onPressed: () {
              Navigator.of(context).pushNamed('/');
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: const Color.fromARGB(255, 255, 255, 255)),
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _snoozeAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
                      foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Retrasar 1 minuto',
                      style: TextStyle(fontSize: 18),
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
