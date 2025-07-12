import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'services/game_service.dart';
import 'games/alarm_game_wrapper.dart';
import 'settings_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AlarmEditScreen extends StatefulWidget {
  final Alarm? alarm; // null para crear nueva alarma, Alarm para editar

  const AlarmEditScreen({super.key, this.alarm});

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
  bool _requireGame = false;
  GameConfig? _gameConfig;
  bool _syncToCloud = true;
  bool _cloudSyncEnabled = false;
  
  // Nuevas variables para configuraciones de volumen
  int _maxVolumePercent = 100;
  int _volumeRampUpDurationSeconds = 30;
  int _tempVolumeReductionPercent = 30;
  int _tempVolumeReductionDurationSeconds = 60;
  
  // Variables para controlar la expansión de las tarjetas
  bool _isSnoozeExpanded = false;
  bool _isVolumeExpanded = false;
  bool _isGameExpanded = false;

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
      _requireGame = widget.alarm!.requireGame;
      _gameConfig = widget.alarm!.gameConfig;
      _syncToCloud = widget.alarm!.syncToCloud;
      _maxVolumePercent = widget.alarm!.maxVolumePercent;
      _volumeRampUpDurationSeconds = widget.alarm!.volumeRampUpDurationSeconds;
      _tempVolumeReductionPercent = widget.alarm!.tempVolumeReductionPercent;
      _tempVolumeReductionDurationSeconds = widget.alarm!.tempVolumeReductionDurationSeconds;

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
    final cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    
    setState(() {
      _cloudSyncEnabled = cloudSyncEnabled;
      if (widget.alarm == null) {
        // Solo para alarmas nuevas
        _maxSnoozes = prefs.getInt('max_snoozes') ?? 3;
        _snoozeDuration = prefs.getInt('snooze_duration_minutes') ?? 5;
        _syncToCloud = cloudSyncEnabled; // Por defecto, sincronizar si está habilitado
        
        // Cargar configuraciones predeterminadas de volumen
        _maxVolumePercent = prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100;
        _volumeRampUpDurationSeconds = prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30;
        _tempVolumeReductionPercent = prefs.getInt(SettingsScreen.defaultTempVolumeReductionKey) ?? 30;
        _tempVolumeReductionDurationSeconds = prefs.getInt(SettingsScreen.defaultTempVolumeReductionDurationKey) ?? 60;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Método helper para crear tarjetas colapsables
  Widget _buildCollapsibleCard({
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.green, width: 2),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.green,
            ),
            onTap: onTap,
          ),
          if (isExpanded) ...[
            const Divider(color: Colors.green, height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
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
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              hourMinuteColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color.fromARGB(255, 208, 252, 210)
                    : const Color.fromARGB(255, 255, 255, 255),
              ),
              dayPeriodTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color.fromARGB(255, 0, 0, 0)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              dayPeriodColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
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
                foregroundColor: WidgetStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                backgroundColor: WidgetStateProperty.all(Colors.green),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(
                  const Color.fromARGB(255, 0, 0, 0),
                ),
                backgroundColor: WidgetStateProperty.all(
                  const Color.fromARGB(255, 255, 255, 255),
                ),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 20),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(
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

  Future<void> _selectGame() async {
    final gameConfig = await GameService.selectGameForAlarm(context);
    if (gameConfig != null) {
      setState(() {
        _gameConfig = gameConfig;
        _requireGame = true;
      });
    }
  }

  void _removeGame() {
    setState(() {
      _gameConfig = null;
      _requireGame = false;
    });
  }

  void _saveAlarm() {
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
      'requireGame': _requireGame,
      'gameConfig': _gameConfig,
      'syncToCloud': _syncToCloud,
      'alarm': widget.alarm,
      'maxVolumePercent': _maxVolumePercent,
      'volumeRampUpDurationSeconds': _volumeRampUpDurationSeconds,
      'tempVolumeReductionPercent': _tempVolumeReductionPercent,
      'tempVolumeReductionDurationSeconds': _tempVolumeReductionDurationSeconds,
    };

    Navigator.pop(context, result);
  }

    String _getGameName(GameType gameType) {
    switch (gameType) {
      case GameType.memorice:
        return 'Memorice';
      case GameType.equations:
        return 'Ecuaciones';
      case GameType.sequence:
        return 'Secuencia';
    }
  }

  String _getGameDescription(GameConfig config) {
    switch (config.gameType) {
      case GameType.memorice:
        return 'Dificultad: ${config.livesLabel} • ${config.parameter} parejas • ${config.repetitions} rondas';
      case GameType.equations:
        return 'Dificultad: ${config.livesLabel} • ${config.parameter} ecuaciones • ${config.repetitions} rondas';
      case GameType.sequence:
        return 'Dificultad: ${config.livesLabel} • Secuencia de ${config.parameter} • ${config.repetitions} rondas';
    }
  }

  IconData _getGameIcon(GameType gameType) {
    switch (gameType) {
      case GameType.memorice:
        return Icons.memory;
      case GameType.equations:
        return Icons.calculate;
      case GameType.sequence:
        return Icons.format_list_numbered;
    }
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

            // Tarjeta de Configuración de Snooze
            _buildCollapsibleCard(
              title: 'Configuración de Snooze',
              isExpanded: _isSnoozeExpanded,
              onTap: () {
                setState(() {
                  _isSnoozeExpanded = !_isSnoozeExpanded;
                });
              },
              children: [
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

            const SizedBox(height: 20),

            // Tarjeta de Configuración de Volumen
            _buildCollapsibleCard(
              title: 'Configuración de Volumen',
              isExpanded: _isVolumeExpanded,
              onTap: () {
                setState(() {
                  _isVolumeExpanded = !_isVolumeExpanded;
                });
              },
              children: [
                Text(
                  'Controla cómo se comporta el volumen de esta alarma',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                const SizedBox(height: 16),
                // Volumen máximo
                Text(
                  'Volumen máximo: $_maxVolumePercent%',
                  style: const TextStyle(color: Colors.white),
                ),
                Slider(
                  value: _maxVolumePercent.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '$_maxVolumePercent%',
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      _maxVolumePercent = value.toInt();
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Duración de escalado de volumen
                Text(
                  'Duración de escalado: $_volumeRampUpDurationSeconds segundos',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  _volumeRampUpDurationSeconds == 0 
                      ? 'El volumen comenzará al máximo inmediatamente'
                      : 'El volumen aumentará gradualmente hasta el máximo',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Slider(
                  value: _volumeRampUpDurationSeconds.toDouble(),
                  min: 0,
                  max: 120,
                  divisions: 24,
                  label: '$_volumeRampUpDurationSeconds s',
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      _volumeRampUpDurationSeconds = value.toInt();
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Porcentaje de reducción temporal
                Text(
                  'Reducción temporal: $_tempVolumeReductionPercent%',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'Volumen al presionar el botón de reducción temporal',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Slider(
                  value: _tempVolumeReductionPercent.toDouble(),
                  min: 10,
                  max: 80,
                  divisions: 14,
                  label: '$_tempVolumeReductionPercent%',
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _tempVolumeReductionPercent = value.toInt();
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Duración de reducción temporal
                Text(
                  'Duración de reducción: $_tempVolumeReductionDurationSeconds segundos',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'Tiempo que durará la reducción de volumen',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Slider(
                  value: _tempVolumeReductionDurationSeconds.toDouble(),
                  min: 15,
                  max: 300,
                  divisions: 19,
                  label: '$_tempVolumeReductionDurationSeconds s',
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _tempVolumeReductionDurationSeconds = value.toInt();
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Tarjeta de Configuración de Juegos
            _buildCollapsibleCard(
              title: 'Juego para Apagar Alarma',
              isExpanded: _isGameExpanded,
              onTap: () {
                setState(() {
                  _isGameExpanded = !_isGameExpanded;
                });
              },
              children: [
                // Switch para habilitar/deshabilitar juego
                SwitchListTile(
                  title: const Text(
                    'Requerir juego para apagar',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _requireGame
                        ? 'Deberás completar un juego para apagar la alarma'
                        : 'La alarma se puede apagar normalmente',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  value: _requireGame,
                  activeColor: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      _requireGame = value;
                      if (!value) {
                        _gameConfig = null;
                      }
                    });
                  },
                ),
                // Configuración del juego seleccionado
                if (_requireGame) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.grey[900],
                    child: ListTile(
                      leading: Icon(
                        _gameConfig != null
                            ? _getGameIcon(_gameConfig!.gameType)
                            : Icons.videogame_asset,
                        color: Colors.green,
                      ),
                      title: Text(
                        _gameConfig != null
                            ? _getGameName(_gameConfig!.gameType)
                            : 'Seleccionar juego',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: _gameConfig != null
                          ? Text(
                              _getGameDescription(_gameConfig!),
                              style: TextStyle(color: Colors.grey[400]),
                            )
                          : const Text(
                              'Toca para elegir un juego',
                              style: TextStyle(color: Colors.grey),
                            ),
                      trailing: _gameConfig != null
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _removeGame,
                            )
                          : const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                            ),
                      onTap: _selectGame,
                    ),
                  ),
                ],
              ],
            ),

            // Card de sincronización en la nube
            if (_cloudSyncEnabled && FirebaseAuth.instance.currentUser != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Sincronización en la Nube',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.grey[900],
                child: SwitchListTile(
                  title: const Text(
                    'Guardar en Firebase',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _syncToCloud
                        ? 'Esta alarma se sincronizará con la nube'
                        : 'Esta alarma solo se guardará localmente',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  value: _syncToCloud,
                  activeColor: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      _syncToCloud = value;
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
