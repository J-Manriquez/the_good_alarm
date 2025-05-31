import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación
import 'settings_screen.dart'; // Importar SettingsScreen

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

  AlarmGroupingOption _currentGroupingOption = AlarmGroupingOption.none;
  Map<String, bool> _groupExpansionState =
      {}; // Para controlar la expansión de cada grupo
  Map<String, bool> _groupShowActiveOnlyState =
      {}; // Para controlar si se muestran solo activas por grupo
  bool _showNextAlarmSection =
      true; // Nuevo estado para la sección de próxima alarma
  static const String _showNextAlarmKey =
      'show_next_alarm'; // Key para SharedPreferences

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler(_handleNativeCalls);
    _loadSettingsAndAlarms(); // Cargar configuración primero
  }

  Future<void> _loadSettingsAndAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final groupingIndex =
        prefs.getInt(SettingsScreen.alarmGroupingKey) ??
        AlarmGroupingOption.none.index;
    _currentGroupingOption = AlarmGroupingOption.values[groupingIndex];
    _showNextAlarmSection =
        prefs.getBool(_showNextAlarmKey) ?? true; // Cargar preferencia
    await _loadAlarms(); // Cargar alarmas después de la configuración
    // Inicializar el estado de expansión para los grupos si es necesario
    if (_currentGroupingOption != AlarmGroupingOption.none) {
      _initializeGroupStates();
    }
    if (mounted) setState(() {});
  }

  void _initializeGroupStates() {
    final groups = _getGroupedAlarms();
    _groupExpansionState = {
      for (var group in groups.keys) group: false,
    }; // Por defecto colapsados
    _groupShowActiveOnlyState = {
      for (var group in groups.keys) group: false,
    }; // Por defecto mostrar todas
  }

  Future<Map<String, String>?> _showAlarmDetailsDialog({
    String? initialTitle,
    String? initialMessage,
  }) async {
    final titleController = TextEditingController(text: initialTitle);
    final messageController = TextEditingController(text: initialMessage);
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false, // User must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(initialTitle == null ? 'Nueva Alarma' : 'Editar Alarma'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: ListBody(
                children: <Widget>[
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: 'Título'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, ingrese un título';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      hintText: 'Mensaje (opcional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop(null);
              },
            ),
            TextButton(
              child: const Text('Guardar'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop({
                    'title': titleController.text,
                    'message': messageController.text,
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleNativeCalls(MethodCall call) async {
    final args = call.arguments != null
        ? Map<String, dynamic>.from(call.arguments)
        : {};
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
          _toggleAlarmState(alarmId, false);
        }
        break;
      case 'alarmManuallySnoozed':
        if (alarmId != null) {
          final newTimeInMillis = args['newTimeInMillis'] as int?;
          if (newTimeInMillis != null) {
            _updateAlarmTime(
              alarmId,
              DateTime.fromMillisecondsSinceEpoch(newTimeInMillis),
            );
          }
        }
        break;
      case 'closeAlarmScreenIfOpen':
        break;
    }
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmsString = prefs.getStringList(_alarmsKey);
    if (alarmsString != null) {
      _alarms.clear();
      _alarms.addAll(alarmsString.map((s) => Alarm.fromJson(jsonDecode(s))));
      _alarms.sort((a, b) => a.time.compareTo(b.time)); // Asegurar orden
    }
    // No llamar a setState aquí, se llama en _loadSettingsAndAlarms
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmsString = _alarms.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(_alarmsKey, alarmsString);
    // Si se guardan alarmas, puede que necesitemos re-inicializar los grupos
    if (_currentGroupingOption != AlarmGroupingOption.none) {
      _initializeGroupStates(); // Re-evaluar grupos si cambian las alarmas
    }
    if (mounted) setState(() {});
  }

  Future<void> _setAlarm() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null && mounted) {
      final alarmDetails = await _showAlarmDetailsDialog();
      if (alarmDetails == null) return;

      final now = DateTime.now();
      // Normalize alarmTime to have 0 seconds and 0 milliseconds
      var alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
        0, // seconds
        0, // milliseconds
      );

      // If the normalized alarm time is before or exactly now, set it for the next day.
      // Using isBefore or equals now, considering only H:M precision.
      final nowNormalized = DateTime(now.year, now.month, now.day, now.hour, now.minute, 0, 0);
      if (alarmTime.isBefore(nowNormalized) || alarmTime.isAtSameMomentAs(nowNormalized)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000;
      final title = alarmDetails['title']!.isNotEmpty
          ? alarmDetails['title']!
          : 'Alarma';
      final message = alarmDetails['message']!.isNotEmpty
          ? alarmDetails['message']!
          : '¡Es hora de despertar!';

      final newAlarm = Alarm(
        id: alarmId,
        time: alarmTime,
        title: title,
        message: message,
      );

      try {
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': alarmTime.millisecondsSinceEpoch,
          'alarmId': alarmId,
          'title': title,
          'message': message,
          'screenRoute': '/alarm',
        });
        _alarms.add(newAlarm);
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

  Future<void> _editAlarm(Alarm alarmToEdit) async {
    final TimeOfDay? newTimeOfDay = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(alarmToEdit.time),
    );
    if (newTimeOfDay == null) return;

    final alarmDetails = await _showAlarmDetailsDialog(
      initialTitle: alarmToEdit.title,
      initialMessage: alarmToEdit.message,
    );
    // Use existing details if new ones are not provided or dialog is cancelled
    final String title = alarmDetails?['title'] ?? alarmToEdit.title;
    final String message = alarmDetails?['message'] ?? alarmToEdit.message;

    if (mounted) {
      final now = DateTime.now();
      // Normalize newAlarmTime to have 0 seconds and 0 milliseconds
      var newAlarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        newTimeOfDay.hour,
        newTimeOfDay.minute,
        0, // seconds
        0, // milliseconds
      );

      // If the normalized alarm time is before or exactly now, set it for the next day.
      final nowNormalized = DateTime(now.year, now.month, now.day, now.hour, now.minute, 0, 0);
      if (newAlarmTime.isBefore(nowNormalized) || newAlarmTime.isAtSameMomentAs(nowNormalized)) {
        newAlarmTime = newAlarmTime.add(const Duration(days: 1));
      }

      try {
        if (alarmToEdit.isActive) {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarmToEdit.id});
        }
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': newAlarmTime.millisecondsSinceEpoch,
          'alarmId': alarmToEdit.id, // Use existing ID for editing
          'title': title,
          'message': message,
          'screenRoute': '/alarm',
        });

        final index = _alarms.indexWhere((a) => a.id == alarmToEdit.id);
        if (index != -1) {
          _alarms[index] = Alarm(
            id: alarmToEdit.id,
            time: newAlarmTime,
            title: title,
            message: message,
            isActive: true, // Edited alarm should be active
          );
        }
        await _saveAlarms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma actualizada y activa')),
        );
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _toggleAlarmState(int alarmId, bool isActive) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      alarm.isActive = isActive;
      try {
        if (isActive) {
          await platform.invokeMethod('setAlarm', {
            'timeInMillis': alarm.time.millisecondsSinceEpoch,
            'alarmId': alarm.id,
            'title': alarm.title,
            'message': alarm.message,
            'screenRoute': '/alarm',
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Alarma activada')));
        } else {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Alarma desactivada')));
        }
        _alarms[index].isActive = isActive;
        await _saveAlarms(); // Esto llamará a setState y re-inicializará grupos
      } on PlatformException catch (e) {
        setState(() {
          alarm.isActive = !isActive; // Revertir
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al ${isActive ? "activar" : "desactivar"} alarma: ${e.message}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteAlarm(int alarmId) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      try {
        if (alarm.isActive) {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
        }
        _alarms.removeAt(index);
        await _saveAlarms(); // Esto llamará a setState y re-inicializará grupos
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alarma eliminada')));
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _updateAlarmTime(int alarmId, DateTime newTime) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final oldAlarm = _alarms[index];
      final newAlarmData = Alarm(
        id: oldAlarm.id,
        time: newTime,
        title: oldAlarm.title,
        message: oldAlarm.message,
        isActive: true,
      );
      try {
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': newAlarmData.time.millisecondsSinceEpoch,
          'alarmId': newAlarmData.id,
          'title': newAlarmData.title,
          'message': newAlarmData.message,
          'screenRoute': '/alarm',
        });
        _alarms[index] = newAlarmData;
        await _saveAlarms(); // Esto llamará a setState y re-inicializará grupos
      } on PlatformException catch (e) {
        print(
          'Error al actualizar la hora de la alarma (snooze): ${e.message}',
        );
      }
    }
  }

  Map<String, List<Alarm>> _getGroupedAlarms() {
    Map<String, List<Alarm>> grouped = {};
    if (_currentGroupingOption == AlarmGroupingOption.none) return {};

    int groupSizeHours;
    switch (_currentGroupingOption) {
      case AlarmGroupingOption.twelveHour:
        groupSizeHours = 12;
        break;
      case AlarmGroupingOption.sixHour:
        groupSizeHours = 6;
        break;
      case AlarmGroupingOption.fourHour:
        groupSizeHours = 4;
        break;
      case AlarmGroupingOption.twoHour:
        groupSizeHours = 2;
        break;
      default:
        return {};
    }

    for (int i = 0; i < 24; i += groupSizeHours) {
      final startHour = i;
      final endHour = (i + groupSizeHours - 1) % 24;
      final groupKey =
          '${startHour.toString().padLeft(2, '0')}:00 - ${endHour.toString().padLeft(2, '0')}:59';
      grouped[groupKey] = [];
    }

    for (var alarm in _alarms) {
      int alarmHour = alarm.time.hour;
      for (var groupKey in grouped.keys) {
        final parts = groupKey.split(' - ');
        final startHour = int.parse(parts[0].split(':')[0]);
        final endHour = int.parse(parts[1].split(':')[0]);

        // Manejar rangos que cruzan la medianoche para la última cubeta del día
        if (startHour <= endHour) {
          // Rango normal (e.g., 06:00 - 11:59)
          if (alarmHour >= startHour && alarmHour <= endHour) {
            grouped[groupKey]!.add(alarm);
            break;
          }
        } else {
          // Rango que cruza la medianoche (e.g., 22:00 - 01:59) - esto es para el último grupo si groupSizeHours no divide 24
          // Esta lógica se simplifica si asumimos que los grupos no cruzan la medianoche de forma extraña
          // Para los grupos definidos (12,6,4,2), siempre se alinearán bien dentro de las 24h.
          // La clave es que endHour es el final del bucket, no el inicio del siguiente.
          // Ejemplo: 2 horas -> 00-01, 02-03, ..., 22-23.
          // El endHour calculado como (i + groupSizeHours -1) % 24 asegura esto.
          if (alarmHour >= startHour && alarmHour <= endHour) {
            // Esta condición es suficiente
            grouped[groupKey]!.add(alarm);
            break;
          }
        }
      }
    }
    // Ordenar alarmas dentro de cada grupo
    grouped.forEach((key, value) {
      value.sort((a, b) => a.time.compareTo(b.time));
    });
    return grouped;
  }

  Alarm? _getNextActiveAlarm() {
    final activeAlarms = _alarms.where((a) => a.isActive).toList();
    if (activeAlarms.isEmpty) return null;
    activeAlarms.sort((a, b) => a.time.compareTo(b.time));
    return activeAlarms.first;
  }

  Widget _buildNextAlarmSection() {
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null || !_showNextAlarmSection)
      return const SizedBox.shrink();

    final otherActiveAlarmsCount = _alarms
        .where((a) => a.isActive && a.id != nextAlarm.id)
        .length;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Próxima Alarma: ${TimeOfDay.fromDateTime(nextAlarm.time).format(context)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              nextAlarm.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (nextAlarm.message.isNotEmpty)
              Text(
                nextAlarm.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  otherActiveAlarmsCount > 0
                      ? '$otherActiveAlarmsCount otra${otherActiveAlarmsCount > 1 ? 's' : ''} alarma${otherActiveAlarmsCount > 1 ? 's' : ''} activa${otherActiveAlarmsCount > 1 ? 's' : ''}'
                      : 'No hay otras alarmas activas',
                ),
                Switch(
                  value: nextAlarm.isActive,
                  onChanged: (bool value) {
                    _toggleAlarmState(nextAlarm.id, value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmItem(Alarm alarm) {
    return ListTile(
      leading: PopupMenuButton<String>(
        onSelected: (String result) {
          if (result == 'delete') {
            _deleteAlarm(alarm.id);
          } else if (result == 'edit') {
            _editAlarm(alarm);
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
          const PopupMenuItem<String>(value: 'delete', child: Text('Eliminar')),
        ],
      ),
      title: Text(alarm.title),
      subtitle: Text(
        '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')} - ${alarm.message}',
      ),
      trailing: Switch(
        value: alarm.isActive,
        onChanged: (bool value) {
          _toggleAlarmState(alarm.id, value);
        },
        activeColor: Colors.green,
        inactiveThumbColor: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<Alarm>> groupedAlarms =
        _currentGroupingOption != AlarmGroupingOption.none
        ? _getGroupedAlarms()
        : {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('The Good Alarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadSettingsAndAlarms(); // Recargar configuración y alarmas al volver
            },
          ),
        ],
      ),
      body: Column(
        // Envolver en Column para añadir la nueva sección
        children: [
          _buildNextAlarmSection(), // Mostrar la sección de la próxima alarma
          Expanded(
            // El ListView/ExpansionPanelList debe estar en un Expanded
            child: _alarms.isEmpty
                ? const Center(child: Text('No hay alarmas configuradas'))
                : _currentGroupingOption == AlarmGroupingOption.none
                ? ListView.builder(
                    itemCount: _alarms.length,
                    itemBuilder: (context, index) {
                      final alarm = _alarms[index];
                      return _buildAlarmItem(alarm);
                    },
                  )
                : ListView.builder(
                    itemCount: groupedAlarms.keys.length,
                    itemBuilder: (context, index) {
                      String groupKey = groupedAlarms.keys.elementAt(index);
                      List<Alarm> alarmsInGroup = groupedAlarms[groupKey]!;
                      bool showActiveOnly =
                          _groupShowActiveOnlyState[groupKey] ?? false;

                      List<Alarm> displayAlarms = showActiveOnly
                          ? alarmsInGroup.where((a) => a.isActive).toList()
                          : alarmsInGroup;

                      if (alarmsInGroup.isEmpty &&
                          !(_groupExpansionState[groupKey] ?? false)) {
                        // No mostrar el grupo si está vacío y no se fuerza la expansión (opcional)
                        // return const SizedBox.shrink();
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ExpansionTile(
                          key: PageStorageKey(
                            groupKey,
                          ), // Para mantener estado de expansión
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                groupKey,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  showActiveOnly
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                tooltip: showActiveOnly
                                    ? 'Mostrar todas'
                                    : 'Mostrar solo activas',
                                onPressed: () {
                                  setState(() {
                                    _groupShowActiveOnlyState[groupKey] =
                                        !showActiveOnly;
                                  });
                                },
                              ),
                            ],
                          ),
                          initiallyExpanded:
                              _groupExpansionState[groupKey] ?? false,
                          onExpansionChanged: (isExpanded) {
                            setState(() {
                              _groupExpansionState[groupKey] = isExpanded;
                            });
                          },
                          children: displayAlarms.isEmpty
                              ? [
                                  const ListTile(
                                    title: Center(
                                      child: Text(
                                        'No hay alarmas en este grupo',
                                      ),
                                    ),
                                  ),
                                ]
                              : displayAlarms
                                    .map((alarm) => _buildAlarmItem(alarm))
                                    .toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _setAlarm,
        tooltip: 'Añadir alarma',
        child: const Icon(Icons.add),
      ),
    );
  }
}
