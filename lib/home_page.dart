import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación
import 'settings_screen.dart'; // Importar SettingsScreen
import 'package:intl/intl.dart';

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

  // NUEVO: Variables para controlar la alarma que está sonando
  bool _isAlarmRinging = false;
  int? _ringingAlarmId;
  String _ringingAlarmTitle = '';
  String _ringingAlarmMessage = '';
  int _ringingAlarmSnoozeCount = 0;
  int _ringingAlarmMaxSnoozes = 3;
  int _ringingAlarmSnoozeDuration = 5;

  // NUEVO: Variables para controlar el estado de la aplicación
  bool _isAppInForeground = true;
  bool _hasUnhandledAlarm = false;
  int? _pendingAlarmId;

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
    int? initialSnoozeDuration, // NUEVO PARÁMETRO
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
    int snoozeDuration = initialSnoozeDuration ?? 5; // NUEVA VARIABLE

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
                    const Text('Configuración de Snooze:'),
                    const SizedBox(height: 8),

                    // Duración del snooze
                    Text('Duración: $snoozeDuration minutos'),
                    Slider(
                      value: snoozeDuration.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$snoozeDuration min',
                      onChanged: (value) {
                        setState(() {
                          snoozeDuration = value.toInt();
                        });
                      },
                    ),

                    const SizedBox(height: 8),
                    const Text('Número máximo de snoozes:'),
                    Slider(
                      value: maxSnoozes.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
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
                      'snoozeDuration': snoozeDuration, // AGREGAR
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

  // NUEVO: Obtener alarmas pospuestas
  List<Alarm> _getSnoozedAlarms() {
    return _alarms
        .where((alarm) => alarm.snoozeCount > 0 && alarm.isActive)
        .toList();
  }

  Future<void> _handleNativeCalls(MethodCall call) async {
    print('=== HANDLE NATIVE CALLS START ===');
    print('Method: ${call.method}');
    print('Arguments: ${call.arguments}');

    final args = call.arguments != null
        ? Map<String, dynamic>.from(call.arguments)
        : {};
    final alarmId = args['alarmId'] as int?;

    switch (call.method) {
      case 'showAlarmScreen':
        final alarmId = call.arguments['alarmId'] as int;
        final title = call.arguments['title'] as String;
        final message = call.arguments['message'] as String;

        // NUEVO: Marcar que hay una alarma sonando
        setState(() {
          _isAlarmRinging = true;
          _ringingAlarmId = alarmId;
          _ringingAlarmTitle = title;
          _ringingAlarmMessage = message;
        });

        // Encontrar la alarma para obtener sus configuraciones
        final alarm = _alarms.firstWhere(
          (alarm) => alarm.id == alarmId,
          orElse: () => Alarm(
            id: alarmId,
            time: DateTime.now(),
            title: title,
            message: message,
          ),
        );

        // NUEVO: Actualizar configuraciones de snooze
        setState(() {
          _ringingAlarmSnoozeCount = alarm.snoozeCount;
          _ringingAlarmMaxSnoozes = alarm.maxSnoozes;
          _ringingAlarmSnoozeDuration = alarm.snoozeDurationMinutes;
        });

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AlarmScreen(
                arguments: {
                  'alarmId': alarmId,
                  'title': title,
                  'message': message,
                  'snoozeCount': alarm.snoozeCount,
                  'maxSnoozes': alarm.maxSnoozes,
                  'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
                },
              ),
            ),
          );
        }
        break;
      // NUEVO: Manejar notificación de alarma sonando
      case 'notifyAlarmRinging':
        final alarmId = call.arguments['alarmId'] as int;
        final title = call.arguments['title'] as String;
        final message = call.arguments['message'] as String;
        final snoozeCount = call.arguments['snoozeCount'] as int;
        final maxSnoozes = call.arguments['maxSnoozes'] as int;
        final snoozeDuration = call.arguments['snoozeDurationMinutes'] as int;

        setState(() {
          _isAlarmRinging = true;
          _ringingAlarmId = alarmId;
          _ringingAlarmTitle = title;
          _ringingAlarmMessage = message;
          _ringingAlarmSnoozeCount = snoozeCount;
          _ringingAlarmMaxSnoozes = maxSnoozes;
          _ringingAlarmSnoozeDuration = snoozeDuration;
        });
        break;
      case 'alarmManuallyStopped':
        print('Alarm manually stopped: $alarmId');
        // NUEVO: Ocultar el contenedor de alarma sonando
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        if (alarmId != null) {
          await _handleAlarmStopped(alarmId);
        }
        // Cerrar la pantalla de alarma si está abierta
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;

      case 'alarmManuallySnoozed':
        final alarmId = call.arguments['alarmId'] as int;
        final newTimeInMillis = call.arguments['newTimeInMillis'] as int;

        // NUEVO: Ocultar el contenedor de alarma sonando cuando se pospone
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        // Encontrar la alarma y actualizar su snoozeCount
        final alarmIndex = _alarms.indexWhere((alarm) => alarm.id == alarmId);
        if (alarmIndex != -1) {
          setState(() {
            _alarms[alarmIndex].snoozeCount += 1; // INCREMENTAR SNOOZE COUNT
            // Actualizar el tiempo si es necesario
          });
          await _saveAlarms(); // GUARDAR CAMBIOS
        }

        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case 'closeAlarmScreenIfOpen':
        print('Closing alarm screen if open for alarm: $alarmId');
        // NUEVO: También ocultar el contenedor cuando se cierra la pantalla
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        break;
    }
    print('=== HANDLE NATIVE CALLS END ===');
  }

  // NUEVO: Manejar cuando una alarma es detenida
  Future<void> _handleAlarmStopped(int alarmId) async {
    print('=== HANDLE ALARM STOPPED START ===');
    print('Processing stopped alarm ID: $alarmId');

    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      print('Found alarm: ${alarm.title}, isRepeating: ${alarm.isRepeating()}');

      // Si la alarma NO es repetitiva, desactivarla
      if (!alarm.isRepeating()) {
        print('Non-repeating alarm, deactivating...');
        setState(() {
          _alarms[index].isActive = false;
          _alarms[index].snoozeCount = 0; // Reset snooze count
        });
        await _saveAlarms();
        print('Non-repeating alarm deactivated and saved');
      } else {
        // Si la alarma es repetitiva, solo desactivar si no hay snoozes activos
        if (alarm.snoozeCount == 0) {
          print(
            'Repeating alarm with no active snoozes, keeping active for next occurrence',
          );
          // Para alarmas repetitivas sin snoozes, mantener activa para la siguiente ocurrencia
          // No hacer nada, la alarma se reprogramará automáticamente
        } else {
          print('Repeating alarm with active snoozes, resetting snooze count');
          setState(() {
            _alarms[index].snoozeCount = 0; // Reset snooze count
          });
          await _saveAlarms();
        }
      }

      _startOrUpdateCountdown();
    } else {
      print('Alarm with ID $alarmId not found in list');
    }
    print('=== HANDLE ALARM STOPPED END ===');
  }

  // NUEVO: Reprogramar alarma repetitiva
  // Future<void> _rescheduleRepeatingAlarm(Alarm alarm) async {
  //   print('=== RESCHEDULE REPEATING ALARM START ===');
  //   print('Rescheduling alarm: ${alarm.title}');

  //   try {
  //     await _setNativeAlarm(alarm);
  //     print('Repeating alarm rescheduled successfully');
  //   } catch (e) {
  //     print('Error rescheduling repeating alarm: $e');
  //   }
  //   print('=== RESCHEDULE REPEATING ALARM END ===');
  // }

  // NUEVO: Manejar cuando una alarma es pospuesta
  Future<void> _handleAlarmSnoozed(int alarmId, int newTimeInMillis) async {
    print('=== HANDLE ALARM SNOOZED START ===');
    print(
      'Processing snoozed alarm ID: $alarmId, new time: ${DateTime.fromMillisecondsSinceEpoch(newTimeInMillis)}',
    );

    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      print(
        'Found alarm: ${alarm.title}, current snooze count: ${alarm.snoozeCount}',
      );

      setState(() {
        // Actualizar tiempo de la alarma al tiempo de snooze
        _alarms[index] = Alarm(
          id: alarm.id,
          time: DateTime.fromMillisecondsSinceEpoch(newTimeInMillis),
          title: alarm.title,
          message: alarm.message,
          isActive: alarm.isActive,
          repeatDays: alarm.repeatDays,
          isDaily: alarm.isDaily,
          isWeekly: alarm.isWeekly,
          isWeekend: alarm.isWeekend,
          snoozeCount: alarm.snoozeCount + 1,
          maxSnoozes: alarm.maxSnoozes,
          snoozeDurationMinutes: alarm.snoozeDurationMinutes,
        );
      });

      await _saveAlarms();
      _startOrUpdateCountdown();
      print(
        'Alarm snoozed and saved, new snooze count: ${_alarms[index].snoozeCount}',
      );
    } else {
      print('Alarm with ID $alarmId not found in list');
    }
    print('=== HANDLE ALARM SNOOZED END ===');
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

  Future<void> _setNativeAlarm(Alarm alarm) async {
    try {
      await platform.invokeMethod('setAlarm', {
        'timeInMillis': alarm.time.millisecondsSinceEpoch,
        'alarmId': alarm.id,
        'title': alarm.title,
        'message': alarm.message,
        'screenRoute': '/alarm',
        'repeatDays': alarm.repeatDays,
        'isDaily': alarm.isDaily,
        'isWeekly': alarm.isWeekly,
        'isWeekend': alarm.isWeekend,
        'maxSnoozes': alarm.maxSnoozes,
        'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
      });
    } catch (e) {
      print('Error setting native alarm: $e');
      rethrow;
    }
  }

  Future<void> _setAlarm() async {
    // Mostrar el diálogo para obtener título, mensaje y configuración de repetición
    final alarmDetails = await _showAlarmDetailsDialog();
    // mostrar dialogo de configuracion de hora
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

      if (alarmDetails == null) return;

      final title = alarmDetails['title']!.isNotEmpty
          ? alarmDetails['title']!
          : 'Alarma';
      final message = alarmDetails['message']!.isNotEmpty
          ? alarmDetails['message']!
          : '¡Es hora de despertar!';
      final repetitionType = alarmDetails['repetitionType'] as String;
      final repeatDays = alarmDetails['repeatDays'] as List<int>;
      final maxSnoozes = alarmDetails['maxSnoozes'] ?? 3;
      final snoozeDuration = alarmDetails['snoozeDuration'] ?? 5;

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
      final alarm = Alarm(
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
        snoozeCount: 0,
        snoozeDurationMinutes: snoozeDuration,
      );

      try {
        await _setNativeAlarm(alarm);
        _alarms.add(alarm);
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
    // Mostrar el diálogo para editar título, mensaje y configuración de repetición
    final result = await _showAlarmDetailsDialog(
      initialTitle: alarm.title,
      initialMessage: alarm.message,
      initialRepeatDays: alarm.repeatDays,
      initialIsDaily: alarm.isDaily,
      initialIsWeekly: alarm.isWeekly,
      initialIsWeekend: alarm.isWeekend,
      initialMaxSnoozes: alarm.maxSnoozes,
      initialSnoozeDuration: alarm.snoozeDurationMinutes, // AGREGAR
    );
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
      final nowNormalized = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        0,
        0,
      );
      if (alarmTime.isBefore(nowNormalized) &&
          (!alarm.isRepeating() ||
              selectedTime.hour != alarm.time.hour ||
              selectedTime.minute != alarm.time.minute)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      if (result != null) {
        final title = result['title'] as String;
        final message = result['message'] as String;
        final repetitionType = result['repetitionType'] as String;
        final repeatDays = result['repeatDays'] as List<int>;
        final maxSnoozes = result['maxSnoozes'] ?? 3;
        final snoozeDuration = result['snoozeDuration'] ?? 5;

        // Configurar los valores de repetición
        bool isDaily = repetitionType == 'daily';
        bool isWeekly = repetitionType == 'weekly';
        bool isWeekend = repetitionType == 'weekend';

        // Si es semanal y no hay días seleccionados, usar el día de la semana de la fecha seleccionada
        List<int> finalRepeatDays = List.from(repeatDays);
        if (isWeekly && finalRepeatDays.isEmpty) {
          finalRepeatDays.add(alarm.time.weekday);
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
              time: alarmTime, // Usar la nueva hora ajustada
              title: title,
              message: message,
              isActive: alarm.isActive,
              repeatDays: finalRepeatDays,
              isDaily: isDaily,
              isWeekly: isWeekly,
              isWeekend: isWeekend,
              maxSnoozes: maxSnoozes,
              snoozeCount: alarm.snoozeCount,
              snoozeDurationMinutes: snoozeDuration,
            );
            _saveAlarms();
          }
        });

        // Reprogramar la alarma si está activa
        if (alarm.isActive) {
          try {
            final updatedAlarm =
                _alarms[_alarms.indexWhere((a) => a.id == alarm.id)];
            await _setNativeAlarm(updatedAlarm);

            // Actualizar el temporizador de cuenta regresiva
            _startOrUpdateCountdown();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Alarma actualizada para ${DateFormat('HH:mm').format(alarm.time)}',
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
          await _setNativeAlarm(alarm);
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
    _countdownTimer?.cancel();

    final nextAlarm = _getNextActiveAlarm();
    _currentNextAlarmForCountdown = nextAlarm;

    if (nextAlarm != null) {
      _updateCountdown();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateCountdown();
      });
    } else {
      setState(() {
        _timeUntilNextAlarm = Duration.zero;
      });
    }
  }

  void _updateCountdown() {
    if (_currentNextAlarmForCountdown != null) {
      final now = DateTime.now();
      final difference = _currentNextAlarmForCountdown!.time.difference(now);

      if (difference.isNegative) {
        // Si la alarma ya pasó, recalcular la próxima alarma
        _startOrUpdateCountdown();
      } else {
        setState(() {
          _timeUntilNextAlarm = difference;
        });
      }
    }
  }

  Alarm? _getNextActiveAlarm() {
    final now = DateTime.now();
    final activeAlarms = _alarms.where((alarm) => alarm.isActive).toList();

    if (activeAlarms.isEmpty) return null;

    // Encontrar la próxima alarma activa
    Alarm? nextAlarm;
    Duration? shortestDuration;

    for (final alarm in activeAlarms) {
      DateTime nextAlarmTime = alarm.time;

      // Si la alarma es repetitiva, calcular la próxima ocurrencia
      if (alarm.isRepeating()) {
        nextAlarmTime = _calculateNextOccurrence(alarm, now);
      } else {
        // Para alarmas no repetitivas, verificar si necesita ser programada para el día siguiente
        nextAlarmTime = alarm.time;
        // Si la hora ya pasó hoy, programar para mañana
        if (nextAlarmTime.isBefore(now)) {
          nextAlarmTime = DateTime(
            now.year,
            now.month,
            now.day,
            alarm.time.hour,
            alarm.time.minute,
          ).add(const Duration(days: 1));
        }
      }

      final duration = nextAlarmTime.difference(now);
      if (duration.isNegative) continue;

      if (shortestDuration == null || duration < shortestDuration) {
        shortestDuration = duration;
        nextAlarm = Alarm(
          id: alarm.id,
          time: nextAlarmTime,
          title: alarm.title,
          message: alarm.message,
          isActive: alarm.isActive,
          repeatDays: alarm.repeatDays,
          isDaily: alarm.isDaily,
          isWeekly: alarm.isWeekly,
          isWeekend: alarm.isWeekend,
          snoozeCount: alarm.snoozeCount,
          maxSnoozes: alarm.maxSnoozes,
          snoozeDurationMinutes: alarm.snoozeDurationMinutes,
        );
      }
    }

    return nextAlarm;
  }

  DateTime _calculateNextOccurrence(Alarm alarm, DateTime now) {
    DateTime nextTime = alarm.time;

    if (alarm.isDaily) {
      // Para alarmas diarias
      if (nextTime.isBefore(now) || nextTime.isAtSameMomentAs(now)) {
        nextTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.time.hour,
          alarm.time.minute,
        ).add(const Duration(days: 1));
      }
    } else if (alarm.isWeekly) {
      // Para alarmas semanales
      final targetWeekday = alarm.time.weekday;
      int daysUntilNext = (targetWeekday - now.weekday) % 7;
      if (daysUntilNext == 0 && nextTime.isBefore(now)) {
        daysUntilNext = 7;
      }
      nextTime = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.time.hour,
        alarm.time.minute,
      ).add(Duration(days: daysUntilNext));
    } else if (alarm.isWeekend) {
      // Para alarmas de fin de semana
      DateTime nextSaturday = now.add(
        Duration(days: (DateTime.saturday - now.weekday) % 7),
      );
      DateTime nextSunday = now.add(
        Duration(days: (DateTime.sunday - now.weekday) % 7),
      );

      if (nextSaturday.isBefore(now))
        nextSaturday = nextSaturday.add(const Duration(days: 7));
      if (nextSunday.isBefore(now))
        nextSunday = nextSunday.add(const Duration(days: 7));

      nextTime = nextSaturday.isBefore(nextSunday)
          ? DateTime(
              nextSaturday.year,
              nextSaturday.month,
              nextSaturday.day,
              alarm.time.hour,
              alarm.time.minute,
            )
          : DateTime(
              nextSunday.year,
              nextSunday.month,
              nextSunday.day,
              alarm.time.hour,
              alarm.time.minute,
            );
    } else if (alarm.repeatDays.isNotEmpty) {
      // Para alarmas personalizadas
      int daysToAdd = 1;
      while (daysToAdd <= 7) {
        final testDate = now.add(Duration(days: daysToAdd));
        if (alarm.repeatDays.contains(testDate.weekday)) {
          nextTime = DateTime(
            testDate.year,
            testDate.month,
            testDate.day,
            alarm.time.hour,
            alarm.time.minute,
          );
          break;
        }
        daysToAdd++;
      }
    }

    return nextTime;
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) {
      return '--:--:--';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // No olvides cancelar el timer en dispose
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Widget _buildNextAlarmSection() {
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null || !_showNextAlarmSection) {
      return const SizedBox.shrink();
    }

    final otherActiveAlarmsCount = _alarms
        .where((a) => a.isActive && a.id != nextAlarm.id)
        .length;

    return Container(
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.green.shade400, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Próxima Alarma: ${TimeOfDay.fromDateTime(nextAlarm.time).format(context)}'
                .toUpperCase(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      nextAlarm.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (nextAlarm.message.isNotEmpty)
                      Text(
                        nextAlarm.message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
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
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                otherActiveAlarmsCount > 0
                    ? '$otherActiveAlarmsCount otra${otherActiveAlarmsCount > 1 ? 's' : ''} alarma${otherActiveAlarmsCount > 1 ? 's' : ''} activa${otherActiveAlarmsCount > 1 ? 's' : ''}'
                    : 'No hay otras alarmas activas',
              ),
            ],
          ),
        ],
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
      title: Text(alarm.title, style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alarm.message.isNotEmpty ? alarm.message : 'Sin mensaje'),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text('Próxima vez: '),
              Text(
                TimeOfDay.fromDateTime(alarm.time).format(context),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
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

  // NUEVO: Método para construir el contenedor de alarma sonando
  Widget _buildRingingAlarmContainer() {
    if (!_isAlarmRinging || _ringingAlarmId == null) {
      return const SizedBox.shrink();
    }

    final canSnooze = _ringingAlarmSnoozeCount < _ringingAlarmMaxSnoozes;

    return GestureDetector(
      onTap: () {
        // Navegar a AlarmScreen cuando se toca el contenedor
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlarmScreen(
              arguments: {
                'alarmId': _ringingAlarmId!,
                'title': _ringingAlarmTitle,
                'message': _ringingAlarmMessage,
                'snoozeCount': _ringingAlarmSnoozeCount,
                'maxSnoozes': _ringingAlarmMaxSnoozes,
                'snoozeDurationMinutes': _ringingAlarmSnoozeDuration,
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.red.shade400, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.red.shade200,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.alarm, color: Colors.red.shade700, size: 35),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ALARMA SONANDO',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _ringingAlarmTitle.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 35,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 235, 64, 52),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_ringingAlarmMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _ringingAlarmMessage,
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await platform.invokeMethod('stopAlarm', {
                        'alarmId': _ringingAlarmId,
                      });
                    } catch (e) {
                      print('Error stopping alarm: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'APAGAR ALARMA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),

                const SizedBox(height: 12),
                if (canSnooze)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await platform.invokeMethod('snoozeAlarm', {
                          'alarmId': _ringingAlarmId,
                          'maxSnoozes': _ringingAlarmMaxSnoozes,
                          'snoozeDurationMinutes': _ringingAlarmSnoozeDuration,
                        });
                      } catch (e) {
                        print('Error snoozing alarm: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'POSPONER $_ringingAlarmSnoozeDuration MIN',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (!canSnooze) ...[
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.warning, color: Colors.white, size: 25),
                        Text(
                          'Máximo Posposiciones Alcanzado ($_ringingAlarmSnoozeCount/$_ringingAlarmMaxSnoozes)',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 255, 255, 255),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
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

          // NUEVO: Contenedor para alarma sonando
          _buildRingingAlarmContainer(),
          if (_getSnoozedAlarms().isNotEmpty)
            Container(
              margin: const EdgeInsets.all(8.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.orange.shade400, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.shade200,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.snooze,
                        color: Colors.orange.shade700,
                        size: 35,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Alarmas Pospuestas (${_getSnoozedAlarms().length})'
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._getSnoozedAlarms()
                      .map(
                        (alarm) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alarm.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      'Sonará: ${DateFormat('HH:mm').format(alarm.time)}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      'Pospuesta: ${alarm.snoozeCount}/${alarm.maxSnoozes} veces',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  // Desactivar alarma pospuesta
                                  await _toggleAlarmState(alarm.id, false);
                                  // Resetear contador de snooze
                                  setState(() {
                                    final index = _alarms.indexWhere(
                                      (a) => a.id == alarm.id,
                                    );
                                    if (index != -1) {
                                      _alarms[index].snoozeCount = 0;
                                    }
                                  });
                                  await _saveAlarms();
                                },
                                icon: Icon(
                                  Icons.cancel,
                                  color: Colors.red.shade600,
                                ),
                                tooltip: 'Desactivar alarma pospuesta',
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ],
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
