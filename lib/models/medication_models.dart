import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

Map<String, DateTime>? _parseFieldUpdatedAt(dynamic value) {
  if (value == null) return null;
  if (value is! Map) return null;
  final result = <String, DateTime>{};
  value.forEach((k, v) {
    if (k is! String) return;
    final parsed = _parseDate(v);
    if (parsed != null) result[k] = parsed;
  });
  return result.isEmpty ? null : result;
}

TimeOfDay _timeOfDayFromJson(dynamic value) {
  if (value is Map) {
    final hour = (value['hour'] as num?)?.toInt() ?? 0;
    final minute = (value['minute'] as num?)?.toInt() ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }
  if (value is String) {
    final parts = value.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
  }
  return const TimeOfDay(hour: 8, minute: 0);
}

Map<String, dynamic> _timeOfDayToJson(TimeOfDay t) =>
    {'hour': t.hour, 'minute': t.minute};

class MedicationModel {
  final String id;
  final String ownerUid;
  final String medicationName;
  final String dosageAmount;
  final String dosageUnit;
  final String medicationType;
  final String instructions;
  final String prescribedBy;
  final String purpose;
  final String notes;
  final String colorHex;
  final bool isActive;
  final bool syncToCloud;
  final String repeatMode;
  final List<int> weekdays;
  final List<TimeOfDay> times;
  final bool requireConfirmation;
  final int confirmationDelayMinutes;
  final int defaultSnoozeMinutes;
  final bool enableTts;
  final String ttsLanguage;
  final int ttsVolume; // 0-100, porcentaje del volúmen máximo de STREAM_MUSIC
  final DateTime? nextScheduledAtLocal;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  MedicationModel({
    required this.id,
    required this.ownerUid,
    required this.medicationName,
    this.dosageAmount = '',
    this.dosageUnit = 'mg',
    this.medicationType = 'Pastilla/Comprimido',
    this.instructions = '',
    this.prescribedBy = '',
    this.purpose = '',
    this.notes = '',
    this.colorHex = '#2196F3',
    this.isActive = true,
    this.syncToCloud = true,
    this.repeatMode = 'daily',
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.times = const [TimeOfDay(hour: 8, minute: 0)],
    this.requireConfirmation = true,
    this.confirmationDelayMinutes = 15,
    this.defaultSnoozeMinutes = 10,
    this.enableTts = true,
    this.ttsLanguage = 'es-MX',
    this.ttsVolume = 80,
    this.nextScheduledAtLocal,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  String buildTtsReminderText({
    int doseIndex = 0,
    String? lastDoseStatus,
    DateTime? lastDoseAt,
  }) {
    final name = medicationName.trim();
    final amount = dosageAmount.trim();
    final unit = dosageUnit.trim();
    final instr = instructions.trim();
    final noteText = notes.trim();

    final buffer = StringBuffer();

    // Indicar número de dosis del día si hay más de una
    final totalDoses = times.length;
    if (totalDoses > 1) {
      const ordinals = [
        'primera', 'segunda', 'tercera', 'cuarta',
        'quinta', 'sexta', 'séptima', 'octava'
      ];
      final ordinal = doseIndex < ordinals.length
          ? ordinals[doseIndex]
          : '${doseIndex + 1}ª';
      buffer.write('Esta es la $ordinal dosis del día. ');
    }

    buffer.write('Es hora de tomar tu medicamento. $name');
    if (amount.isNotEmpty) {
      buffer.write(': $amount $unit');
    }
    buffer.write('.');
    if (instr.isNotEmpty) {
      buffer.write(' $instr.');
    }
    if (noteText.isNotEmpty) {
      buffer.write(' Nota: $noteText.');
    }

    // Agregar info de la última dosis
    if (lastDoseStatus != null) {
      if (lastDoseStatus == 'taken') {
        buffer.write(' La última dosis fue tomada correctamente');
      } else if (lastDoseStatus == 'skipped') {
        buffer.write(' La última dosis fue omitida');
      } else if (lastDoseStatus == 'missed') {
        buffer.write(' La última dosis no fue tomada');
      }
      if (lastDoseAt != null) {
        final diff = DateTime.now().difference(lastDoseAt);
        if (diff.inHours < 24) {
          buffer.write(' hace ${diff.inHours} horas');
        } else {
          buffer.write(' ayer');
        }
      }
      buffer.write('.');
    }

    return buffer.toString();
  }

  String buildTtsConfirmationText({String? scheduledTimeText}) {
    final name = medicationName.trim();
    final amount = dosageAmount.trim();
    final unit = dosageUnit.trim();
    final buffer = StringBuffer();
    if (amount.isNotEmpty) {
      buffer.write('¿Ya tomaste $name? Recuerda que debes tomar $amount $unit. Por favor confirma.');
    } else {
      buffer.write('¿Ya tomaste $name? Por favor confirma.');
    }
    if (scheduledTimeText != null && scheduledTimeText.isNotEmpty) {
      buffer.write(' La dosis estaba programada para las $scheduledTimeText.');
    }
    return buffer.toString();
  }

  String buildTtsAlreadyConfirmedText(String hora, {String? scheduledTimeText}) {
    final name = medicationName.trim();
    final buffer = StringBuffer();
    buffer.write('Ya confirmaste que tomaste $name a las $hora. ¿Es correcto?');
    if (scheduledTimeText != null && scheduledTimeText.isNotEmpty) {
      buffer.write(' La dosis estaba programada para las $scheduledTimeText.');
    }
    return buffer.toString();
  }

  bool isRepeating() =>
      repeatMode == 'daily' ||
      repeatMode == 'customDays' ||
      weekdays.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'medicationName': medicationName,
        'dosageAmount': dosageAmount,
        'dosageUnit': dosageUnit,
        'medicationType': medicationType,
        'instructions': instructions,
        'prescribedBy': prescribedBy,
        'purpose': purpose,
        'notes': notes,
        'colorHex': colorHex,
        'isActive': isActive,
        'syncToCloud': syncToCloud,
        'repeatMode': repeatMode,
        'weekdays': weekdays,
        'times': times.map(_timeOfDayToJson).toList(),
        'requireConfirmation': requireConfirmation,
        'confirmationDelayMinutes': confirmationDelayMinutes,
        'defaultSnoozeMinutes': defaultSnoozeMinutes,
        'enableTts': enableTts,
        'ttsLanguage': ttsLanguage,
        'ttsVolume': ttsVolume,
        'nextScheduledAtLocal': nextScheduledAtLocal?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory MedicationModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id', 'ownerUid', 'medicationName', 'dosageAmount', 'dosageUnit',
      'medicationType', 'instructions', 'prescribedBy', 'purpose', 'notes',
      'colorHex', 'isActive', 'syncToCloud', 'repeatMode', 'weekdays', 'times',
      'requireConfirmation', 'confirmationDelayMinutes', 'defaultSnoozeMinutes',
      'enableTts', 'ttsLanguage', 'ttsVolume', 'nextScheduledAtLocal',
      'createdAt', 'updatedAt', 'deletedAt', 'revision', 'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }

    List<int> weekdays = [];
    final rawWeekdays = json['weekdays'];
    if (rawWeekdays is List) {
      weekdays = rawWeekdays.whereType<num>().map((e) => e.toInt()).toList();
    }
    if (weekdays.isEmpty && json['repeatMode'] != 'customDays') {
      weekdays.addAll(const [1, 2, 3, 4, 5, 6, 7]);
    }

    List<TimeOfDay> times = [];
    final rawTimes = json['times'];
    if (rawTimes is List) {
      times = rawTimes.map((e) => _timeOfDayFromJson(e)).toList();
    }
    if (times.isEmpty) times.add(const TimeOfDay(hour: 8, minute: 0));

    return MedicationModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      medicationName: json['medicationName'] as String? ?? '',
      dosageAmount: json['dosageAmount'] as String? ?? '',
      dosageUnit: json['dosageUnit'] as String? ?? 'mg',
      medicationType:
          json['medicationType'] as String? ?? 'Pastilla/Comprimido',
      instructions: json['instructions'] as String? ?? '',
      prescribedBy: json['prescribedBy'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? '#2196F3',
      isActive: json['isActive'] as bool? ?? true,
      syncToCloud: json['syncToCloud'] as bool? ?? true,
      repeatMode: json['repeatMode'] as String? ?? 'daily',
      weekdays: weekdays,
      times: times,
      requireConfirmation: json['requireConfirmation'] as bool? ?? true,
      confirmationDelayMinutes:
          (json['confirmationDelayMinutes'] as num?)?.toInt() ?? 15,
      defaultSnoozeMinutes:
          (json['defaultSnoozeMinutes'] as num?)?.toInt() ?? 10,
      enableTts: json['enableTts'] as bool? ?? true,
      ttsLanguage: json['ttsLanguage'] as String? ?? 'es-MX',
      ttsVolume: (json['ttsVolume'] as num?)?.toInt() ?? 80,
      nextScheduledAtLocal: _parseDate(json['nextScheduledAtLocal']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  MedicationModel copyWith({
    String? id,
    String? ownerUid,
    String? medicationName,
    String? dosageAmount,
    String? dosageUnit,
    String? medicationType,
    String? instructions,
    String? prescribedBy,
    String? purpose,
    String? notes,
    String? colorHex,
    bool? isActive,
    bool? syncToCloud,
    String? repeatMode,
    List<int>? weekdays,
    List<TimeOfDay>? times,
    bool? requireConfirmation,
    int? confirmationDelayMinutes,
    int? defaultSnoozeMinutes,
    bool? enableTts,
    String? ttsLanguage,
    int? ttsVolume,
    DateTime? nextScheduledAtLocal,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return MedicationModel(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      medicationName: medicationName ?? this.medicationName,
      dosageAmount: dosageAmount ?? this.dosageAmount,
      dosageUnit: dosageUnit ?? this.dosageUnit,
      medicationType: medicationType ?? this.medicationType,
      instructions: instructions ?? this.instructions,
      prescribedBy: prescribedBy ?? this.prescribedBy,
      purpose: purpose ?? this.purpose,
      notes: notes ?? this.notes,
      colorHex: colorHex ?? this.colorHex,
      isActive: isActive ?? this.isActive,
      syncToCloud: syncToCloud ?? this.syncToCloud,
      repeatMode: repeatMode ?? this.repeatMode,
      weekdays: weekdays ?? List<int>.from(this.weekdays),
      times: times ?? List<TimeOfDay>.from(this.times),
      requireConfirmation: requireConfirmation ?? this.requireConfirmation,
      confirmationDelayMinutes:
          confirmationDelayMinutes ?? this.confirmationDelayMinutes,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
      enableTts: enableTts ?? this.enableTts,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsVolume: ttsVolume ?? this.ttsVolume,
      nextScheduledAtLocal: nextScheduledAtLocal ?? this.nextScheduledAtLocal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ?? this.fieldUpdatedAt,
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MedicationCompletionModel
// ─────────────────────────────────────────────────────────

class MedicationCompletionModel {
  final String id;
  final String ownerUid;
  final String medicationId;
  final DateTime scheduledAtLocal;
  final DateTime? confirmedAtLocal;
  final String status; // "taken" | "skipped" | "missed" | "pending"
  final String note;
  final int snoozeCount;
  final String dosageAmountTaken;
  final String dosageUnitTaken;
  final bool confirmedViaReminder;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;

  MedicationCompletionModel({
    required this.id,
    required this.ownerUid,
    required this.medicationId,
    required this.scheduledAtLocal,
    this.confirmedAtLocal,
    this.status = 'pending',
    this.note = '',
    this.snoozeCount = 0,
    this.dosageAmountTaken = '',
    this.dosageUnitTaken = '',
    this.confirmedViaReminder = false,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'medicationId': medicationId,
        'scheduledAtLocal': scheduledAtLocal.toIso8601String(),
        'confirmedAtLocal': confirmedAtLocal?.toIso8601String(),
        'status': status,
        'note': note,
        'snoozeCount': snoozeCount,
        'dosageAmountTaken': dosageAmountTaken,
        'dosageUnitTaken': dosageUnitTaken,
        'confirmedViaReminder': confirmedViaReminder,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  factory MedicationCompletionModel.fromJson(Map<String, dynamic> json) {
    return MedicationCompletionModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      medicationId: json['medicationId'] as String? ?? '',
      scheduledAtLocal:
          _parseDate(json['scheduledAtLocal']) ?? DateTime.now(),
      confirmedAtLocal: _parseDate(json['confirmedAtLocal']),
      status: json['status'] as String? ?? 'pending',
      note: json['note'] as String? ?? '',
      snoozeCount: (json['snoozeCount'] as num?)?.toInt() ?? 0,
      dosageAmountTaken: json['dosageAmountTaken'] as String? ?? '',
      dosageUnitTaken: json['dosageUnitTaken'] as String? ?? '',
      confirmedViaReminder: json['confirmedViaReminder'] as bool? ?? false,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
    );
  }

  MedicationCompletionModel copyWith({
    String? id,
    String? ownerUid,
    String? medicationId,
    DateTime? scheduledAtLocal,
    DateTime? confirmedAtLocal,
    String? status,
    String? note,
    int? snoozeCount,
    String? dosageAmountTaken,
    String? dosageUnitTaken,
    bool? confirmedViaReminder,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
  }) {
    return MedicationCompletionModel(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      medicationId: medicationId ?? this.medicationId,
      scheduledAtLocal: scheduledAtLocal ?? this.scheduledAtLocal,
      confirmedAtLocal: confirmedAtLocal ?? this.confirmedAtLocal,
      status: status ?? this.status,
      note: note ?? this.note,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      dosageAmountTaken: dosageAmountTaken ?? this.dosageAmountTaken,
      dosageUnitTaken: dosageUnitTaken ?? this.dosageUnitTaken,
      confirmedViaReminder: confirmedViaReminder ?? this.confirmedViaReminder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ?? this.fieldUpdatedAt,
    );
  }
}
