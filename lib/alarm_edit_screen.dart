import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'services/game_service.dart';
import 'games/alarm_game_wrapper.dart';
import 'settings_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/piper_voice_catalog.dart';
import 'services/piper_tts_service.dart';
import 'widgets/voices_manager_modal.dart';

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
  bool _isTtsExpanded = false;

  // Variables para TTS
  final FlutterTts _tts = FlutterTts();
  AudioPlayer? _previewPlayer;
  bool _enableTts = true;
  String _ttsLanguage = 'es-MX';
  int _ttsVolume = 80;
  double _ttsPitch = 1.0;
  int _ttsRepeatCount = 3;
  int _ttsRepeatDelaySeconds = 1;
  bool _ttsUsePrefix = false;
  String? _ttsVoice;
  String? _piperVoice;
  List<Map<dynamic, dynamic>> _availableVoices = [];
  List<String> _availableLocales = ['es-MX', 'es-ES', 'en-US'];

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
    _loadVoices();

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
      _enableTts = widget.alarm!.enableTts;
      _ttsLanguage = widget.alarm!.ttsLanguage;
      _ttsVolume = widget.alarm!.ttsVolume;
      _ttsPitch = widget.alarm!.ttsPitch;
      _ttsRepeatCount = widget.alarm!.ttsRepeatCount;
      _ttsRepeatDelaySeconds = widget.alarm!.ttsRepeatDelaySeconds;
      _ttsUsePrefix = widget.alarm!.ttsUsePrefix;
      _ttsVoice = widget.alarm!.ttsVoice;
      _piperVoice = widget.alarm!.piperVoice;

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

        // Cargar configuraciones predeterminadas de TTS
        final ttsVoice = prefs.getString(SettingsScreen.defaultTtsPiperVoiceKey);
        if (ttsVoice != null) _piperVoice = ttsVoice;
        _ttsLanguage = prefs.getString(SettingsScreen.defaultTtsLanguageKey) ?? 'es-MX';
        _ttsPitch = prefs.getDouble(SettingsScreen.defaultTtsPitchKey) ?? 1.0;
        _ttsVolume = prefs.getInt(SettingsScreen.defaultTtsVolumeKey) ?? 80;
        _ttsRepeatCount = prefs.getInt(SettingsScreen.defaultTtsRepeatCountKey) ?? 3;
        _ttsRepeatDelaySeconds = prefs.getInt(SettingsScreen.defaultTtsRepeatDelayKey) ?? 1;
      }
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
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
    Widget? headerAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary, width: 2),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: headerAction != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      headerAction,
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: scheme.primary,
                      ),
                    ],
                  )
                : Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.primary,
                  ),
            onTap: onTap,
          ),
          if (isExpanded) ...[
            Divider(color: scheme.primary, height: 1),
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
        final scheme = Theme.of(context).colorScheme;
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: scheme.surface,
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.onPrimary
                    : scheme.onSurface,
              ),
              hourMinuteColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
              ),
              dayPeriodTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.onPrimary
                    : scheme.onSurface,
              ),
              dayPeriodColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
              ),
              dialHandColor: scheme.primary,
              dialBackgroundColor: scheme.surfaceContainerHighest,
              entryModeIconColor: scheme.primary,
              helpTextStyle: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(scheme.onPrimary),
                backgroundColor: WidgetStateProperty.all(scheme.primary),
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
                foregroundColor: WidgetStateProperty.all(scheme.onSurface),
                backgroundColor: WidgetStateProperty.all(scheme.surface),
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
                  scheme.onSurface,
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

  Future<void> _openVoicesManager() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => VoicesManagerModal(selectedVoiceId: _piperVoice),
    );
    // result == null significa que se cerró sin cambios (no se tocó ningún botón)
    // Si el usuario pulsó "Quitar voz Piper" devuelve null explícito
    // distinguimos con la bandera devuelta por el modal
    if (!mounted) return;
    // showModalBottomSheet retorna el valor de Navigator.pop, que puede ser
    // String (voz seleccionada), null (cerrado sin acción) o '' (quitar)
    setState(() => _piperVoice = result);
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await _tts.getVoices;
      if (voices != null && mounted) {
        final list = List<Map<dynamic, dynamic>>.from(voices);
        // Extraer locales únicos y ordenarlos
        final localeSet = <String>{};
        for (final v in list) {
          final locale = v['locale'] as String?;
          if (locale != null && locale.isNotEmpty) localeSet.add(locale);
        }
        final locales = localeSet.toList()..sort();
        setState(() {
          _availableVoices = list;
          if (locales.isNotEmpty) {
            _availableLocales = locales;
            // Si el idioma actual no existe entre los disponibles, usar el primero
            if (!_availableLocales.contains(_ttsLanguage)) {
              _ttsLanguage = _availableLocales.first;
              _ttsVoice = null;
            }
          }
        });
      }
    } catch (e) {
      print('[AlarmEditScreen] Error al cargar voces: $e');
    }
  }

  String _piperVoiceName(String voiceId) {
    try {
      final v = piperVoiceCatalog.firstWhere((v) => v.id == voiceId);
      return '${v.displayName} · ${v.locale} · ${v.qualityLabel}';
    } catch (_) {
      return voiceId;
    }
  }

  String _localeDisplayName(String locale) {
    const names = {
      'es-MX': 'Español (México)',
      'es-ES': 'Español (España)',
      'es-US': 'Español (EE.UU.)',
      'es-419': 'Español (Latinoamérica)',
      'es': 'Español',
      'en-US': 'English (US)',
      'en-GB': 'English (UK)',
      'en-AU': 'English (Australia)',
      'en-IN': 'English (India)',
      'en': 'English',
      'fr-FR': 'Français (France)',
      'fr': 'Français',
      'pt-BR': 'Português (Brasil)',
      'pt-PT': 'Português (Portugal)',
      'pt': 'Português',
      'de-DE': 'Deutsch',
      'de': 'Deutsch',
      'it-IT': 'Italiano',
      'it': 'Italiano',
      'ja-JP': '日本語',
      'ko-KR': '한국어',
      'zh-CN': '中文 (简体)',
      'zh-TW': '中文 (繁體)',
      'ru-RU': 'Русский',
      'ar': 'العربية',
    };
    return names[locale] ?? locale;
  }

  Future<void> _previewTts() async {
    final name = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Alarma';
    final desc = _messageController.text.trim();
    final prefix = _ttsUsePrefix ? 'Alarma: ' : '';
    final text = '$prefix$name.${desc.isNotEmpty ? ' $desc.' : ''}';

    // Si hay voz Piper configurada, usarla en el preview
    if (_piperVoice != null) {
      try {
        await _tts.stop();
        await _previewPlayer?.stop();
        await _previewPlayer?.dispose();
        _previewPlayer = null;

        final wavPath = await PiperTtsService.instance.synthesizeToWav(text, _piperVoice!);
        if (wavPath == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('El modelo Piper no está descargado aún')),
            );
          }
          return;
        }
        _previewPlayer = AudioPlayer();
        await _previewPlayer!.play(DeviceFileSource(wavPath));
      } catch (e) {
        print('[AlarmEditScreen] Piper preview error: $e');
      }
      return;
    }

    // Sin voz Piper: usar flutter_tts
    try {
      await _tts.stop();
      if (_ttsVoice != null) {
        final voiceMap = _availableVoices.firstWhere(
          (v) => v['name'] == _ttsVoice,
          orElse: () => <dynamic, dynamic>{},
        );
        final voiceLocale = voiceMap['locale'] as String? ?? _ttsLanguage;
        await _tts.setLanguage(voiceLocale);
        await _tts.setVoice({'name': _ttsVoice!, 'locale': voiceLocale});
      } else {
        await _tts.setLanguage(_ttsLanguage);
      }
      await _tts.setVolume(_ttsVolume / 100.0);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(_ttsPitch);
      await _tts.speak(text);
    } catch (e) {
      print('[AlarmEditScreen] TTS preview error: $e');
    }
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
      'enableTts': _enableTts,
      'ttsLanguage': _ttsLanguage,
      'ttsVolume': _ttsVolume,
      'ttsPitch': _ttsPitch,
      'ttsRepeatCount': _ttsRepeatCount,
      'ttsRepeatDelaySeconds': _ttsRepeatDelaySeconds,
      'ttsUsePrefix': _ttsUsePrefix,
      'ttsVoice': _ttsVoice,
      'piperVoice': _piperVoice,
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.alarm == null ? 'Nueva Alarma' : 'Editar Alarma',
        ),
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: Text(
              'Guardar',
              style: TextStyle(color: scheme.primary, fontSize: 16),
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
              color: scheme.surface,
              child: ListTile(
                leading: Icon(Icons.access_time, color: scheme.primary),
                title: Text(
                  'Hora',
                  style: TextStyle(color: scheme.onSurface),
                ),
                subtitle: Text(
                  _selectedTime.format(context),
                  style: TextStyle(color: scheme.primary, fontSize: 18),
                ),
                onTap: _selectTime,
                trailing: const Icon(Icons.arrow_forward_ios),
              ),
            ),

            const SizedBox(height: 20),

            // Título
            Text(
              'Título',
              style: TextStyle(color: scheme.onSurface, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Título de la alarma',
                hintStyle: TextStyle(color: scheme.onSurface),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Mensaje
            Text(
              'Mensaje',
              style: TextStyle(color: scheme.onSurface, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Mensaje de la alarma',
                hintStyle: TextStyle(color: scheme.onSurface),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Repetición
            Text(
              'Repetición',
              style: TextStyle(color: scheme.onSurface, fontSize: 16),
            ),
            const SizedBox(height: 8),

            ..._repetitionOptions.map(
              (option) => RadioListTile<String>(
                title: Text(
                  option['label']!,
                  style: TextStyle(color: scheme.onSurface),
                ),
                value: option['value']!,
                groupValue: _repetitionType,
                onChanged: _updateRepetitionType,
                activeColor: scheme.primary,
              ),
            ),

            // Selección de días personalizados
            if (_repetitionType == 'custom') ...[
              const SizedBox(height: 16),
              Text(
                'Selecciona los días:',
                style: TextStyle(color: scheme.onSurface, fontSize: 16),
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
                    selectedColor: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                      color: _selectedDays.contains(dayValue)
                          ? scheme.onPrimary
                          : scheme.onSurface,
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
                  style: TextStyle(color: scheme.onSurface),
                ),
                Slider(
                  value: _snoozeDuration.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '$_snoozeDuration min',
                  activeColor: scheme.primary,
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
                  style: TextStyle(color: scheme.onSurface),
                ),
                Slider(
                  value: _maxSnoozes.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _maxSnoozes.toString(),
                  activeColor: scheme.primary,
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
                  style: TextStyle(color: scheme.onSurface, fontSize: 14),
                ),
                const SizedBox(height: 16),
                // Volumen máximo
                Text(
                  'Volumen máximo: $_maxVolumePercent%',
                  style: TextStyle(color: scheme.onSurface),
                ),
                Slider(
                  value: _maxVolumePercent.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '$_maxVolumePercent%',
                  activeColor: scheme.secondary,
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
                  style: TextStyle(color: scheme.onSurface),
                ),
                Text(
                  _volumeRampUpDurationSeconds == 0 
                      ? 'El volumen comenzará al máximo inmediatamente'
                      : 'El volumen aumentará gradualmente hasta el máximo',
                  style: TextStyle(color: scheme.onSurface, fontSize: 12),
                ),
                Slider(
                  value: _volumeRampUpDurationSeconds.toDouble(),
                  min: 0,
                  max: 120,
                  divisions: 24,
                  label: '$_volumeRampUpDurationSeconds s',
                  activeColor: scheme.secondary,
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
                  style: TextStyle(color: scheme.onSurface),
                ),
                Text(
                  'Volumen al presionar el botón de reducción temporal',
                  style: TextStyle(color: scheme.onSurface, fontSize: 12),
                ),
                Slider(
                  value: _tempVolumeReductionPercent.toDouble(),
                  min: 10,
                  max: 80,
                  divisions: 14,
                  label: '$_tempVolumeReductionPercent%',
                  activeColor: scheme.tertiary,
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
                  style: TextStyle(color: scheme.onSurface),
                ),
                Text(
                  'Tiempo que durará la reducción de volumen',
                  style: TextStyle(color: scheme.onSurface, fontSize: 12),
                ),
                Slider(
                  value: _tempVolumeReductionDurationSeconds.toDouble(),
                  min: 15,
                  max: 300,
                  divisions: 19,
                  label: '$_tempVolumeReductionDurationSeconds s',
                  activeColor: scheme.tertiary,
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
                  title: Text(
                    'Requerir juego para apagar',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  subtitle: Text(
                    _requireGame
                        ? 'Deberás completar un juego para apagar la alarma'
                        : 'La alarma se puede apagar normalmente',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  value: _requireGame,
                  activeColor: scheme.primary,
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
                    color: scheme.surface,
                    child: ListTile(
                      leading: Icon(
                        _gameConfig != null
                            ? _getGameIcon(_gameConfig!.gameType)
                            : Icons.videogame_asset,
                        color: scheme.primary,
                      ),
                      title: Text(
                        _gameConfig != null
                            ? _getGameName(_gameConfig!.gameType)
                            : 'Seleccionar juego',
                        style: TextStyle(color: scheme.onSurface),
                      ),
                      subtitle: _gameConfig != null
                          ? Text(
                              _getGameDescription(_gameConfig!),
                              style: TextStyle(color: scheme.onSurface),
                            )
                          : Text(
                              'Toca para elegir un juego',
                              style: TextStyle(color: scheme.onSurface),
                            ),
                      trailing: _gameConfig != null
                          ? IconButton(
                              icon: Icon(Icons.close, color: scheme.error),
                              onPressed: _removeGame,
                            )
                          : Icon(
                              Icons.arrow_forward_ios,
                              color: scheme.onSurface,
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
              Text(
                'Sincronización en la Nube',
                style: TextStyle(color: scheme.onSurface, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Card(
                color: scheme.surface,
                child: SwitchListTile(
                  title: Text(
                    'Guardar en Firebase',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  subtitle: Text(
                    _syncToCloud
                        ? 'Esta alarma se sincronizará con la nube'
                        : 'Esta alarma solo se guardará localmente',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  value: _syncToCloud,
                  activeColor: scheme.primary,
                  onChanged: (value) {
                    setState(() {
                      _syncToCloud = value;
                    });
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Tarjeta de Lectura en voz alta (TTS)
            _buildCollapsibleCard(
              title: 'Lectura en voz alta (TTS)',
              isExpanded: _isTtsExpanded,
              onTap: () {
                setState(() {
                  _isTtsExpanded = !_isTtsExpanded;
                });
              },
              headerAction: IconButton(
                icon: const Icon(Icons.settings_voice, size: 20),
                tooltip: 'Gestionar voces Piper',
                onPressed: _openVoicesManager,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              children: [
                SwitchListTile(
                  title: Text(
                    'Leer alarma en voz alta',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  subtitle: Text(
                    _enableTts
                        ? 'Se leerá el nombre y descripción al sonar'
                        : 'Sin lectura en voz alta',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  value: _enableTts,
                  activeColor: scheme.primary,
                  onChanged: (value) {
                    setState(() {
                      _enableTts = value;
                    });
                  },
                ),
                if (_enableTts) ...[
                  // Indicador de voz Piper activa
                  if (_piperVoice != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.record_voice_over,
                              size: 16, color: scheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Voz Piper: ${_piperVoiceName(_piperVoice!)}',
                              style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 13),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                size: 16, color: scheme.onPrimaryContainer),
                            tooltip: 'Quitar voz Piper',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                setState(() => _piperVoice = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Idioma',
                    style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _ttsLanguage,
                    dropdownColor: scheme.surface,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _availableLocales
                        .map((locale) => DropdownMenuItem(
                              value: locale,
                              child: Text(_localeDisplayName(locale)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() {
                        _ttsLanguage = value;
                        _ttsVoice = null;
                      });
                    },
                  ),
                  if (_availableVoices.isNotEmpty) ...[                    const SizedBox(height: 16),
                    Text(
                      'Voz',
                      style: TextStyle(color: scheme.onSurface, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: _ttsVoice,
                      dropdownColor: scheme.surface,
                      style: TextStyle(color: scheme.onSurface),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sistema (según idioma)'),
                        ),
                        ..._availableVoices
                            .where((v) {
                              final locale =
                                  (v['locale'] as String? ?? '').toLowerCase();
                              return locale == _ttsLanguage.toLowerCase();
                            })
                            .map((v) {
                              final name = v['name'] as String? ?? '';
                              final quality = v['quality'] as String? ?? '';
                              final network = v['network_required'] as String?;
                              final isNetwork = network == '1';
                              final label = isNetwork ? '$quality (red)' : '$quality (local)';
                              return DropdownMenuItem<String?>(
                                value: name,
                                child: Text(label),
                              );
                            })
                            .toList(),
                      ],
                      onChanged: (value) => setState(() => _ttsVoice = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Volumen de voz: $_ttsVolume%',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  Slider(
                    value: _ttsVolume.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '$_ttsVolume%',
                    activeColor: scheme.primary,
                    onChanged: (value) {
                      setState(() {
                        _ttsVolume = value.toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.play_arrow, color: scheme.primary),
                      label: Text(
                        'Escuchar vista previa',
                        style: TextStyle(color: scheme.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: scheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _previewTts,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: Text(
                      'Anunciar tipo: "Alarma: [nombre]"',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                    subtitle: Text(
                      _ttsUsePrefix
                          ? 'La voz dirá "Alarma:" antes del nombre'
                          : 'La voz solo dirá el nombre y descripción',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    value: _ttsUsePrefix,
                    activeColor: scheme.primary,
                    checkColor: scheme.onPrimary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) =>
                        setState(() => _ttsUsePrefix = value ?? false),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tono de voz',
                    style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<double>(
                    value: _ttsPitch,
                    dropdownColor: scheme.surface,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0.5, child: Text('Grave')),
                      DropdownMenuItem(value: 1.0, child: Text('Normal')),
                      DropdownMenuItem(value: 1.5, child: Text('Aguda')),
                      DropdownMenuItem(value: 2.0, child: Text('Muy aguda')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _ttsPitch = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Repeticiones',
                    style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in const [
                        (1, '1 vez'),
                        (3, '3 veces'),
                        (5, '5 veces'),
                        (-1, 'Indefinido'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _ttsRepeatCount == entry.$1,
                          selectedColor: scheme.primary,
                          labelStyle: TextStyle(
                            color: _ttsRepeatCount == entry.$1
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                          onSelected: (_) =>
                              setState(() => _ttsRepeatCount = entry.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pausa entre repeticiones',
                    style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const [1, 3, 5, 10, 15])
                        ChoiceChip(
                          label: Text('${s}s'),
                          selected: _ttsRepeatDelaySeconds == s,
                          selectedColor: scheme.primary,
                          labelStyle: TextStyle(
                            color: _ttsRepeatDelaySeconds == s
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                          onSelected: (_) =>
                              setState(() => _ttsRepeatDelaySeconds = s),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

}
