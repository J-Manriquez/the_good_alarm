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

Map<String, dynamic> _timeOfDayToJson(TimeOfDay t) => {'hour': t.hour, 'minute': t.minute};

class HabitModel {
  final String id;
  final String ownerUid;
  final String title;
  final String description;
  final bool isActive;
  final bool syncToCloud;

  final String repeatMode;
  final List<int> weekdays;
  final List<TimeOfDay> times;

  final bool requireConfirmation;
  final int defaultSnoozeMinutes;

  final int? cardBackgroundColorArgb;
  final int? titleTextColorArgb;
  final int? descriptionTextColorArgb;
  final int? timeTextColorArgb;

  final String alertScreenType;
  final String alertLayoutId;

  final DateTime? nextScheduledAtLocal;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  HabitModel({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.description,
    this.isActive = true,
    this.syncToCloud = true,
    this.repeatMode = 'daily',
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.times = const [TimeOfDay(hour: 8, minute: 0)],
    this.requireConfirmation = true,
    this.defaultSnoozeMinutes = 10,
    this.cardBackgroundColorArgb,
    this.titleTextColorArgb,
    this.descriptionTextColorArgb,
    this.timeTextColorArgb,
    this.alertScreenType = 'fullscreen',
    this.alertLayoutId = 'classic',
    this.nextScheduledAtLocal,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'title': title,
        'description': description,
        'isActive': isActive,
        'syncToCloud': syncToCloud,
        'repeatMode': repeatMode,
        'weekdays': weekdays,
        'times': times.map(_timeOfDayToJson).toList(),
        'requireConfirmation': requireConfirmation,
        'defaultSnoozeMinutes': defaultSnoozeMinutes,
        'cardBackgroundColorArgb': cardBackgroundColorArgb,
        'titleTextColorArgb': titleTextColorArgb,
        'descriptionTextColorArgb': descriptionTextColorArgb,
        'timeTextColorArgb': timeTextColorArgb,
        'alertScreenType': alertScreenType,
        'alertLayoutId': alertLayoutId,
        'nextScheduledAtLocal': nextScheduledAtLocal?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt': fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory HabitModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'ownerUid',
      'title',
      'description',
      'isActive',
      'syncToCloud',
      'repeatMode',
      'weekdays',
      'times',
      'requireConfirmation',
      'defaultSnoozeMinutes',
      'cardBackgroundColorArgb',
      'titleTextColorArgb',
      'descriptionTextColorArgb',
      'timeTextColorArgb',
      'alertScreenType',
      'alertLayoutId',
      'nextScheduledAtLocal',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }

    final rawTimes = json['times'];
    final times = <TimeOfDay>[];
    if (rawTimes is List) {
      for (final t in rawTimes) {
        times.add(_timeOfDayFromJson(t));
      }
    }
    if (times.isEmpty) {
      times.add(const TimeOfDay(hour: 8, minute: 0));
    }

    final rawWeekdays = json['weekdays'];
    final weekdays = <int>[];
    if (rawWeekdays is List) {
      for (final d in rawWeekdays) {
        final v = (d as num?)?.toInt();
        if (v != null && v >= 1 && v <= 7) weekdays.add(v);
      }
    }
    if (weekdays.isEmpty) {
      weekdays.addAll(const [1, 2, 3, 4, 5, 6, 7]);
    }

    return HabitModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      syncToCloud: json['syncToCloud'] as bool? ?? true,
      repeatMode: json['repeatMode'] as String? ?? 'daily',
      weekdays: weekdays,
      times: times,
      requireConfirmation: json['requireConfirmation'] as bool? ?? true,
      defaultSnoozeMinutes: (json['defaultSnoozeMinutes'] as num?)?.toInt() ?? 10,
      cardBackgroundColorArgb: (json['cardBackgroundColorArgb'] as num?)?.toInt(),
      titleTextColorArgb: (json['titleTextColorArgb'] as num?)?.toInt(),
      descriptionTextColorArgb: (json['descriptionTextColorArgb'] as num?)?.toInt(),
      timeTextColorArgb: (json['timeTextColorArgb'] as num?)?.toInt(),
      alertScreenType: json['alertScreenType'] as String? ?? 'fullscreen',
      alertLayoutId: json['alertLayoutId'] as String? ?? 'classic',
      nextScheduledAtLocal: _parseDate(json['nextScheduledAtLocal']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  HabitModel copyWith({
    String? id,
    String? ownerUid,
    String? title,
    String? description,
    bool? isActive,
    bool? syncToCloud,
    String? repeatMode,
    List<int>? weekdays,
    List<TimeOfDay>? times,
    bool? requireConfirmation,
    int? defaultSnoozeMinutes,
    int? cardBackgroundColorArgb,
    int? titleTextColorArgb,
    int? descriptionTextColorArgb,
    int? timeTextColorArgb,
    String? alertScreenType,
    String? alertLayoutId,
    DateTime? nextScheduledAtLocal,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return HabitModel(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      title: title ?? this.title,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      syncToCloud: syncToCloud ?? this.syncToCloud,
      repeatMode: repeatMode ?? this.repeatMode,
      weekdays: weekdays ?? List<int>.from(this.weekdays),
      times: times ?? List<TimeOfDay>.from(this.times),
      requireConfirmation: requireConfirmation ?? this.requireConfirmation,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
      cardBackgroundColorArgb: cardBackgroundColorArgb ?? this.cardBackgroundColorArgb,
      titleTextColorArgb: titleTextColorArgb ?? this.titleTextColorArgb,
      descriptionTextColorArgb: descriptionTextColorArgb ?? this.descriptionTextColorArgb,
      timeTextColorArgb: timeTextColorArgb ?? this.timeTextColorArgb,
      alertScreenType: alertScreenType ?? this.alertScreenType,
      alertLayoutId: alertLayoutId ?? this.alertLayoutId,
      nextScheduledAtLocal: nextScheduledAtLocal ?? this.nextScheduledAtLocal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ??
          (this.fieldUpdatedAt == null ? null : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

class HabitCompletionModel {
  final String id;
  final String ownerUid;
  final String habitId;
  final DateTime scheduledAtLocal;
  final DateTime? completedAtLocal;
  final String status;
  final String note;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  HabitCompletionModel({
    required this.id,
    required this.ownerUid,
    required this.habitId,
    required this.scheduledAtLocal,
    this.completedAtLocal,
    required this.status,
    this.note = '',
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'habitId': habitId,
        'scheduledAtLocal': scheduledAtLocal.toIso8601String(),
        'completedAtLocal': completedAtLocal?.toIso8601String(),
        'status': status,
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt': fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory HabitCompletionModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'ownerUid',
      'habitId',
      'scheduledAtLocal',
      'completedAtLocal',
      'status',
      'note',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }

    return HabitCompletionModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      habitId: json['habitId'] as String? ?? '',
      scheduledAtLocal: _parseDate(json['scheduledAtLocal']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      completedAtLocal: _parseDate(json['completedAtLocal']),
      status: json['status'] as String? ?? 'done',
      note: json['note'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  HabitCompletionModel copyWith({
    String? id,
    String? ownerUid,
    String? habitId,
    DateTime? scheduledAtLocal,
    DateTime? completedAtLocal,
    String? status,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return HabitCompletionModel(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      habitId: habitId ?? this.habitId,
      scheduledAtLocal: scheduledAtLocal ?? this.scheduledAtLocal,
      completedAtLocal: completedAtLocal ?? this.completedAtLocal,
      status: status ?? this.status,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ??
          (this.fieldUpdatedAt == null ? null : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

