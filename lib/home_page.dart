import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert'; // Para jsonEncode y jsonDecode
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación
import 'settings_screen.dart'; // Importar SettingsScreen
import 'alarm_edit_screen.dart';
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

  bool moreAlarms = false; // Oculto por defecto

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

  // Future<Map<String, dynamic>?> _showAlarmDetailsDialog({
  //   String? initialTitle,
  //   String? initialMessage,
  //   List<int>? initialRepeatDays,
  //   bool? initialIsDaily,
  //   bool? initialIsWeekly,
  //   bool? initialIsWeekend,
  //   int? initialMaxSnoozes,
  //   int? initialSnoozeDuration, // NUEVO PARÁMETRO
  // }) async {
  //   final titleController = TextEditingController(text: initialTitle ?? '');
  //   final messageController = TextEditingController(text: initialMessage ?? '');

  //   // Valores iniciales para repetición
  //   String repetitionType = 'none';
  //   List<int> selectedDays = initialRepeatDays ?? [];

  //   if (initialIsDaily == true) {
  //     repetitionType = 'daily';
  //   } else if (initialIsWeekly == true) {
  //     repetitionType = 'weekly';
  //   } else if (initialIsWeekend == true) {
  //     repetitionType = 'weekend';
  //   } else if (initialRepeatDays != null && initialRepeatDays.isNotEmpty) {
  //     repetitionType = 'custom';
  //     selectedDays = List.from(initialRepeatDays);
  //   }

  //   // Valores para los días de la semana
  //   final daysOfWeek = [
  //     'Lunes',
  //     'Martes',
  //     'Miércoles',
  //     'Jueves',
  //     'Viernes',
  //     'Sábado',
  //     'Domingo',
  //   ];

  //   // Opciones de repetición
  //   final repetitionOptions = [
  //     {'value': 'none', 'label': 'Sin repetición'},
  //     {'value': 'daily', 'label': 'Diaria'},
  //     {'value': 'weekly', 'label': 'Semanal (mismo día)'},
  //     {'value': 'weekend', 'label': 'Fines de semana (Sáb-Dom)'},
  //     {'value': 'custom', 'label': 'Personalizada'},
  //   ];

  //   // Valor para el número máximo de snoozes
  //   int maxSnoozes = initialMaxSnoozes ?? 3;
  //   int snoozeDuration = initialSnoozeDuration ?? 5; // NUEVA VARIABLE

  //   return showDialog<Map<String, dynamic>>(
  //     context: context,
  //     builder: (context) {
  //       return StatefulBuilder(
  //         builder: (context, setState) {
  //           return AlertDialog(
  //             title: Text(
  //               initialTitle == null ? 'Nueva Alarma' : 'Editar Alarma',
  //             ),
  //             content: SingleChildScrollView(
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   TextField(
  //                     controller: titleController,
  //                     decoration: const InputDecoration(hintText: 'Título'),
  //                   ),
  //                   TextField(
  //                     controller: messageController,
  //                     decoration: const InputDecoration(labelText: 'Mensaje'),
  //                   ),
  //                   const SizedBox(height: 16),
  //                   const Text('Repetición:'),
  //                   ...repetitionOptions.map(
  //                     (option) => RadioListTile<String>(
  //                       title: Text(option['label'] as String),
  //                       value: option['value'] as String,
  //                       groupValue: repetitionType,
  //                       onChanged: (value) {
  //                         setState(() {
  //                           repetitionType = value!;

  //                           // Si cambiamos a semanal, añadimos el día actual
  //                           if (value == 'weekly') {
  //                             final now = DateTime.now();
  //                             selectedDays = [now.weekday];
  //                           }
  //                           // Si cambiamos a fin de semana, seleccionamos sábado y domingo
  //                           else if (value == 'weekend') {
  //                             selectedDays = [
  //                               DateTime.saturday,
  //                               DateTime.sunday,
  //                             ];
  //                           }
  //                           // Si no es personalizado, limpiamos la selección
  //                           else if (value != 'custom') {
  //                             selectedDays = [];
  //                           }
  //                         });
  //                       },
  //                     ),
  //                   ),

  //                   // Mostrar selección de días si es personalizado
  //                   if (repetitionType == 'custom')
  //                     Column(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         const SizedBox(height: 8),
  //                         const Text('Selecciona los días:'),
  //                         const SizedBox(height: 8),
  //                         Wrap(
  //                           spacing: 8.0,
  //                           children: List.generate(7, (index) {
  //                             final dayValue =
  //                                 index + 1; // 1-7 para Lunes-Domingo
  //                             return FilterChip(
  //                               label: Text(daysOfWeek[index]),
  //                               selected: selectedDays.contains(dayValue),
  //                               onSelected: (selected) {
  //                                 setState(() {
  //                                   if (selected) {
  //                                     selectedDays.add(dayValue);
  //                                   } else {
  //                                     selectedDays.remove(dayValue);
  //                                   }
  //                                 });
  //                               },
  //                             );
  //                           }),
  //                         ),
  //                       ],
  //                     ),

  //                   const SizedBox(height: 16),
  //                   const Text('Configuración de Snooze:'),
  //                   const SizedBox(height: 8),

  //                   // Duración del snooze
  //                   Text('Duración: $snoozeDuration minutos'),
  //                   Slider(
  //                     value: snoozeDuration.toDouble(),
  //                     min: 1,
  //                     max: 30,
  //                     divisions: 29,
  //                     label: '$snoozeDuration min',
  //                     onChanged: (value) {
  //                       setState(() {
  //                         snoozeDuration = value.toInt();
  //                       });
  //                     },
  //                   ),

  //                   const SizedBox(height: 8),
  //                   const Text('Número máximo de snoozes:'),
  //                   Slider(
  //                     value: maxSnoozes.toDouble(),
  //                     min: 0,
  //                     max: 10,
  //                     divisions: 10,
  //                     label: maxSnoozes.toString(),
  //                     onChanged: (value) {
  //                       setState(() {
  //                         maxSnoozes = value.toInt();
  //                       });
  //                     },
  //                   ),
  //                   Text('Valor actual: $maxSnoozes'),
  //                 ],
  //               ),
  //             ),
  //             actions: [
  //               TextButton(
  //                 onPressed: () => Navigator.pop(context),
  //                 child: const Text('Cancelar'),
  //               ),
  //               TextButton(
  //                 onPressed: () {
  //                   // // Validar que al menos hay un título
  //                   // if (titleController.text.trim().isEmpty) {
  //                   //   ScaffoldMessenger.of(context).showSnackBar(
  //                   //     const SnackBar(
  //                   //       content: Text('Por favor, ingresa un título'),
  //                   //     ),
  //                   //   );
  //                   //   return;
  //                   // }

  //                   // Validar que si es personalizado, al menos hay un día seleccionado
  //                   if (repetitionType == 'custom' && selectedDays.isEmpty) {
  //                     ScaffoldMessenger.of(context).showSnackBar(
  //                       const SnackBar(
  //                         content: Text(
  //                           'Por favor, selecciona al menos un día',
  //                         ),
  //                       ),
  //                     );
  //                     return;
  //                   }

  //                   // Preparar resultado
  //                   final result = {
  //                     'title': titleController.text,
  //                     'message': messageController.text,
  //                     'repetitionType': repetitionType,
  //                     'repeatDays': selectedDays,
  //                     'maxSnoozes': maxSnoozes,
  //                     'snoozeDuration': snoozeDuration, // AGREGAR
  //                   };

  //                   Navigator.pop(context, result);
  //                 },
  //                 child: const Text('Guardar'),
  //               ),
  //             ],
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  // NUEVO: Obtener alarmas pospuestas
  List<Alarm> _getSnoozedAlarms() {
    return _alarms
        .where((alarm) => alarm.snoozeCount > 0 && alarm.isActive)
        .toList();
  }

  // NUEVA: Función para calcular la hora real de una alarma pospuesta
  DateTime _calculateSnoozedAlarmTime(Alarm alarm) {
    if (alarm.snoozeCount == 0) {
      return alarm.time;
    }

    // Calcular la hora original + (minutos de posposición * número de posposiciones)
    final totalSnoozeMinutes = alarm.snoozeDurationMinutes * alarm.snoozeCount;
    return alarm.time.add(Duration(minutes: totalSnoozeMinutes));
  }

  // NUEVA: Función para calcular tiempo faltante para alarma pospuesta
  Duration _calculateTimeUntilSnoozedAlarm(Alarm alarm) {
    final now = DateTime.now();
    final snoozedTime = _calculateSnoozedAlarmTime(alarm);
    return snoozedTime.difference(now);
  }

  // MODIFICADA: Función para calcular correctamente el tiempo hasta la próxima alarma
  Duration _calculateTimeUntilAlarm(Alarm alarm) {
    final now = DateTime.now();
    
    if (!alarm.isRepeating()) {
      // Para alarmas no repetitivas, usar la lógica anterior
      DateTime alarmTime = alarm.time;
      
      if (alarmTime.isBefore(now) || 
          (alarmTime.hour < now.hour || 
           (alarmTime.hour == now.hour && alarmTime.minute <= now.minute))) {
        alarmTime = DateTime(
          now.year,
          now.month,
          now.day + 1,
          alarm.time.hour,
          alarm.time.minute,
        );
      }
      
      return alarmTime.difference(now);
    }
    
    // Para alarmas repetitivas
    DateTime nextAlarmTime = _getNextRepeatAlarmTime(alarm, now);
    return nextAlarmTime.difference(now);
  }
  // NUEVA: Función para calcular la próxima vez que sonará una alarma repetitiva
  DateTime _getNextRepeatAlarmTime(Alarm alarm, DateTime now) {
    DateTime todayAlarmTime = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.time.hour,
      alarm.time.minute,
    );
    
    if (alarm.isDaily) {
      // Si es diaria y aún no ha pasado hoy, es hoy
      if (todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }
      // Si ya pasó, es mañana
      return todayAlarmTime.add(const Duration(days: 1));
    }
    
    if (alarm.isWeekend) {
      // Fin de semana: sábado (6) y domingo (7)
      int currentWeekday = now.weekday;
      
      // Si es sábado o domingo y aún no ha pasado la hora
      if ((currentWeekday == 6 || currentWeekday == 7) && todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }
      
      // Calcular días hasta el próximo fin de semana
      int daysUntilSaturday;
      if (currentWeekday == 7) { // Domingo
        daysUntilSaturday = 6; // Próximo sábado
      } else {
        daysUntilSaturday = 6 - currentWeekday; // Días hasta sábado
      }
      
      return todayAlarmTime.add(Duration(days: daysUntilSaturday));
    }
    
    if (alarm.isWeekly) {
      // Semanal: mismo día de la semana
      int currentWeekday = now.weekday;
      int alarmWeekday = alarm.time.weekday;
      
      // Si es el mismo día y aún no ha pasado la hora
      if (currentWeekday == alarmWeekday && todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }
      
      // Calcular días hasta la próxima semana
      int daysUntilNextWeek = 7 - ((currentWeekday - alarmWeekday) % 7);
      if (daysUntilNextWeek == 7 && currentWeekday == alarmWeekday) {
        daysUntilNextWeek = 7; // Próxima semana
      }
      
      return todayAlarmTime.add(Duration(days: daysUntilNextWeek));
    }
    
    if (alarm.repeatDays.isNotEmpty) {
      // Días personalizados
      int currentWeekday = now.weekday;
      
      // Verificar si hoy está en los días de repetición y aún no ha pasado
      if (alarm.repeatDays.contains(currentWeekday) && todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }
      
      // Buscar el próximo día de repetición
      List<int> sortedDays = List.from(alarm.repeatDays)..sort();
      
      // Buscar el próximo día en esta semana
      for (int day in sortedDays) {
        if (day > currentWeekday) {
          int daysUntil = day - currentWeekday;
          return todayAlarmTime.add(Duration(days: daysUntil));
        }
      }
      
      // Si no hay días restantes esta semana, usar el primer día de la próxima semana
      int firstDay = sortedDays.first;
      int daysUntilNextWeek = 7 - currentWeekday + firstDay;
      return todayAlarmTime.add(Duration(days: daysUntilNextWeek));
    }
    
    // Fallback: mañana
    return todayAlarmTime.add(const Duration(days: 1));
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
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const AlarmEditScreen()),
    );

    if (result != null && mounted) {
      final selectedTime = result['time'] as TimeOfDay;
      final now = DateTime.now();

      var alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
        0,
        0,
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

      final title = result['title']!.isNotEmpty ? result['title']! : 'Alarma';
      final message = result['message']!.isNotEmpty
          ? result['message']!
          : '¡Es hora de despertar!';
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
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => AlarmEditScreen(alarm: alarm)),
    );

    if (result != null && mounted) {
      final selectedTime = result['time'] as TimeOfDay;
      final now = DateTime.now();

      DateTime alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
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
      if (alarmTime.isBefore(nowNormalized) &&
          (!alarm.isRepeating() ||
              selectedTime.hour != alarm.time.hour ||
              selectedTime.minute != alarm.time.minute)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      final title = (result['title'] as String).isNotEmpty
          ? result['title'] as String
          : 'Alarma';
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
            time: alarmTime,
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

  Future<void> _toggleAlarmState(int alarmId, bool isActive) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      if (alarm.isActive == isActive) return; // No change needed

      try {
        if (isActive) {
          // Reactivar alarma: setearla de nuevo
          await _setNativeAlarm(alarm);
          // ScaffoldMessenger.of(
          //   context,
          // ).showSnackBar(const SnackBar(content: Text('Alarma activada')));
        } else {
          // Desactivar alarma: cancelarla
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
          // ScaffoldMessenger.of(
          //   context,
          // ).showSnackBar(const SnackBar(content: Text('Alarma desactivada')));
        }
        _alarms[index].isActive = isActive;
        await _saveAlarms(); // Guardar y refrescar UI
        _startOrUpdateCountdown(); // <--- ADD THIS LINE
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarma ${isActive ? "activada" : "desactivada"}'),
            backgroundColor: isActive
                ? Colors.green
                : const Color.fromARGB(255, 211, 47, 47),
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

    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) {
      // Formato: dd:hh:mm:ss
      return '${days.toString().padLeft(2, '0')}:${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (hours > 0) {
      // Formato: hh:mm:ss
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      // Formato: mm:ss
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
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
        .where((alarm) => alarm.id != nextAlarm.id && alarm.isActive)
        .length;

    return Container(
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.only(
        left: 16.0,
        top: 16.0,
        bottom: 0,
        right: 16.0,
      ),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
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
            margin: const EdgeInsets.all(0),
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
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.all(0),
            padding: const EdgeInsets.all(0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        otherActiveAlarmsCount > 0
                            ? '$otherActiveAlarmsCount otra${otherActiveAlarmsCount > 1 ? 's' : ''} alarma${otherActiveAlarmsCount > 1 ? 's' : ''} activa${otherActiveAlarmsCount > 1 ? 's' : ''}'
                            : 'No hay otras alarmas activas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (otherActiveAlarmsCount > 0) ...[
                      IconButton(
                        icon: Icon(
                          moreAlarms ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          setState(() {
                            moreAlarms = !moreAlarms;
                          });
                        },
                        tooltip: moreAlarms
                            ? 'Ocultar alarmas'
                            : 'Mostrar alarmas',
                      ),
                    ],
                    const SizedBox(width: 16),
                  ],
                ),
                // Lista de alarmas adicionales (ahora fuera del Row)
                if (moreAlarms && otherActiveAlarmsCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.shade400,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: _alarms
                          .where(
                            (alarm) =>
                                alarm.id != nextAlarm.id && alarm.isActive,
                          )
                          .map(
                            (alarm) => Container(
                              // decoration: BoxDecoration(
                              //   border: Border(
                              //     bottom: BorderSide(
                              //       color: Colors.grey[700]!,
                              //       width: 0.5,
                              //     ),
                              //   ),
                              // ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.alarm,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                title: Text(
                                  alarm.title,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (alarm.message.isNotEmpty)
                                      Text(
                                        alarm.message,
                                        style: TextStyle(
                                          color: const Color.fromARGB(
                                            255,
                                            0,
                                            0,
                                            0,
                                          ),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      'Sonará a las ${DateFormat('HH:mm').format(alarm.time)}',
                                      style: TextStyle(
                                        color: const Color.fromARGB(
                                          255,
                                          0,
                                          0,
                                          0,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Switch(
                                  value: alarm.isActive,
                                  onChanged: (bool value) {
                                    _toggleAlarmState(alarm.id, value);
                                  },
                                  activeColor: Colors.green,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onTap: () {
                                  _editAlarm(alarm);
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
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
      title: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${alarm.title} ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontSize: 16,
              ),
            ),
            if (alarm.isRepeating())
              TextSpan(
                text: _getRepeatDaysPrefix(alarm),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
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
              builder: (context) {
                final durationUntilAlarm = _calculateTimeUntilAlarm(alarm);
                return Text(
                  'Faltan: ${_formatDuration(durationUntilAlarm)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green),
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
          borderRadius: BorderRadius.circular(8.0),
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
                      color: Color.fromARGB(255, 211, 47, 47),
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
                      borderRadius: BorderRadius.circular(8.0),
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

  // NUEVA: Función para obtener el prefijo de días de repetición
  String _getRepeatDaysPrefix(Alarm alarm) {
    if (!alarm.isRepeating()) {
      return '';
    }
    
    if (alarm.isDaily) {
      return '[Diario] ';
    }
    
    if (alarm.isWeekend) {
      return '[Fin de semana] ';
    }
    
    if (alarm.isWeekly) {
      return '[Semanal] ';
    }
    
    if (alarm.repeatDays.isNotEmpty) {
      List<String> dayNames = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      List<String> activeDays = [];
      
      for (int day in alarm.repeatDays) {
        if (day >= 1 && day <= 7) {
          activeDays.add(dayNames[day - 1]);
        }
      }
      
      if (activeDays.isNotEmpty) {
        return '[${activeDays.join(',')}] ';
      }
    }
    
    return '';
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<Alarm>> groupedAlarms =
        _currentGroupingOption != AlarmGroupingOption.none
        ? _getGroupedAlarms()
        : {};

    // Verificar si hay alarmas activas
    final hasActiveAlarms = _alarms.any((alarm) => alarm.isActive);
    final nextAlarm = _getNextActiveAlarm();

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
              _loadSettingsAndAlarms();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              color: hasActiveAlarms ? Colors.green : Colors.black,
              child: Text(
                hasActiveAlarms 
                    ? 'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}'
                    : 'No hay alarmas activas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color.fromARGB(255, 255, 255, 255),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Contenedor para alarma sonando
            _buildRingingAlarmContainer(),

            // Contenedor para alarmas pospuestas
            if (_getSnoozedAlarms().isNotEmpty)
              Container(
                margin: const EdgeInsets.all(8.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8.0),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            alarm.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Faltan: ${_formatDuration(_calculateTimeUntilSnoozedAlarm(alarm))}',
                                            style: TextStyle(
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'Sonará a las: ${DateFormat('HH:mm').format(_calculateSnoozedAlarmTime(alarm))}',
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

            // Sección de próxima alarma
            _buildNextAlarmSection(),

            // Lista de alarmas (sin Expanded, ahora dentro del scroll)
            _alarms.isEmpty
                ? Container(
                    height: 200,
                    child: const Center(
                      child: Text('No hay alarmas configuradas'),
                    ),
                  )
                : _currentGroupingOption == AlarmGroupingOption.none
                ? Column(
                    children: _alarms
                        .map((alarm) => _buildAlarmItem(alarm))
                        .toList(),
                  )
                : Column(
                    children: groupedAlarms.keys.map((groupKey) {
                      List<Alarm> alarmsInGroup = groupedAlarms[groupKey]!;
                      bool showActiveOnly =
                          _groupShowActiveOnlyState[groupKey] ?? false;

                      List<Alarm> displayAlarms = showActiveOnly
                          ? alarmsInGroup.where((a) => a.isActive).toList()
                          : alarmsInGroup;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        elevation: 1.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: BorderSide.none,
                        ),
                        child: ExpansionTile(
                          collapsedIconColor: Colors.transparent,
                          key: PageStorageKey(groupKey),
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
                          shape: Border.all(color: Colors.transparent),
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
                    }).toList(),
                  ),
          ],
        ),
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
