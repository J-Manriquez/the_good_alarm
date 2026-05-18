import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';
import '../services/medication_scheduler.dart';
import '../settings_screen.dart';

class MedicationAlertScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const MedicationAlertScreen({super.key, this.arguments});

  @override
  State<MedicationAlertScreen> createState() => _MedicationAlertScreenState();
}

class _MedicationAlertScreenState extends State<MedicationAlertScreen> {
  static const _channel = MethodChannel('com.andodevs.the_good_alarm/alarm');

  final MedicationRepository _repo = MedicationRepository();
  final MedicationScheduler _scheduler = MedicationScheduler();
  final FlutterTts _tts = FlutterTts();

  bool _cloudSyncEnabled = false;
  bool _loading = true;
  MedicationModel? _med;
  int _savedMusicVolume = -1;

  int _doseIndex = 0;
  String? _lastDoseStatus;
  DateTime? _lastDoseAt;
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
    print('[MedicationAlertScreen] init medicationId=$_medicationId occurrenceKey=$_occurrenceKey');
    try {
      final prefs = await SharedPreferences.getInstance();
      _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
      final med = await _repo.loadLocalMedication(_medicationId);

      // Calcular índice de dosis del día
      int doseIndex = 0;
      if (med != null && med.times.length > 1) {
        final targetH = _scheduledAtLocal.hour;
        final targetM = _scheduledAtLocal.minute;
        final sortedTimes = [...med.times]
          ..sort((a, b) => a.hour != b.hour
              ? a.hour.compareTo(b.hour)
              : a.minute.compareTo(b.minute));
        for (int i = 0; i < sortedTimes.length; i++) {
          if (sortedTimes[i].hour == targetH && sortedTimes[i].minute == targetM) {
            doseIndex = i;
            break;
          }
        }
        print('[MedicationAlertScreen] doseIndex=$doseIndex de ${med.times.length} dosis');
      }

      // Cargar historial de la última dosis
      String? lastDoseStatus;
      DateTime? lastDoseAt;
      if (med != null) {
        try {
          final completions = await _repo.loadLocalCompletionsForMedication(med.id, limit: 20);
          final finished = completions
              .where((c) => c.status != 'pending' && c.id != _occurrenceKey)
              .toList()
            ..sort((a, b) => b.scheduledAtLocal.compareTo(a.scheduledAtLocal));
          if (finished.isNotEmpty) {
            lastDoseStatus = finished.first.status;
            lastDoseAt = finished.first.scheduledAtLocal;
            print('[MedicationAlertScreen] última dosis: status=$lastDoseStatus at=$lastDoseAt');
          }
        } catch (e) {
          print('[MedicationAlertScreen] error cargando historial: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _med = med;
        _doseIndex = doseIndex;
        _lastDoseStatus = lastDoseStatus;
        _lastDoseAt = lastDoseAt;
        _loading = false;
      });
      if (med != null) {
        if (med.enableTts) {
          await _speakReminder(med);
        }
      }
    } catch (e) {
      print('[MedicationAlertScreen] init error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scheduleConfirmation(MedicationModel med) async {
    try {
      final confirmAt = DateTime.now().add(Duration(minutes: med.confirmationDelayMinutes));
      await _scheduler.scheduleConfirmation(
        med: med,
        occurrenceKey: _occurrenceKey,
        confirmAt: confirmAt,
      );
      print('[MedicationAlertScreen] confirmación programada para ${confirmAt.toIso8601String()} (${med.confirmationDelayMinutes} min desde ahora)');
    } catch (e) {
      print('[MedicationAlertScreen] error programando confirmación: $e');
    }
  }

  Future<void> _speakReminder(MedicationModel med) async {
    try {
      // Override volúmen del sistema con la configuración del medicamento
      final saved = await _channel.invokeMethod<int>('setMusicStreamVolume', {'volumePercent': med.ttsVolume});
      if (saved != null) _savedMusicVolume = saved;
      print('[MedicationAlertScreen] volumen seteado a ${med.ttsVolume}% (guardado=$_savedMusicVolume)');
      await _tts.setLanguage(med.ttsLanguage);
      await _tts.setSpeechRate(0.5);
      _ttsRepeatCount = 0;
      _ttsEnabled = true;
      // Repetir el recordatorio hasta 3 veces en total
      _tts.setCompletionHandler(() {
        if (_ttsRepeatCount < 2 && _ttsEnabled && mounted) {
          _ttsRepeatCount++;
          print('[MedicationAlertScreen] TTS repetición $_ttsRepeatCount/2');
          final text = _med?.buildTtsReminderText(
                doseIndex: _doseIndex,
                lastDoseStatus: _lastDoseStatus,
                lastDoseAt: _lastDoseAt,
              ) ??
              '';
          _tts.speak(text);
        }
      });
      final text = med.buildTtsReminderText(
        doseIndex: _doseIndex,
        lastDoseStatus: _lastDoseStatus,
        lastDoseAt: _lastDoseAt,
      );
      print('[MedicationAlertScreen] TTS: $text');
      await _tts.speak(text);
    } catch (e) {
      print('[MedicationAlertScreen] TTS error: $e');
    }
  }

  Future<void> _stopTts() async {
    try {
      await _tts.stop();
      // Restaurar volúmen original
      if (_savedMusicVolume >= 0) {
        await _channel.invokeMethod('restoreMusicStreamVolume', {'savedVolume': _savedMusicVolume});
        print('[MedicationAlertScreen] volumen restaurado a $_savedMusicVolume');
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

  Future<void> _markTaken() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationAlertScreen] markTaken occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = await _repo.getCompletionForOccurrence(_occurrenceKey);
    final completion = MedicationCompletionModel(
      id: _occurrenceKey,
      ownerUid: med.ownerUid,
      medicationId: med.id,
      scheduledAtLocal: _scheduledAtLocal,
      confirmedAtLocal: DateTime.now(),
      status: 'taken',
      snoozeCount: existing?.snoozeCount ?? 0,
      dosageAmountTaken: med.dosageAmount,
      dosageUnitTaken: med.dosageUnit,
      note: '',
    );

    try {
      await _repo.upsertCompletion(
        completion: completion,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: userId,
      );
      print('[MedicationAlertScreen] completion guardado status=taken snoozeCount=${existing?.snoozeCount ?? 0}');
    } catch (e) {
      print('[MedicationAlertScreen] error guardando completion: $e');
    }

    await _scheduler.dismissNotification(occurrenceKey: _occurrenceKey);
    await _scheduleConfirmation(med);
    await _rescheduleNext(med, userId);
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationAlertScreen] snooze occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = await _repo.getCompletionForOccurrence(_occurrenceKey);
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
      print('[MedicationAlertScreen] snooze registrado snoozeCount=$newSnoozeCount');
    } catch (e) {
      print('[MedicationAlertScreen] error guardando snooze: $e');
    }

    final snoozeAt = DateTime.now().add(Duration(minutes: med.defaultSnoozeMinutes));
    final updated = med.copyWith(nextScheduledAtLocal: snoozeAt);
    try {
      await _repo.upsertMedication(
          medication: updated,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: userId);
      await _scheduler.scheduleOccurrence(med: updated, whenLocal: snoozeAt);
      print('[MedicationAlertScreen] snooze programado para ${snoozeAt.toIso8601String()}');
    } catch (e) {
      print('[MedicationAlertScreen] error en snooze: $e');
    }

    await _scheduler.dismissNotification(occurrenceKey: _occurrenceKey);
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    final med = _med;
    if (med == null) return;
    print('[MedicationAlertScreen] skip occurrenceKey=$_occurrenceKey');
    await _stopTts();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final existing = await _repo.getCompletionForOccurrence(_occurrenceKey);
    final completion = MedicationCompletionModel(
      id: _occurrenceKey,
      ownerUid: med.ownerUid,
      medicationId: med.id,
      scheduledAtLocal: _scheduledAtLocal,
      confirmedAtLocal: DateTime.now(),
      status: 'skipped',
      snoozeCount: existing?.snoozeCount ?? 0,
      dosageAmountTaken: '',
      dosageUnitTaken: med.dosageUnit,
      note: '',
    );

    try {
      await _repo.upsertCompletion(
        completion: completion,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: userId,
      );
    } catch (e) {
      print('[MedicationAlertScreen] error guardando skip: $e');
    }

    await _rescheduleNext(med, userId);
    await _clearScreenFlag();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _rescheduleNext(MedicationModel med, String? userId) async {
    final next = _scheduler.nextOccurrenceLocal(med, DateTime.now());
    final updated = med.copyWith(nextScheduledAtLocal: next);
    try {
      await _repo.upsertMedication(
          medication: updated,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: userId);
      if (next != null) {
        await _scheduler.scheduleOccurrence(med: updated, whenLocal: next);
        print('[MedicationAlertScreen] próxima ocurrencia programada: ${next.toIso8601String()}');
      }
    } catch (e) {
      print('[MedicationAlertScreen] error reprogramando: $e');
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

    final cardColor = med.colorHex.isNotEmpty
        ? Color(int.tryParse(med.colorHex.replaceFirst('#', '0xFF')) ?? scheme.surface.value)
        : scheme.surface;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hora + botón mute
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (med.enableTts) const SizedBox(width: 40),
                      Expanded(
                        child: Center(
                          child: Text(
                            _timeText,
                            style: TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: onCard),
                          ),
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

                  // Nombre del medicamento
                  Center(
                    child: Text(
                      med.medicationName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: onCard),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Dosis
                  if (med.dosageAmount.isNotEmpty) ...[
                    Center(
                      child: Text(
                        '${med.dosageAmount} ${med.dosageUnit}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: onCard.withOpacity(0.85)),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Tipo de medicamento
                  if (med.medicationType.isNotEmpty)
                    Center(
                      child: Chip(
                        label: Text(med.medicationType,
                            style: TextStyle(color: onCard)),
                        backgroundColor: cardColor.withOpacity(0.7),
                        side: BorderSide(color: onCard.withOpacity(0.3)),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Instrucciones
                  if (med.instructions.isNotEmpty) ...[
                    _infoRow(
                        Icons.info_outline, 'Instrucciones', med.instructions, onCard),
                    const SizedBox(height: 8),
                  ],

                  // Prescrito por
                  if (med.prescribedBy.isNotEmpty) ...[
                    _infoRow(Icons.person_outline, 'Prescrito por',
                        med.prescribedBy, onCard),
                    const SizedBox(height: 8),
                  ],

                  // Propósito
                  if (med.purpose.isNotEmpty) ...[
                    _infoRow(
                        Icons.healing_outlined, 'Propósito', med.purpose, onCard),
                    const SizedBox(height: 8),
                  ],

                  // Notas
                  if (med.notes.isNotEmpty) ...[
                    _infoRow(
                        Icons.notes_outlined, 'Notas', med.notes, onCard),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Botones en columna, ancho completo
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _markTaken,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Tomé el medicamento'),
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
                      onPressed: _snooze,
                      icon: const Icon(Icons.alarm),
                      label: Text('Recordar en ${_med?.defaultSnoozeMinutes ?? 10} min'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
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

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color.withOpacity(0.7)),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: color.withOpacity(0.85)),
              children: [
                TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
