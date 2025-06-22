import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';

class AlarmEditScreen extends StatefulWidget {
  final Alarm? alarm; // null para crear nueva alarma, Alarm para editar

  const AlarmEditScreen({Key? key, this.alarm}) : super(key: key);

  @override
  _AlarmEditScreenState createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late TextEditingController _titleController;
  late TextEditingController _messageController;

  TimeOfDay _selectedTime = TimeOfDay.now();
  String _repetitionType = 'none';
  List<int> _selectedDays = [];
  int _maxSnoozes = 3;
  int _snoozeDuration = 5;

  final List<String> _daysOfWeek = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  final List<Map<String, String>> _repetitionOptions = [
    {'value': 'none', 'label': 'Sin repetición'},
    {'value': 'daily', 'label': 'Diaria'},
    {'value': 'weekly', 'label': 'Semanal (mismo día)'},
    {'value': 'weekend', 'label': 'Fines de semana (Sáb-Dom)'},
    {'value': 'custom', 'label': 'Personalizada'},
  ];

  @override
  void initState() {
    super.initState();
    _loadDefaultSettings(); // Agregar esta línea

    // Inicializar controladores y valores
    if (widget.alarm != null) {
      // Modo edición
      _titleController = TextEditingController(text: widget.alarm!.title);
      _messageController = TextEditingController(text: widget.alarm!.message);
      _selectedTime = TimeOfDay(
        hour: widget.alarm!.time.hour,
        minute: widget.alarm!.time.minute,
      );
      _maxSnoozes = widget.alarm!.maxSnoozes;
      _snoozeDuration = widget.alarm!.snoozeDurationMinutes;

      // Configurar repetición
      if (widget.alarm!.isDaily) {
        _repetitionType = 'daily';
      } else if (widget.alarm!.isWeekly) {
        _repetitionType = 'weekly';
      } else if (widget.alarm!.isWeekend) {
        _repetitionType = 'weekend';
      } else if (widget.alarm!.repeatDays.isNotEmpty) {
        _repetitionType = 'custom';
        _selectedDays = List.from(widget.alarm!.repeatDays);
      }
    } else {
      // Modo creación
      _titleController = TextEditingController();
      _messageController = TextEditingController();
    }
  }

  // Agregar este método
  Future<void> _loadDefaultSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (widget.alarm == null) {
      // Solo para alarmas nuevas
      setState(() {
        _maxSnoozes = prefs.getInt('max_snoozes') ?? 3;
        _snoozeDuration = prefs.getInt('snooze_duration_minutes') ?? 5;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _selectTime() async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      cancelText: 'Cerrar',
      confirmText: 'Aceptar',
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
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
      setState(() {
        _selectedTime = selectedTime;
      });
    }
  }

  void _updateRepetitionType(String? value) {
    setState(() {
      _repetitionType = value!;

      // Configurar días según el tipo de repetición
      if (value == 'weekly') {
        final now = DateTime.now();
        _selectedDays = [now.weekday];
      } else if (value == 'weekend') {
        _selectedDays = [DateTime.saturday, DateTime.sunday];
      } else if (value != 'custom') {
        _selectedDays = [];
      }
    });
  }

  void _toggleDay(int dayValue) {
    setState(() {
      if (_selectedDays.contains(dayValue)) {
        _selectedDays.remove(dayValue);
      } else {
        _selectedDays.add(dayValue);
      }
    });
  }

  void _saveAlarm() {
    // Validaciones
    // if (_titleController.text.trim().isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('Por favor, ingresa un título')),
    //   );
    //   return;
    // }

    if (_repetitionType == 'custom' && _selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona al menos un día')),
      );
      return;
    }

    // Preparar resultado
    final result = {
      'time': _selectedTime,
      'title': _titleController.text,
      'message': _messageController.text,
      'repetitionType': _repetitionType,
      'repeatDays': _selectedDays,
      'maxSnoozes': _maxSnoozes,
      'snoozeDuration': _snoozeDuration,
      'alarm': widget.alarm, // Para saber si es edición
    };

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.alarm == null ? 'Nueva Alarma' : 'Editar Alarma',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: const Text(
              'Guardar',
              style: TextStyle(color: Colors.green, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selector de hora
            Card(
              color: Colors.grey[900],
              child: ListTile(
                leading: const Icon(Icons.access_time, color: Colors.green),
                title: const Text(
                  'Hora',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _selectedTime.format(context),
                  style: const TextStyle(color: Colors.green, fontSize: 18),
                ),
                onTap: _selectTime,
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Título
            const Text(
              'Título',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Título de la alarma',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Mensaje
            const Text(
              'Mensaje',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Mensaje de la alarma',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Repetición
            const Text(
              'Repetición',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),

            ..._repetitionOptions.map(
              (option) => RadioListTile<String>(
                title: Text(
                  option['label']!,
                  style: const TextStyle(color: Colors.white),
                ),
                value: option['value']!,
                groupValue: _repetitionType,
                onChanged: _updateRepetitionType,
                activeColor: Colors.green,
              ),
            ),

            // Selección de días personalizados
            if (_repetitionType == 'custom') ...[
              const SizedBox(height: 16),
              const Text(
                'Selecciona los días:',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                children: List.generate(7, (index) {
                  final dayValue = index + 1;
                  return FilterChip(
                    label: Text(_daysOfWeek[index]),
                    selected: _selectedDays.contains(dayValue),
                    onSelected: (selected) => _toggleDay(dayValue),
                    selectedColor: Colors.green,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                      color: _selectedDays.contains(dayValue)
                          ? Colors.black
                          : Colors.white,
                    ),
                  );
                }),
              ),
            ],

            const SizedBox(height: 20),

            // Configuración de Snooze
            const Text(
              'Configuración de Snooze',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),

            // Duración del snooze
            Text(
              'Duración: $_snoozeDuration minutos',
              style: const TextStyle(color: Colors.white),
            ),
            Slider(
              value: _snoozeDuration.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_snoozeDuration min',
              activeColor: Colors.green,
              onChanged: (value) {
                setState(() {
                  _snoozeDuration = value.toInt();
                });
              },
            ),

            const SizedBox(height: 16),

            // Número máximo de snoozes
            Text(
              'Número máximo de snoozes: $_maxSnoozes',
              style: const TextStyle(color: Colors.white),
            ),
            Slider(
              value: _maxSnoozes.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              label: _maxSnoozes.toString(),
              activeColor: Colors.green,
              onChanged: (value) {
                setState(() {
                  _maxSnoozes = value.toInt();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
