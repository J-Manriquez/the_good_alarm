import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'package:the_good_alarm/settings_screen.dart';
import 'games/alarm_game_wrapper.dart';
import 'services/piper_tts_service.dart';
import 'services/volume_service.dart';
import 'widgets/volume_control_button.dart';
import 'widgets/synchronized_volume_control_button.dart';

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
  int snoozeCount = 0;
  int maxSnoozes = 3;
  int snoozeDurationMinutes = 5; // Valor por defecto
  static const platform = MethodChannel('com.andodevs.the_good_alarm/alarm');

  // Agregar estas variables para manejar los juegos
  bool requireGame = false;
  GameConfig? gameConfig;

  // Variables para control de volumen
  late VolumeService _volumeService;
  int maxVolumePercent = 100;
  int volumeRampUpDurationSeconds = 0;
  int tempVolumeReductionPercent = 50;
  int tempVolumeReductionDurationSeconds = 30;
  bool _isVolumeReductionActive = false;

  // Variables para TTS
  final FlutterTts _tts = FlutterTts();
  bool enableTts = true;
  String ttsLanguage = 'es-MX';
  int ttsVolume = 80;
  double ttsPitch = 1.0;
  int ttsRepeatCount = 3;    // 1, 3, 5 o -1=indefinido
  int ttsRepeatDelaySeconds = 5;
  int _ttsRepeatCount = 0;
  bool _ttsEnabled = true;
  int _savedMusicVolume = -1;
  bool ttsUsePrefix = false;
  String? ttsVoice;
  String? piperVoice;

  // Audioplayer para Piper TTS
  AudioPlayer? _piperPlayer;
  StreamSubscription? _piperSub;

  @override
  void initState() {
    super.initState();
    
    // Inicializar VolumeService
    _volumeService = VolumeService();

    if (widget.arguments != null) {
      alarmId = widget.arguments!['alarmId'] ?? 0;
      title = widget.arguments!['title'] ?? 'Alarma';
      message = widget.arguments!['message'] ?? '¡Es hora de despertar!';
      snoozeCount = widget.arguments!['snoozeCount'] ?? 0;
      maxSnoozes = widget.arguments!['maxSnoozes'] ?? 3;
      snoozeDurationMinutes = widget.arguments!['snoozeDurationMinutes'] ?? 5;
      requireGame = widget.arguments!['requireGame'] as bool? ?? false;
      gameConfig = widget.arguments!['gameConfig'] as GameConfig?;
      
      // Cargar configuraciones de volumen
      maxVolumePercent = widget.arguments!['maxVolumePercent'] ?? 100;
      volumeRampUpDurationSeconds = widget.arguments!['volumeRampUpDurationSeconds'] ?? 0;
      tempVolumeReductionPercent = widget.arguments!['tempVolumeReductionPercent'] ?? 50;
      tempVolumeReductionDurationSeconds = widget.arguments!['tempVolumeReductionDurationSeconds'] ?? 30;

      // Cargar configuraciones de TTS
      enableTts = widget.arguments!['enableTts'] as bool? ?? true;
      ttsLanguage = widget.arguments!['ttsLanguage'] as String? ?? 'es-MX';
      ttsVolume = widget.arguments!['ttsVolume'] as int? ?? 80;
      ttsPitch = (widget.arguments!['ttsPitch'] as num?)?.toDouble() ?? 1.0;
      ttsRepeatCount = widget.arguments!['ttsRepeatCount'] as int? ?? 3;
      ttsRepeatDelaySeconds = widget.arguments!['ttsRepeatDelaySeconds'] as int? ?? 1;
      ttsUsePrefix = widget.arguments!['ttsUsePrefix'] as bool? ?? false;
      ttsVoice = widget.arguments!['ttsVoice'] as String?;
      piperVoice = widget.arguments!['piperVoice'] as String?;

      // AGREGAR LOGS DE DEPURACIÓN
      print('=== ALARM SCREEN INIT DEBUG ===');
      print('AlarmId: $alarmId');
      print('MaxSnoozes: $maxSnoozes');
      print('SnoozeDurationMinutes: $snoozeDurationMinutes');
      print('SnoozeCount: $snoozeCount');
      print('Volume Config - Max: $maxVolumePercent%, RampUp: ${volumeRampUpDurationSeconds}s');
      print('Volume Config - TempReduction: $tempVolumeReductionPercent%, Duration: ${tempVolumeReductionDurationSeconds}s');
      print('Arguments received: ${widget.arguments}');
      print('=== ALARM SCREEN INIT DEBUG END ===');

      _notifyAlarmRinging();
      _startVolumeControl();
      if (enableTts) {
        _speakAlarm();
      }
    }
  }

  Future<void> _speakAlarm() async {
    try {
      final saved = await platform.invokeMethod<int>('setMusicStreamVolume', {'volumePercent': ttsVolume});
      if (saved != null) _savedMusicVolume = saved;
      final prefix = ttsUsePrefix ? 'Alarma: ' : '';
      final text = '$prefix$title.${message.isNotEmpty ? ' $message.' : ''}';
      _ttsRepeatCount = 0;
      _ttsEnabled = true;

      if (piperVoice != null) {
        await _speakAlarmPiper(text);
      } else {
        if (ttsVoice != null) {
          await _tts.setLanguage(ttsLanguage);
          await _tts.setVoice({'name': ttsVoice!, 'locale': ttsLanguage});
        } else {
          await _tts.setLanguage(ttsLanguage);
        }
        await _tts.setVolume(1.0);
        await _tts.setSpeechRate(0.5);
        await _tts.setPitch(ttsPitch);
        _tts.setCompletionHandler(() async {
          if (!_ttsEnabled || !mounted) return;
          final shouldRepeat = ttsRepeatCount == -1 || _ttsRepeatCount < (ttsRepeatCount - 1);
          if (shouldRepeat) {
            _ttsRepeatCount++;
            if (ttsRepeatDelaySeconds > 0) {
              await Future.delayed(Duration(seconds: ttsRepeatDelaySeconds));
            }
            if (_ttsEnabled && mounted) {
              _tts.speak(text);
            }
          }
        });
        print('[AlarmScreen] TTS: $text (repeat=$ttsRepeatCount, delay=${ttsRepeatDelaySeconds}s, pitch=$ttsPitch)');
        await _tts.speak(text);
      }
    } catch (e) {
      print('[AlarmScreen] TTS error: $e');
    }
  }

  Future<void> _speakAlarmPiper(String text) async {
    final wav = await PiperTtsService.instance.synthesizeToWav(text, piperVoice!);
    if (wav == null || !_ttsEnabled || !mounted) return;

    await _piperSub?.cancel();
    await _piperPlayer?.dispose();
    _piperPlayer = AudioPlayer();

    _piperSub = _piperPlayer!.onPlayerComplete.listen((_) async {
      await _piperSub?.cancel();
      _piperSub = null;
      if (!_ttsEnabled || !mounted) return;
      final shouldRepeat = ttsRepeatCount == -1 || _ttsRepeatCount < (ttsRepeatCount - 1);
      if (shouldRepeat) {
        _ttsRepeatCount++;
        if (ttsRepeatDelaySeconds > 0) {
          await Future.delayed(Duration(seconds: ttsRepeatDelaySeconds));
        }
        if (_ttsEnabled && mounted) _speakAlarmPiper(text);
      }
    });
    await _piperPlayer!.play(DeviceFileSource(wav));
  }

  Future<void> _stopTts() async {
    try {
      _ttsEnabled = false;
      await _tts.stop();
      await _piperSub?.cancel();
      _piperSub = null;
      await _piperPlayer?.stop();
      await _piperPlayer?.dispose();
      _piperPlayer = null;
      if (_savedMusicVolume >= 0) {
        await platform.invokeMethod('restoreMusicStreamVolume', {'savedVolume': _savedMusicVolume});
        print('[AlarmScreen] volumen TTS restaurado a $_savedMusicVolume');
        _savedMusicVolume = -1;
      }
    } catch (_) {}
  }

  // NUEVO: Método para notificar que la alarma está sonando
  Future<void> _notifyAlarmRinging() async {
    try {
      await platform.invokeMethod('notifyAlarmRinging', {
        'alarmId': alarmId,
        'title': title,
        'message': message,
        'snoozeCount': snoozeCount,
        'maxSnoozes': maxSnoozes,
        'snoozeDurationMinutes': snoozeDurationMinutes,
      });
    } catch (e) {
      print('Error notifying alarm ringing: $e');
    }
  }

  // Método para iniciar el control de volumen
  Future<void> _startVolumeControl() async {
    try {
      await _volumeService.startVolumeControl(
        maxVolumePercent,
        volumeRampUpDurationSeconds,
      );
    } catch (e) {
      print('Error starting volume control: $e');
    }
  }

  // Método para manejar la reducción temporal de volumen
  void _onVolumeReductionToggle(bool isActive) {
    setState(() {
      _isVolumeReductionActive = isActive;
    });
    
    if (isActive) {
      _volumeService.setTemporaryVolumeReduction(
        tempVolumeReductionPercent,
        tempVolumeReductionDurationSeconds,
      );
    } else {
      _volumeService.cancelTemporaryVolumeReduction();
    }
  }

  // NUEVO: Cargar configuración de snooze
  Future<void> _loadSnoozeSettings() async {
    print('=== LOAD SNOOZE SETTINGS START ===');
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeDuration = prefs.getInt('snooze_duration_minutes') ?? 5;

      setState(() {
        snoozeDurationMinutes = snoozeDuration;
      });

      print('Loaded snooze duration: $snoozeDurationMinutes minutes');
    } catch (e) {
      print('Error loading snooze settings: $e');
    }
    print('=== LOAD SNOOZE SETTINGS END ===');
  }

  Future<void> _loadSnoozeDuration() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        snoozeDurationMinutes =
            prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
      });
    }
  }

  Future<void> _stopAlarm() async {
    // Si la alarma requiere juego, navegar al juego
    if (requireGame && gameConfig != null) {
      final gameCompleted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => AlarmGameWrapper(
            alarmId: alarmId,
            gameConfig: gameConfig!,
            tempVolumeReductionPercent: tempVolumeReductionPercent,
            tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
          ),
        ),
      );
      
      // Si el usuario regresó sin completar el juego, no hacer nada
      // (la alarma sigue sonando)
      if (gameCompleted == true) {
        _actuallyStopAlarm();
      }
    } else {
      // Si no requiere juego, apagar directamente
      _actuallyStopAlarm();
    }
  }

  Future<void> _actuallyStopAlarm() async {
    // Detener TTS
    await _stopTts();
    // Detener el control de volumen
    try {
      await _volumeService.stopVolumeControl();
    } catch (e) {
      print('Error stopping volume control: $e');
    }
    
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
    print('=== SNOOZE ALARM START ===');
    print('Snoozing alarm ID: $alarmId for $snoozeDurationMinutes minutes');
    print('Current snooze count: $snoozeCount, max: $maxSnoozes');

    if (snoozeCount >= maxSnoozes) {
      print('Maximum snoozes reached, cannot snooze anymore');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo de posposiciones alcanzado')),
      );
      return;
    }

    await _stopTts();

    try {
      await platform.invokeMethod('snoozeAlarm', {
        'alarmId': alarmId,
        'maxSnoozes': maxSnoozes, // AGREGAR
        'snoozeDurationMinutes': snoozeDurationMinutes, // AGREGAR
      });
      print('Snooze command sent to native code');

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error snoozing alarm: $e');
    }
    print('=== SNOOZE ALARM END ===');
  }

  @override
  void dispose() {
    // Detener TTS y control de volumen al salir de la pantalla
    _tts.stop().catchError((_) {});
    _volumeService.stopVolumeControl().catchError((e) {
      print('Error stopping volume control in dispose: $e');
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determinar si se puede posponer
    final canSnooze = snoozeCount < maxSnoozes;
    print('Can snooze: $canSnooze (count: $snoozeCount, max: $maxSnoozes)');
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 85.0),
          child: Text(
            'Alarma Activa',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, size: 30),
            onPressed: () {
              // MODIFICADO: Usar pop en lugar de pushNamed para volver a la instancia existente
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: scheme.error, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                // Text(
                //   title,
                //   style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                //     color: const Color.fromARGB(255, 255, 255, 255),
                //     fontWeight: FontWeight.bold,
                //   ),
                //   textAlign: TextAlign.center,
                // ),
                // const SizedBox(height: 10),
                // Text(
                //   message,
                //   style: Theme.of(context).textTheme.titleLarge?.copyWith(
                //     color: const Color.fromARGB(255, 255, 255, 255),
                //   ),
                //   textAlign: TextAlign.center,
                // ),
                Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 35,
                          fontWeight: FontWeight.bold,
                          color: scheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 20,
                            color: scheme.error,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double
                      .infinity, // Esto hace que el botón ocupe todo el ancho disponible
                  child: ElevatedButton(
                    onPressed: _stopAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      requireGame && gameConfig != null 
                        ? 'JUGAR PARA APAGAR'
                        : 'APAGAR ALARMA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (canSnooze)
                  SizedBox(
                    width: double.infinity,
                    // En el método build
                    child: ElevatedButton(
                      onPressed: _snoozeAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'POSPONER $snoozeDurationMinutes MIN',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                // Botón de control de volumen sincronizado
                SynchronizedVolumeControlButton(
                  tempVolumePercent: tempVolumeReductionPercent,
                  durationSeconds: tempVolumeReductionDurationSeconds,
                  onToggle: (isActive) {
                    setState(() {
                      _isVolumeReductionActive = isActive;
                    });
                    print('Volume reduction toggled in alarm screen: $isActive');
                  },
                  onExpired: () {
                    setState(() {
                      _isVolumeReductionActive = false;
                    });
                    print('Volume reduction expired in alarm screen');
                  },
                ),
                const SizedBox(height: 20),
                // Mostrar un mensaje si se ha alcanzado el máximo de snoozes
                if (!canSnooze) ...[
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: scheme.error),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.warning, color: scheme.onErrorContainer, size: 25),
                        Text(
                          'Máximo Posposiciones Alcanzado ($snoozeCount/$maxSnoozes)',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
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
        ),
      ),
    );
  }
}
