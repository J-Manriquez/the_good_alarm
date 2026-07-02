import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';
import '../services/medication_scheduler.dart';
import '../services/piper_tts_service.dart';
import '../settings_screen.dart';

class MedicationConfirmScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const MedicationConfirmScreen({super.key, this.arguments});

  @override
  State<MedicationConfirmScreen> createState() =>
      _MedicationConfirmScreenState();
}

class _MedicationConfirmScreenState extends State<MedicationConfirmScreen> {
  static const _channel = MethodChannel('com.andodevs.the_good_alarm/alarm');

  final MedicationRepository _repo = MedicationRepository();
  final MedicationScheduler _scheduler = MedicationScheduler();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _cloudSyncEnabled = false;
  bool _loading = true;
  MedicationModel? _med;
  MedicationCompletionModel? _existingCompletion;
  int _savedMusicVolume = -1;
  int _ttsRepeatCount = 0;
  bool _ttsEnabled = true;

  late final String _medicationId;
  late final String _occurrenceKey;
  late final int _scheduledAtLocalMillis;

  @override
  void initState() {
    super.initState();
    final args = widget.arguments ?? {};
    _medicationId = args['medicationId'] as String? ?? '';
    _occurrenceKey = args['occurrenceKey'] as String? ?? '';
    _scheduledAtLocalMillis =
        (args['scheduledAtLocalMillis'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    _init();
  }

  Future<void> _init() async {
    print('[MedicationConfirmScreen] init medicationId=$_medicationId occurrenceKey=$_occurrenceKey');
    try {
      final prefs = await SharedPreferences.getInstance();
      _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;

      final med = await _repo.loadLocalMedication(_medicationId);
      final existing = await _repo.getCompletionForOccurrence(_occurrenceKey);

      if (!mounted) return;
      setState(() {
        _med = med;
        _existingCompletion = existing;
        _loading = false;
      });

      if (med != null && med.enableTts) {
        await _speakConfirmation(med, existing);
      }
    } catch (e) {
      print('[MedicationConfirmScreen] init error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _speakConfirmation(
      MedicationModel med, MedicationCompletionModel? existing) async {
    // Configurar volumen: bloque independiente para que un fallo no aborte el TTS
    try {
      final saved = await _channel.invokeMethod<int>(
          'setMusicStreamVolume', {'volumePercent': med.ttsVolume});
      if (saved != null) _savedMusicVolume = saved;
      print('[MedicationConfirmScreen] volumen seteado a ${med.ttsVolume}% (guardado=$_savedMusicVolume)');
    } catch (e) {
      print('[MedicationConfirmScreen] setMusicStreamVolume error (continuando con TTS): $e');
    }

    _ttsRepeatCount = 0;
    _ttsEnabled = true;

    String textToSpeak;
    if (existing != null && existing.status == 'taken') {
      final hora = _confirmedAtText(existing);
      textToSpeak = med.buildTtsAlreadyConfirmedText(hora,
          scheduledTimeText: _scheduledTimeText);
    } else {
      textToSpeak =
          med.buildTtsConfirmationText(scheduledTimeText: _scheduledTimeText);
    }

    // Intentar Piper TTS si la voz está configurada y descargada
    if (med.piperVoice != null) {
      try {
        final isDownloaded =
            await PiperTtsService.instance.isDownloaded(med.piperVoice!);
        if (isDownloaded) {
          final wav = await PiperTtsService.instance
              .synthesizeToWav(textToSpeak, med.piperVoice!);
          if (wav != null) {
            print('[MedicationConfirmScreen] Piper TTS: $textToSpeak');
            _audioPlayer.onPlayerComplete.listen((_) async {
              final shouldRepeat = med.ttsRepeatCount == -1 ||
                  _ttsRepeatCount < (med.ttsRepeatCount - 1);
              if (shouldRepeat && _ttsEnabled && mounted) {
                _ttsRepeatCount++;
                print('[MedicationConfirmScreen] Piper TTS repetición $_ttsRepeatCount');
                if (med.ttsRepeatDelaySeconds > 0) {
                  await Future.delayed(
                      Duration(seconds: med.ttsRepeatDelaySeconds));
                }
                if (_ttsEnabled && mounted) {
                  await _audioPlayer.play(DeviceFileSource(wav));
                }
              }
            });
            await _audioPlayer.play(DeviceFileSource(wav));
            return;
          }
        }
      } catch (e) {
        print(
            '[MedicationConfirmScreen] Piper TTS error, fallback a flutter_tts: $e');
      }
    }

    // Fallback: flutter_tts (voz del sistema)
    try {
      await _tts.setLanguage(med.ttsLanguage);
      await _tts.setSpeechRate(0.5);
      _tts.setCompletionHandler(() async {
        final shouldRepeat = med.ttsRepeatCount == -1 ||
            _ttsRepeatCount < (med.ttsRepeatCount - 1);
        if (shouldRepeat && _ttsEnabled && mounted) {
          _ttsRepeatCount++;
          print('[MedicationConfirmScreen] TTS repetición $_ttsRepeatCount');
          if (med.ttsRepeatDelaySeconds > 0) {
            await Future.delayed(
                Duration(seconds: med.ttsRepeatDelaySeconds));
          }
          if (_ttsEnabled && mounted) _tts.speak(textToSpeak);
        }
      });
      print('[MedicationConfirmScreen] flutter_tts: $textToSpeak');
      await _tts.speak(textToSpeak);
    } catch (e) {
      print('[MedicationConfirmScreen] TTS error: $e');
    }
  }

  String _confirmedAtText(MedicationCompletionModel c) {
    if (c.confirmedAtLocal == null) return '';
    final dt = c.confirmedAtLocal!;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _stopTts() async {
    _ttsEnabled = false;
    try {
      await _tts.stop();
      await _audioPlayer.stop();
      // Restaurar volúmen original
      if (_savedMusicVolume >= 0) {
        await _channel.invokeMethod('restoreMusicStreamVolume', {'savedVolume': _savedMusicVolume});
        print('[MedicationConfirmScreen] volumen restaurado a $_savedMusicVolume');
        _savedMusicVolume = -1;
      }
    } catch (_) {}
  }

  /// Hora original del recordatorio, extraída del occurrenceKey
  /// (formato: "med|{id}|{yyyyMMdd}|{HHmm}").
  /// Esto evita usar la hora en que suena la confirmación en lugar de
  /// la hora a la que estaba programado el medicamento.
  DateTime get _scheduledAtLocal {
    try {
      final parts = _occurrenceKey.split('|');
      if (parts.length >= 4) {
        final dateStr = parts[2]; // yyyyMMdd
        final timeStr = parts[3]; // HHmm
        return DateTime(
          int.parse(dateStr.substring(0, 4)),
          int.parse(dateStr.substring(4, 6)),
          int.parse(dateStr.substring(6, 8)),
          int.parse(timeStr.substring(0, 2)),
          int.parse(timeStr.substring(2, 4)),
        );
      }
    } catch (_) {}
    // Fallback: usar milisegundos recibidos (será la hora de la confirmación)
    return DateTime.fromMillisecondsSinceEpoch(_scheduledAtLocalMillis);
  }

  String get _scheduledTimeText {
    final dt = _scheduledAtLocal;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get _currentTimeText {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmTaken() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationConfirmScreen] confirmTaken occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = _existingCompletion;
    final completion = MedicationCompletionModel(
      id: _occurrenceKey,
      ownerUid: med.ownerUid,
      medicationId: med.id,
      scheduledAtLocal: _scheduledAtLocal,
      confirmedAtLocal: DateTime.now(),
      status: 'taken',
      snoozeCount: existing?.snoozeCount ?? 0,
      dosageAmountTaken: existing?.dosageAmountTaken.isNotEmpty == true
          ? existing!.dosageAmountTaken
          : med.dosageAmount,
      dosageUnitTaken: existing?.dosageUnitTaken.isNotEmpty == true
          ? existing!.dosageUnitTaken
          : med.dosageUnit,
      confirmedViaReminder: true,
      note: '',
    );

    try {
      await _repo.upsertCompletion(
        completion: completion,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: userId,
      );
      print('[MedicationConfirmScreen] completion guardado status=taken confirmedViaReminder=true snoozeCount=${existing?.snoozeCount ?? 0}');
    } catch (e) {
      print('[MedicationConfirmScreen] error guardando completion: $e');
    }

    await _scheduler.dismissNotification(occurrenceKey: _occurrenceKey, isConfirmation: true);
    await _cancelConfirmation();
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmNotTaken() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationConfirmScreen] confirmNotTaken occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = _existingCompletion;
    // Solo actualizar si no hay ya un 'taken'
    if (existing == null || existing.status != 'taken') {
      final completion = MedicationCompletionModel(
        id: _occurrenceKey,
        ownerUid: med.ownerUid,
        medicationId: med.id,
        scheduledAtLocal: _scheduledAtLocal,
        confirmedAtLocal: DateTime.now(),
        status: 'missed',
        snoozeCount: existing?.snoozeCount ?? 0,
        dosageAmountTaken: '',
        dosageUnitTaken: med.dosageUnit,
        confirmedViaReminder: true,
        note: '',
      );
      try {
        await _repo.upsertCompletion(
          completion: completion,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: userId,
        );
        print('[MedicationConfirmScreen] completion guardado status=missed');
      } catch (e) {
        print('[MedicationConfirmScreen] error guardando missed: $e');
      }
    }

    await _scheduler.dismissNotification(occurrenceKey: _occurrenceKey, isConfirmation: true);
    await _cancelConfirmation();
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationConfirmScreen] snooze occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = _existingCompletion;
    final newSnoozeCount = (existing?.snoozeCount ?? 0) + 1;
    final snoozeCompletion = MedicationCompletionModel(
      id: _occurrenceKey,
      ownerUid: med.ownerUid,
      medicationId: med.id,
      scheduledAtLocal: _scheduledAtLocal,
      status: 'pending',
      snoozeCount: newSnoozeCount,
      dosageAmountTaken: med.dosageAmount,
      dosageUnitTaken: med.dosageUnit,
      note: '',
    );
    try {
      await _repo.upsertCompletion(
        completion: snoozeCompletion,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: userId,
      );
      print('[MedicationConfirmScreen] snooze registrado snoozeCount=$newSnoozeCount');
    } catch (e) {
      print('[MedicationConfirmScreen] error guardando snooze: $e');
    }

    final confirmAt =
        DateTime.now().add(Duration(minutes: med.defaultSnoozeMinutes));
    try {
      await _scheduler.scheduleConfirmation(
        med: med,
        occurrenceKey: _occurrenceKey,
        confirmAt: confirmAt,
      );
      print('[MedicationConfirmScreen] nueva confirmación programada para ${confirmAt.toIso8601String()}');
    } catch (e) {
      print('[MedicationConfirmScreen] error reprogramando confirmación: $e');
    }

    await _scheduler.dismissNotification(
        occurrenceKey: _occurrenceKey, isConfirmation: true);
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancelConfirmation() async {
    try {
      await _scheduler.cancelConfirmation(occurrenceKey: _occurrenceKey);
    } catch (e) {
      print('[MedicationConfirmScreen] error cancelando confirmación: $e');
    }
  }

  Future<void> _clearScreenFlag() async {
    try {
      await _scheduler.clearScreenFlag(occurrenceKey: _occurrenceKey);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ttsEnabled = false;
    _tts.stop();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final med = _med;
    if (med == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Medicamento no encontrado'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    }

    final alreadyTaken = _existingCompletion?.status == 'taken';
    final cardColor = med.colorHex.isNotEmpty
        ? Color(int.tryParse(med.colorHex.replaceFirst('#', '0xFF')) ?? scheme.surface.value)
        : (alreadyTaken ? const Color.fromARGB(255, 6, 194, 16) : scheme.surface);

    final isLight = ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final onCard = isLight ? Colors.black87 : Colors.white;

    return Scaffold(
      backgroundColor: scheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Card(
              color: cardColor,
              margin: const EdgeInsets.all(16),
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícono, hora y botón mute
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (med.enableTts) const SizedBox(width: 48),
                        Expanded(
                          child: Column(
                            children: [
                              Icon(
                                alreadyTaken
                                    ? Icons.check_circle
                                    : Icons.help_outline,
                                size: 88,
                                color: alreadyTaken
                                    ? const Color.fromARGB(255, 6, 194, 16)
                                    : scheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _currentTimeText,
                                style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        if (med.enableTts)
                          IconButton(
                            icon: Icon(
                              _ttsEnabled
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              color: onCard.withOpacity(0.75),
                            ),
                            iconSize: 36,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip:
                                _ttsEnabled ? 'Silenciar' : 'Activar voz',
                            onPressed: () {
                              if (_ttsEnabled) {
                                setState(() => _ttsEnabled = false);
                                _stopTts();
                              } else {
                                setState(() => _ttsEnabled = true);
                                _speakConfirmation(
                                    med, _existingCompletion);
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Título de la confirmación
                    Text(
                      alreadyTaken
                          ? '¿Puedes confirmar que tomaste\n${med.medicationName}?'
                          : '¿Ya tomaste\n${med.medicationName}?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: onCard,
                          height: 1.25),
                    ),
                    const SizedBox(height: 10),

                    // Dosis
                    if (med.dosageAmount.isNotEmpty)
                      Text(
                        'Debías tomar ${med.dosageAmount} ${med.dosageUnit}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),

                    const SizedBox(height: 10),
                    Text(
                      'La dosis original era a las $_scheduledTimeText',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600),
                    ),

                    if (med.instructions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        med.instructions,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            color: onCard.withOpacity(0.75)),
                      ),
                    ],

                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 18),

                    // Botón: Sí lo tomé
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _confirmTaken,
                        icon: const Icon(Icons.check, size: 26),
                        label: Text(
                            alreadyTaken ? 'Sí, es correcto' : 'Sí, lo tomé'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 6, 194, 16),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Botón: Posponer
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _snooze,
                        icon: const Icon(Icons.snooze, size: 26),
                        label: Text(
                            'Posponer ${med.defaultSnoozeMinutes} min'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Botón: No lo tomé
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _confirmNotTaken,
                        icon: const Icon(Icons.close, size: 26),
                        label: Text(
                            alreadyTaken ? 'No, no lo tomé' : 'No lo tomé'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
