import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación
import 'settings_screen.dart'; // Importar SettingsScreen
import 'package:intl/intl.dart';

// Modelo para la alarma con soporte para repetición
class Alarm {
  final int id;
  final DateTime time;
  final String title;
  final String message;
  bool isActive; // Para saber si la alarma está activa o ya sonó
  List<int> repeatDays; // Días de repetición (1-7 para lunes-domingo)
  bool isDaily;
  bool isWeekly;
  bool isWeekend;
  int snoozeCount;
  int maxSnoozes;

  Alarm({
    required this.id,
    required this.time,
    required this.title,
    required this.message,
    this.isActive = true, // Por defecto, la alarma está activa al crearse
    this.repeatDays = const [],
    this.isDaily = false,
    this.isWeekly = false,
    this.isWeekend = false,
    this.snoozeCount = 0,
    this.maxSnoozes = 3,
  });

  // Getter para determinar si la alarma es repetitiva
  bool isRepeating() {
    return isDaily || isWeekly || isWeekend || repeatDays.isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'title': title,
    'message': message,
    'isActive': isActive,
    'repeatDays': repeatDays,
    'isDaily': isDaily,
    'isWeekly': isWeekly,
    'isWeekend': isWeekend,
    'snoozeCount': snoozeCount,
    'maxSnoozes': maxSnoozes,
  };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
    id: json['id'] as int,
    time: DateTime.parse(json['time'] as String),
    title: json['title'] as String,
    message: json['message'] as String,
    isActive: json['isActive'] as bool? ?? true,
    repeatDays: json['repeatDays'] != null
        ? List<int>.from(json['repeatDays'])
        : [],
    isDaily: json['isDaily'] as bool? ?? false,
    isWeekly: json['isWeekly'] as bool? ?? false,
    isWeekend: json['isWeekend'] as bool? ?? false,
    snoozeCount: json['snoozeCount'] as int? ?? 0,
    maxSnoozes: json['maxSnoozes'] as int? ?? 3,
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
    _startOrUpdateCountdown();
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

  Future<Map<String, dynamic>?> _showAlarmDetailsDialog({
    String? initialTitle,
    String? initialMessage,
    List<int>? initialRepeatDays,
    bool? initialIsDaily,
    bool? initialIsWeekly,
    bool? initialIsWeekend,
    int? initialMaxSnoozes,
  }) async {
    final titleController = TextEditingController(text: initialTitle ?? '');
    final messageController = TextEditingController(text: initialMessage ?? '');

    // Valores iniciales para repetición
    String repetitionType = 'none';
    List<int> selectedDays = initialRepeatDays ?? [];

    if (initialIsDaily == true) {
      repetitionType = 'daily';
    } else if (initialIsWeekly == true) {
      repetitionType = 'weekly';
    } else if (initialIsWeekend == true) {
      repetitionType = 'weekend';
    } else if (initialRepeatDays != null && initialRepeatDays.isNotEmpty) {
      repetitionType = 'custom';
      selectedDays = List.from(initialRepeatDays);
    }

    // Valores para los días de la semana
    final daysOfWeek = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];

    // Opciones de repetición
    final repetitionOptions = [
      {'value': 'none', 'label': 'Sin repetición'},
      {'value': 'daily', 'label': 'Diaria'},
      {'value': 'weekly', 'label': 'Semanal (mismo día)'},
      {'value': 'weekend', 'label': 'Fines de semana (Sáb-Dom)'},
      {'value': 'custom', 'label': 'Personalizada'},
    ];

