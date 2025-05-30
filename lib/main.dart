import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Canal de comunicación con el código nativo
const platform = MethodChannel('com.example.the_good_alarm/alarm');

void main() {
  // Asegurarse de que las vinculaciones de Flutter estén inicializadas
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
        '/alarm': (context) => const AlarmPage(),
      },
      // Manejar rutas dinámicas que pueden venir desde el código nativo
      onGenerateRoute: (settings) {
        if (settings.name == '/alarm') {
          // Extraer argumentos si están disponibles
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => AlarmPage(
              alarmId: args?['alarmId'] as int? ?? 0,
            ),
          );
        }
        return null;
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, dynamic>> _alarms = [];
  List<Map<String, String>> _systemSounds = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkInitialRoute();
  }
  @override
  void initState() {
    super.initState();
    _loadSystemSounds();
    // Elimina _checkInitialRoute() de aquí
  }

  Future<void> _checkInitialRoute() async {
    try {
      // Obtener la ruta inicial si la aplicación se inició desde una notificación
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Map<String, dynamic>) {
        final screenRoute = args['screenRoute'] as String?;
        final alarmId = args['alarmId'] as int?;
        
        if (screenRoute != null && alarmId != null) {
          // Navegar a la pantalla de alarma
          Navigator.pushNamed(
            context,
            screenRoute,
            arguments: {'alarmId': alarmId},
          );
        }
      }
    } catch (e) {
      print('Error al verificar la ruta inicial: $e');
    }
  }

  Future<void> _loadSystemSounds() async {
    try {
      final result = await platform.invokeMethod('getSystemSounds');
      setState(() {
        _systemSounds = List<Map<String, String>>.from(
          (result as List).map((item) => Map<String, String>.from(item)),
        );
      });
    } on PlatformException catch (e) {
      print('Error al cargar sonidos del sistema: ${e.message}');
    }
  }

  Future<void> _setAlarm() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      // Calcular el tiempo en milisegundos
      final now = DateTime.now();
      var alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      // Si la hora seleccionada es anterior a la hora actual, programar para mañana
      if (alarmTime.isBefore(now)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      final alarmId = DateTime.now().millisecondsSinceEpoch % 10000;

      try {
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': alarmTime.millisecondsSinceEpoch,
          'alarmId': alarmId,
          'title': 'Alarma',
          'message': '¡Es hora de despertar!',
          'screenRoute': '/alarm',
        });

        setState(() {
          _alarms.add({
            'id': alarmId,
            'time': alarmTime,
            'title': 'Alarma',
            'message': '¡Es hora de despertar!',
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma configurada correctamente')),
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al configurar la alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _cancelAlarm(int alarmId) async {
    try {
      await platform.invokeMethod('cancelAlarm', {'alarmId': alarmId});
      setState(() {
        _alarms.removeWhere((alarm) => alarm['id'] == alarmId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarma cancelada correctamente')),
      );
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cancelar la alarma: ${e.message}')),
      );
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
                  title: Text('Alarma ${index + 1}'),
                  subtitle: Text(
                    '${alarm['time'].hour.toString().padLeft(2, '0')}:${alarm['time'].minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _cancelAlarm(alarm['id']),
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

class AlarmPage extends StatefulWidget {
  final int alarmId;

  const AlarmPage({super.key, this.alarmId = 0});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // Iniciar vibración y sonido cuando se muestra la pantalla de alarma
    _startAlarm();
  }

  Future<void> _startAlarm() async {
    try {
      // Patrón de vibración: 0ms de retraso, 500ms encendido, 500ms apagado, 500ms encendido
      await platform.invokeMethod('vibrate', {
        'pattern': [0, 500, 500, 500],
      });

      // Reproducir sonido de alarma predeterminado
      await platform.invokeMethod('playSound', {
        'soundUri': '',  // Uri vacío para usar el sonido predeterminado
      });

      setState(() {
        _isPlaying = true;
      });
    } on PlatformException catch (e) {
      print('Error al iniciar la alarma: ${e.message}');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await platform.invokeMethod('stopSound');
      setState(() {
        _isPlaying = false;
      });
    } on PlatformException catch (e) {
      print('Error al detener la alarma: ${e.message}');
    }
  }

  @override
  void dispose() {
    // Detener la alarma cuando se cierra la pantalla
    _stopAlarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade100,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.alarm,
              size: 100,
              color: Colors.red,
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Es hora de despertar!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                _stopAlarm();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              child: const Text(
                'Detener',
                style: TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                _stopAlarm();
                // Posponer la alarma por 5 minutos
                final now = DateTime.now();
                final snoozeTime = now.add(const Duration(minutes: 5));
                platform.invokeMethod('setAlarm', {
                  'timeInMillis': snoozeTime.millisecondsSinceEpoch,
                  'alarmId': widget.alarmId,
                  'title': 'Alarma (pospuesta)',
                  'message': '¡Es hora de despertar!',
                  'screenRoute': '/alarm',
                });
                Navigator.pop(context);
              },
              child: const Text(
                'Posponer 5 minutos',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
