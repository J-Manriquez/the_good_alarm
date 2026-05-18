import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';
import '../services/medication_scheduler.dart';
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
    try {
      // Override volúmen del sistema con la configuración del medicamento
      final saved = await _channel.invokeMethod<int>('setMusicStreamVolume', {'volumePercent': med.ttsVolume});
      if (saved != null) _savedMusicVolume = saved;
      print('[MedicationConfirmScreen] volumen seteado a ${med.ttsVolume}% (guardado=$_savedMusicVolume)');
      await _tts.setLanguage(med.ttsLanguage);
      await _tts.setSpeechRate(0.5);
      _ttsRepeatCount = 0;
      _ttsEnabled = true;
      String textToSpeak;
      if (existing != null && existing.status == 'taken') {
        final hora = _confirmedAtText(existing);
        textToSpeak = med.buildTtsAlreadyConfirmedText(hora, scheduledTimeText: _timeText);
      } else {
        textToSpeak = med.buildTtsConfirmationText(scheduledTimeText: _timeText);
      }
      // Repetir hasta 3 veces en total
      _tts.setCompletionHandler(() {
        if (_ttsRepeatCount < 2 && _ttsEnabled && mounted) {
          _ttsRepeatCount++;
          print('[MedicationConfirmScreen] TTS repetición $_ttsRepeatCount/2');
          _tts.speak(textToSpeak);
        }
      });
      print('[MedicationConfirmScreen] TTS: $textToSpeak');
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
    try {
      await _tts.stop();
      // Restaurar volúmen original
      if (_savedMusicVolume >= 0) {
        await _channel.invokeMethod('restoreMusicStreamVolume', {'savedVolume': _savedMusicVolume});
        print('[MedicationConfirmScreen] volumen restaurado a $_savedMusicVolume');
        _savedMusicVolume = -1;
      }
    } catch (_) {}
  }

  DateTime get _scheduledAtLocal =>
      DateTime.fromMillisecondsSinceEpoch(_scheduledAtLocalMillis);

  String get _timeText {
    final dt = _scheduledAtLocal;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
    _tts.stop();
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
        : (alreadyTaken ? Colors.green.shade50 : scheme.surface);

    final isLight = ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final onCard = isLight ? Colors.black87 : Colors.white;

    return Scaffold(
      backgroundColor: scheme.background,
      body: SafeArea(
        child: Center(
          child: Card(
            color: cardColor,
            margin: const EdgeInsets.all(16),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícono, hora y botón mute
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (med.enableTts) const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              alreadyTaken ? Icons.check_circle : Icons.help_outline,
                              size: 64,
                              color: alreadyTaken ? Colors.green.shade600 : scheme.primary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _timeText,
                              style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: onCard.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),
                      if (med.enableTts)
                        IconButton(
                          icon: Icon(
                            _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                            color: onCard.withOpacity(0.75),
                          ),
                          iconSize: 28,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: _ttsEnabled ? 'Silenciar' : 'Silenciado',
                          onPressed: () {
                            if (_ttsEnabled) {
                              setState(() => _ttsEnabled = false);
                              _stopTts();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Título de la confirmación
                  Text(
                    alreadyTaken
                        ? '¿Confirmás que tomaste ${med.medicationName}?'
                        : '¿Ya tomaste ${med.medicationName}?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: onCard),
                  ),
                  const SizedBox(height: 6),

                  // Dosis
                  if (med.dosageAmount.isNotEmpty)
                    Text(
                      '${med.dosageAmount} ${med.dosageUnit}',
                      style: TextStyle(
                          fontSize: 16,
                          color: onCard.withOpacity(0.8)),
                    ),

                  if (alreadyTaken && _existingCompletion?.confirmedAtLocal != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Confirmado previamente a las ${_confirmedAtText(_existingCompletion!)}',
                      style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600),
                    ),
                  ],

                  if (med.instructions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      med.instructions,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: onCard.withOpacity(0.75)),
                    ),
                  ],

                  const SizedBox(height: 22),
                  const Divider(),
                  const SizedBox(height: 14),

                  // Botones de confirmación en columna, ancho completo
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _confirmTaken,
                      icon: const Icon(Icons.check),
                      label: Text(alreadyTaken ? 'Sí, es correcto' : 'Sí, lo tomé'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _confirmNotTaken,
                      icon: const Icon(Icons.close),
                      label: Text(alreadyTaken ? 'No, no lo tomé' : 'No lo tomé'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
