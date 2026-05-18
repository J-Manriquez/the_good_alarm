import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/medication_models.dart';

class MedicationScheduler {
  static const MethodChannel _platform =
      MethodChannel('com.andodevs.the_good_alarm/alarm');

  /// Calcula la próxima ocurrencia del medicamento a partir de [nowLocal].
  DateTime? nextOccurrenceLocal(MedicationModel med, DateTime nowLocal) {
    if (!med.isActive) return null;
    if (med.deletedAt != null) return null;
    if (med.times.isEmpty) return null;

    final allowedDays = med.repeatMode == 'customDays'
        ? med.weekdays.where((d) => d >= 1 && d <= 7).toSet()
        : <int>{1, 2, 3, 4, 5, 6, 7};
    if (allowedDays.isEmpty) return null;

    final times = List<TimeOfDay>.from(med.times)
      ..sort((a, b) => a.hour != b.hour
          ? a.hour.compareTo(b.hour)
          : a.minute.compareTo(b.minute));

    final baseDay = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    for (var dayOffset = 0; dayOffset <= 14; dayOffset++) {
      final day = baseDay.add(Duration(days: dayOffset));
      if (!allowedDays.contains(day.weekday)) continue;

      for (final t in times) {
        final candidate =
            DateTime(day.year, day.month, day.day, t.hour, t.minute);
        if (candidate.isAfter(nowLocal)) return candidate;
      }
    }
    return null;
  }

  /// Clave de ocurrencia única: "med|{medId}|{yyyyMMdd}|{HHmm}"
  String occurrenceKeyFor(String medId, DateTime whenLocal) {
    final dateKey =
        '${whenLocal.year.toString().padLeft(4, '0')}${whenLocal.month.toString().padLeft(2, '0')}${whenLocal.day.toString().padLeft(2, '0')}';
    final timeKey =
        '${whenLocal.hour.toString().padLeft(2, '0')}${whenLocal.minute.toString().padLeft(2, '0')}';
    return 'med|$medId|$dateKey|$timeKey';
  }

  /// Programa el recordatorio principal del medicamento.
  Future<void> scheduleOccurrence({
    required MedicationModel med,
    required DateTime whenLocal,
  }) async {
    final key = occurrenceKeyFor(med.id, whenLocal);
    print('[MedicationScheduler] scheduleOccurrence key=$key time=${whenLocal.toIso8601String()}');
    await _platform.invokeMethod('setMedication', {
      'medicationId': med.id,
      'occurrenceKey': key,
      'timeInMillis': whenLocal.millisecondsSinceEpoch,
      'title': med.medicationName,
      'message': med.instructions.isEmpty ? '' : med.instructions,
      'dosageAmount': med.dosageAmount,
      'dosageUnit': med.dosageUnit,
      'screenRoute': '/medication',
    });
  }

  /// Programa el recordatorio de confirmación con la clave y hora exactas.
  Future<void> scheduleConfirmation({
    required MedicationModel med,
    required String occurrenceKey,
    required DateTime confirmAt,
  }) async {
    print('[MedicationScheduler] scheduleConfirmation key=$occurrenceKey confirmAt=${confirmAt.toIso8601String()}');
    await _platform.invokeMethod('setMedicationConfirmation', {
      'medicationId': med.id,
      'occurrenceKey': occurrenceKey,
      'timeInMillis': confirmAt.millisecondsSinceEpoch,
      'title': med.medicationName,
      'screenRoute': '/medication_confirm',
    });
  }

  /// Cancela el recordatorio principal.
  Future<void> cancelOccurrence({required String occurrenceKey}) async {
    print('[MedicationScheduler] cancelOccurrence key=$occurrenceKey');
    await _platform.invokeMethod('cancelMedication', {
      'occurrenceKey': occurrenceKey,
    });
  }

  /// Cancela el recordatorio de confirmación (solo llamar desde MedicationConfirmScreen).
  Future<void> cancelConfirmation({required String occurrenceKey}) async {
    print('[MedicationScheduler] cancelConfirmation key=$occurrenceKey');
    await _platform.invokeMethod('cancelMedicationConfirmation', {
      'occurrenceKey': occurrenceKey,
    });
  }

  /// Descarta la notificación visible para la ocurrencia dada.
  Future<void> dismissNotification({
    required String occurrenceKey,
    bool isConfirmation = false,
  }) async {
    try {
      await _platform.invokeMethod('dismissMedicationNotification', {
        'occurrenceKey': occurrenceKey,
        'isConfirmation': isConfirmation,
      });
      print('[MedicationScheduler] dismissNotification key=$occurrenceKey isConfirmation=$isConfirmation');
    } catch (e) {
      print('[MedicationScheduler] dismissNotification error: $e');
    }
  }

  /// Limpia el flag de pantalla para que pueda mostrarse nuevamente.
  Future<void> clearScreenFlag({required String occurrenceKey}) async {
    await _platform.invokeMethod('clearMedicationScreenFlag', {
      'occurrenceKey': occurrenceKey,
    });
  }
}