    // Valor para el número máximo de snoozes
    int maxSnoozes = initialMaxSnoozes ?? 3;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                initialTitle == null ? 'Nueva Alarma' : 'Editar Alarma',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(hintText: 'Título'),
                    ),
                    TextField(
                      controller: messageController,
                      decoration: const InputDecoration(labelText: 'Mensaje'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Repetición:'),
                    ...repetitionOptions.map(
                      (option) => RadioListTile<String>(
                        title: Text(option['label'] as String),
                        value: option['value'] as String,
                        groupValue: repetitionType,
                        onChanged: (value) {
                          setState(() {
                            repetitionType = value!;

                            // Si cambiamos a semanal, añadimos el día actual
                            if (value == 'weekly') {
                              final now = DateTime.now();
                              selectedDays = [now.weekday];
                            }
                            // Si cambiamos a fin de semana, seleccionamos sábado y domingo
                            else if (value == 'weekend') {
                              selectedDays = [
                                DateTime.saturday,
                                DateTime.sunday,
                              ];
                            }
                            // Si no es personalizado, limpiamos la selección
                            else if (value != 'custom') {
                              selectedDays = [];
                            }
                          });
                        },
                      ),
                    ),

                    // Mostrar selección de días si es personalizado
                    if (repetitionType == 'custom')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Text('Selecciona los días:'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8.0,
                            children: List.generate(7, (index) {
                              final dayValue =
                                  index + 1; // 1-7 para Lunes-Domingo
                              return FilterChip(
                                label: Text(daysOfWeek[index]),
                                selected: selectedDays.contains(dayValue),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      selectedDays.add(dayValue);
                                    } else {
                                      selectedDays.remove(dayValue);
                                    }
                                  });
                                },
                              );
                            }),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),
                    const Text('Número máximo de snoozes:'),
                    Slider(
                      value: maxSnoozes.toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      label: maxSnoozes.toString(),
                      onChanged: (value) {
                        setState(() {
                          maxSnoozes = value.toInt();
                        });
                      },
                    ),
                    Text('Valor actual: $maxSnoozes'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    // Validar que al menos hay un título
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Por favor, ingresa un título'),
                        ),
                      );
                      return;
                    }

                    // Validar que si es personalizado, al menos hay un día seleccionado
                    if (repetitionType == 'custom' && selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Por favor, selecciona al menos un día',
                          ),
                        ),
                      );
                      return;
                    }

                    // Preparar resultado
                    final result = {
                      'title': titleController.text,
                      'message': messageController.text,
                      'repetitionType': repetitionType,
                      'repeatDays': selectedDays,
                      'maxSnoozes': maxSnoozes,
                    };

                    Navigator.pop(context, result);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
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
          Navigator.of(context).pushNamed(
          '/alarm',
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
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      cancelText: 'Cerrar', // Cambia el texto del botón Cancelar
      confirmText: 'Aceptar', // Cambia el texto del botón OK
      helpText: 'Seleccionar Hora',
      initialEntryMode: TimePickerEntryMode.input,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.black,
              hourMinuteTextColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              hourMinuteColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 208, 252, 210)
                    : const Color.fromARGB(255, 255, 255, 255),
              ),
              dayPeriodTextColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              dayPeriodColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 208, 252, 210)
                    : const Color.fromARGB(255, 255, 255, 255),
              ),
              dialHandColor: Colors.green,
              dialBackgroundColor: Colors.grey.shade800,
              entryModeIconColor: Colors.green,
              helpTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
              confirmButtonStyle: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                backgroundColor: MaterialStateProperty.all(Colors.green),
                textStyle: MaterialStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                // Aquí configuras el radio de borde
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      10,
                    ), // Radio de borde de 10
                  ),
                ),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 0, 0, 0),
                ),
                backgroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                textStyle: MaterialStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                // Aquí configuras el radio de borde
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      10,
                    ), // Radio de borde de 10
                  ),
                ),
              ), // Color del texto "SELECCIONAR HORA"
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null && mounted) {
      // Obtener la fecha y hora actual
      final now = DateTime.now();

      // Crear una fecha con la hora seleccionada
      var alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
        0, // seconds
        0, // milliseconds
      );

      // Si la hora seleccionada ya pasó hoy, programarla para mañana
      final nowNormalized = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        0,
        0,
      );
      if (alarmTime.isBefore(nowNormalized) ||
          alarmTime.isAtSameMomentAs(nowNormalized)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      // Mostrar el diálogo para obtener título, mensaje y configuración de repetición
      final alarmDetails = await _showAlarmDetailsDialog();
      if (alarmDetails == null) return;

      final title = alarmDetails['title']!.isNotEmpty
          ? alarmDetails['title']!
          : 'Alarma';
      final message = alarmDetails['message']!.isNotEmpty
          ? alarmDetails['message']!
          : '¡Es hora de despertar!';
      final repetitionType = alarmDetails['repetitionType'] as String;
      final repeatDays = alarmDetails['repeatDays'] as List<int>;
      final maxSnoozes = alarmDetails['maxSnoozes'] as int;

      // Configurar los valores de repetición
      bool isDaily = repetitionType == 'daily';
      bool isWeekly = repetitionType == 'weekly';
      bool isWeekend = repetitionType == 'weekend';

      // Si es semanal y no hay días seleccionados, usar el día de la semana de la fecha seleccionada
      List<int> finalRepeatDays = List.from(repeatDays);
      if (isWeekly && finalRepeatDays.isEmpty) {
        finalRepeatDays.add(alarmTime.weekday);
      }

      // Crear un nuevo ID para la alarma
      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000;

      // Crear la nueva alarma
      final newAlarm = Alarm(
        id: alarmId,
        time: alarmTime,
        title: title,
        message: message,
        isActive: true,
        repeatDays: finalRepeatDays,
        isDaily: isDaily,
        isWeekly: isWeekly,
        isWeekend: isWeekend,
        maxSnoozes: maxSnoozes,
      );

      try {
        await platform.invokeMethod('setAlarm', {
          'timeInMillis': alarmTime.millisecondsSinceEpoch,
          'alarmId': alarmId,
          'title': title,
          'message': message,
          'screenRoute': '/alarm',
          'repeatDays': finalRepeatDays,
          'isDaily': isDaily,
          'isWeekly': isWeekly,
          'isWeekend': isWeekend,
        });
        _alarms.add(newAlarm);
        await _saveAlarms();
        _startOrUpdateCountdown();
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

  Future<void> _editAlarm(Alarm alarm) async {
    // Mostrar el selector de tiempo con la hora actual de la alarma
    final TimeOfDay initialTime = TimeOfDay(
      hour: alarm.time.hour,
      minute: alarm.time.minute,
    );
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      cancelText: 'Cerrar', // Cambia el texto del botón Cancelar
      confirmText: 'Aceptar', // Cambia el texto del botón OK
      helpText: 'Seleccionar Hora',
      initialEntryMode: TimePickerEntryMode.input,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.black,
              hourMinuteTextColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              hourMinuteColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 208, 252, 210)
                    : const Color.fromARGB(255, 255, 255, 255),
              ),
              dayPeriodTextColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              dayPeriodColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.selected)
                    ? const Color.fromARGB(255, 208, 252, 210)
                    : const Color.fromARGB(255, 255, 255, 255),
              ),
              dialHandColor: Colors.green,
              dialBackgroundColor: Colors.grey.shade800,
              entryModeIconColor: Colors.green,
              helpTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
              confirmButtonStyle: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                backgroundColor: MaterialStateProperty.all(Colors.green),
                textStyle: MaterialStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                // Aquí configuras el radio de borde
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      10,
                    ), // Radio de borde de 10
                  ),
                ),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 0, 0, 0),
                ),
                backgroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                textStyle: MaterialStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                // Aquí configuras el radio de borde
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      10,
                    ), // Radio de borde de 10
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                foregroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (selectedTime == null) return;

    final alarmDetails = await _showAlarmDetailsDialog(
      initialTitle: alarm.title,
      initialMessage: alarm.message,
    );
    // Use existing details if new ones are not provided or dialog is cancelled
    final String title =
        (alarmDetails?['title'] ?? alarm.title).isNotEmpty
        ? (alarmDetails?['title'] ?? alarm.title)
        : 'Alarma';
    final String message = alarmDetails?['message'] ?? alarm.message;

    if (selectedTime != null) {
      // Obtener la fecha y hora actual
      final now = DateTime.now();

      // Crear una fecha con la hora seleccionada pero manteniendo la fecha original
      DateTime alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      // Si la hora seleccionada ya pasó hoy, programarla para mañana
      // (solo para alarmas no repetitivas o si estamos cambiando la hora)
      if (alarmTime.isBefore(now) &&
          !alarm.isDaily &&
          !alarm.isWeekly &&
          !alarm.isWeekend &&
          alarm.repeatDays.isEmpty) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      // Mostrar el diálogo para editar título, mensaje y configuración de repetición
      final result = await _showAlarmDetailsDialog(
        initialTitle: alarm.title,
        initialMessage: alarm.message,
        initialRepeatDays: alarm.repeatDays,
        initialIsDaily: alarm.isDaily,
        initialIsWeekly: alarm.isWeekly,
        initialIsWeekend: alarm.isWeekend,
        initialMaxSnoozes: alarm.maxSnoozes,
      );

      if (result != null) {
        final title = result['title'] as String;
        final message = result['message'] as String;
        final repetitionType = result['repetitionType'] as String;
        final repeatDays = result['repeatDays'] as List<int>;
        final maxSnoozes = result['maxSnoozes'] as int;

        // Configurar los valores de repetición
        bool isDaily = repetitionType == 'daily';
        bool isWeekly = repetitionType == 'weekly';
        bool isWeekend = repetitionType == 'weekend';

        // Si es semanal y no hay días seleccionados, usar el día de la semana de la fecha seleccionada
        List<int> finalRepeatDays = List.from(repeatDays);
        if (isWeekly && finalRepeatDays.isEmpty) {
          finalRepeatDays.add(alarmTime.weekday);
        }

        // Cancelar la alarma anterior
        try {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
        } catch (e) {
          print('Error al cancelar la alarma anterior: $e');
        }

        // Actualizar la alarma en la lista
        setState(() {
          final index = _alarms.indexWhere((a) => a.id == alarm.id);
          if (index != -1) {
            _alarms[index] = Alarm(
              id: alarm.id,
              time: alarmTime,
              title: title,
              message: message,
              
              isActive: alarm.isActive,
              repeatDays: finalRepeatDays,
              isDaily: isDaily,
              isWeekly: isWeekly,
              isWeekend: isWeekend,
              maxSnoozes: maxSnoozes,
            );
            _saveAlarms();
          }
        });

        // Reprogramar la alarma si está activa
        if (alarm.isActive) {
          try {
            await platform.invokeMethod('setAlarm', {
              'timeInMillis': alarmTime.millisecondsSinceEpoch,
              'alarmId': alarm.id,
              'title': title,
              'message': message,
              'screenRoute': '/alarm',
              'repeatDays': finalRepeatDays,
              'isDaily': isDaily,
              'isWeekly': isWeekly,
              'isWeekend': isWeekend,
            });

            // Actualizar el temporizador de cuenta regresiva
            _startOrUpdateCountdown();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Alarma actualizada para ${DateFormat('HH:mm').format(alarmTime)}',
                ),
              ),
            );
          } catch (e) {
            print('Error al reprogramar la alarma: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error al reprogramar la alarma')),
            );
          }
        }
      }
    }
  }

  Future<void> _toggleAlarmState(int alarmId, bool isActive) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      if (alarm.isActive == isActive) return; // No change needed

      try {
        if (isActive) {
          // Reactivar alarma: setearla de nuevo
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
          // Desactivar alarma: cancelarla
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Alarma desactivada')));
        }
        _alarms[index].isActive = isActive;
        await _saveAlarms(); // Guardar y refrescar UI
        _startOrUpdateCountdown(); // <--- ADD THIS LINE
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarma ${isActive ? "activada" : "desactivada"}'),
          ),
        );
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
        // Revertir el cambio en la UI si la operación nativa falla
        // _alarms[index].isActive = !isActive; // Opcional, dependiendo de la UX deseada
        // if(mounted) setState(() {});
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

  // At the top of _HomePageState class
  Timer? _countdownTimer;
  Duration _timeUntilNextAlarm = Duration.zero;
  Alarm? _currentNextAlarmForCountdown;

  // In initState or a method called when alarms/settings change:
  void _startOrUpdateCountdown() {
    _countdownTimer?.cancel(); // Cancel existing timer
    final nextAlarm = _getNextActiveAlarm();
    _currentNextAlarmForCountdown = nextAlarm;

    if (nextAlarm != null) {
      _updateCountdown(); // Initial update
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
      // If alarm became inactive or null, try to find the next one
      _startOrUpdateCountdown();
      return;
    }
    final now = DateTime.now();
    DateTime nextAlarmTime = _currentNextAlarmForCountdown!.time;

    // Adjust for non-repeating alarms that are in the past for today
    if (!_currentNextAlarmForCountdown!.isRepeating() &&
        nextAlarmTime.isBefore(now)) {
      nextAlarmTime = nextAlarmTime.add(const Duration(days: 1));
    }

    final difference = nextAlarmTime.isAfter(now)
        ? nextAlarmTime.difference(now)
        : Duration.zero;

    if (mounted) {
      setState(() {
        _timeUntilNextAlarm = difference;
      });
    }
    if (difference == Duration.zero ||
        (!_currentNextAlarmForCountdown!.isRepeating() &&
            _currentNextAlarmForCountdown!.time.isBefore(now))) {
      _startOrUpdateCountdown();
    }
  }

  // In dispose method:
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // Helper function to format duration (can be static or a member of _HomePageState)
  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) {
      return "--:--:--"; // Simplified for no time remaining or past
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours.remainder(24));
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inDays > 0) {
      String days = duration.inDays.toString();
      return "$days Días: $hours:$minutes:$seconds";
    } else {
      return "$hours:$minutes:$seconds";
    }
  }

  Alarm? _getNextActiveAlarm() {
    final now = DateTime.now();
    final activeAlarms = _alarms.where((a) => a.isActive).toList();
    if (activeAlarms.isEmpty) return null;

    // Sort alarms: first by whether their time is after now, then by time.
    // This prioritizes alarms yet to occur today.
    // For non-repeating alarms, if their time has passed today, they are effectively for the next day.
    activeAlarms.sort((a, b) {
      DateTime aNextTime = a.time;
      DateTime bNextTime = b.time;

      // If not repeating and time is in the past for today, consider it for the next day for sorting
      if (!a.isRepeating() && aNextTime.isBefore(now)) {
        aNextTime = aNextTime.add(const Duration(days: 1));
      }
      if (!b.isRepeating() && bNextTime.isBefore(now)) {
        bNextTime = bNextTime.add(const Duration(days: 1));
      }
      return aNextTime.compareTo(bNextTime);
    });
    return activeAlarms.first;
  }

  Widget _buildNextAlarmSection() {
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null || !_showNextAlarmSection) {
      return const SizedBox.shrink();
    }

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
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.black,
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alarm.message.isNotEmpty ? alarm.message : 'Sin mensaje'),
          if (alarm.isActive)
            Text(
              'Próxima vez: ${TimeOfDay.fromDateTime(alarm.time).format(context)}',
            ),
          if (alarm.isActive)
            Builder(
              // Use Builder to get a fresh context if needed for TextTheme
              builder: (context) {
                final now = DateTime.now();
                final durationUntilAlarm = alarm.time.isAfter(now)
                    ? alarm.time.difference(now)
                    : Duration.zero;
                return Text(
                  'Faltan: ${_formatDuration(durationUntilAlarm)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.green),
                );
              },
            ),
        ],
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
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
        title: Padding(
          padding: const EdgeInsets.only(left: 85),
          child: Text(
            'The Good Alarm',
            style: TextStyle(
              fontSize: 25,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 30),
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadSettingsAndAlarms(); // Recargar configuración y alarmas al volver
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Envolver en Column para añadir la nueva sección
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            color: Colors.green,
            child: Text(
              'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color.fromARGB(255, 255, 255, 255),
              ),
              textAlign: TextAlign.center,
            ),
          ),
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
                        elevation: 1.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4.0),
                          side: BorderSide.none,
                        ),
                        child: ExpansionTile(
                          collapsedIconColor: Colors.transparent,
                          key: PageStorageKey(
                            groupKey,
                          ), // Para mantener estado de expansión
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: Icon(
                                  showActiveOnly
                                      ? Icons.alarm_on
                                      : Icons.alarm_off,
                                ),
                                color: Colors.black,
                                iconSize: 35,
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
                              const SizedBox(width: 80),
                              Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Text(
                                  groupKey,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
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
                          shape: Border.all(
                            color: Colors.transparent,
                          ), // Elimina el borde cuando está colapsado
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
        focusColor: Colors.white,
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }
}
