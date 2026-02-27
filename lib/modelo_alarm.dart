
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:the_good_alarm/games/modelo_juegos.dart';

class Alarm {
  final int id;
  final DateTime time;
  final String title;
  final String message;
  bool isActive;
  List<int> repeatDays;
  bool isDaily;
  bool isWeekly;
  bool isWeekend;
  int snoozeCount;
  int maxSnoozes;
  int snoozeDurationMinutes;
  bool requireGame;
  GameConfig? gameConfig;
  bool syncToCloud;
  List<Map<String, dynamic>>? activeOnlyIn;
  
  // Configuraciones de volumen
  int maxVolumePercent;
  int volumeRampUpDurationSeconds;
  int tempVolumeReductionPercent;
  int tempVolumeReductionDurationSeconds;
  DateTime? createdAt;
  DateTime? updatedAt;
  DateTime? deletedAt;
  int revision;
  Map<String, DateTime>? fieldUpdatedAt;
  Map<String, dynamic> extras;

  Alarm({
    required this.id,
    required this.time,
    required this.title,
    required this.message,
    this.isActive = true,
    this.repeatDays = const [],
    this.isDaily = false,
    this.isWeekly = false,
    this.isWeekend = false,
    this.snoozeCount = 0,
    this.maxSnoozes = 3,
    this.snoozeDurationMinutes = 5,
    this.requireGame = false,
    this.gameConfig,
    this.syncToCloud = true,
    this.activeOnlyIn,
    this.maxVolumePercent = 100,
    this.volumeRampUpDurationSeconds = 30,
    this.tempVolumeReductionPercent = 30,
    this.tempVolumeReductionDurationSeconds = 60,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  bool isRepeating() {
    return isDaily || isWeekly || isWeekend || repeatDays.isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'title': title,
    'message': message,
    'isActive': isActive,
    'repeatDays': repeatDays,
    'isDaily': isDaily,
    'isWeekly': isWeekly,
    'isWeekend': isWeekend,
    'snoozeCount': snoozeCount,
    'maxSnoozes': maxSnoozes,
    'snoozeDurationMinutes': snoozeDurationMinutes,
    'requireGame': requireGame,
    'gameConfig': gameConfig?.toJson(),
    'syncToCloud': syncToCloud,
    'activeOnlyIn': activeOnlyIn,
    'maxVolumePercent': maxVolumePercent,
    'volumeRampUpDurationSeconds': volumeRampUpDurationSeconds,
    'tempVolumeReductionPercent': tempVolumeReductionPercent,
    'tempVolumeReductionDurationSeconds': tempVolumeReductionDurationSeconds,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'revision': revision,
    'fieldUpdatedAt': fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
    ...extras,
  };

  factory Alarm.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'time',
      'title',
      'message',
      'isActive',
      'repeatDays',
      'isDaily',
      'isWeekly',
      'isWeekend',
      'snoozeCount',
      'maxSnoozes',
      'snoozeDurationMinutes',
      'requireGame',
      'gameConfig',
      'syncToCloud',
      'activeOnlyIn',
      'maxVolumePercent',
      'volumeRampUpDurationSeconds',
      'tempVolumeReductionPercent',
      'tempVolumeReductionDurationSeconds',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }

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
        if (parsed != null) {
          result[k] = parsed;
        }
      });
      return result.isEmpty ? null : result;
    }

    return Alarm(
      id: (json['id'] as num).toInt(),
      time: DateTime.parse(json['time'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      isActive: json['isActive'] as bool? ?? true,
      repeatDays: json['repeatDays'] != null ? List<int>.from(json['repeatDays']) : [],
      isDaily: json['isDaily'] as bool? ?? false,
      isWeekly: json['isWeekly'] as bool? ?? false,
      isWeekend: json['isWeekend'] as bool? ?? false,
      snoozeCount: (json['snoozeCount'] as num?)?.toInt() ?? 0,
      maxSnoozes: (json['maxSnoozes'] as num?)?.toInt() ?? 3,
      snoozeDurationMinutes: (json['snoozeDurationMinutes'] as num?)?.toInt() ?? 5,
      requireGame: json['requireGame'] as bool? ?? false,
      gameConfig: json['gameConfig'] is Map ? GameConfig.fromJson(Map<String, dynamic>.from(json['gameConfig'])) : null,
      syncToCloud: json['syncToCloud'] as bool? ?? true,
      activeOnlyIn: json['activeOnlyIn'] != null ? List<Map<String, dynamic>>.from(json['activeOnlyIn']) : null,
      maxVolumePercent: (json['maxVolumePercent'] as num?)?.toInt() ?? 100,
      volumeRampUpDurationSeconds: (json['volumeRampUpDurationSeconds'] as num?)?.toInt() ?? 30,
      tempVolumeReductionPercent: (json['tempVolumeReductionPercent'] as num?)?.toInt() ?? 30,
      tempVolumeReductionDurationSeconds: (json['tempVolumeReductionDurationSeconds'] as num?)?.toInt() ?? 60,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }
  
  // Crear una copia de la alarma con propiedades modificadas
  Alarm copyWith({
    int? id,
    DateTime? time,
    String? title,
    String? message,
    bool? isActive,
    List<int>? repeatDays,
    bool? isDaily,
    bool? isWeekly,
    bool? isWeekend,
    int? snoozeCount,
    int? maxSnoozes,
    int? snoozeDurationMinutes,
    bool? requireGame,
    GameConfig? gameConfig,
    bool? syncToCloud,
    List<Map<String, dynamic>>? activeOnlyIn,
    int? maxVolumePercent,
    int? volumeRampUpDurationSeconds,
    int? tempVolumeReductionPercent,
    int? tempVolumeReductionDurationSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return Alarm(
      id: id ?? this.id,
      time: time ?? this.time,
      title: title ?? this.title,
      message: message ?? this.message,
      isActive: isActive ?? this.isActive,
      repeatDays: repeatDays ?? List<int>.from(this.repeatDays),
      isDaily: isDaily ?? this.isDaily,
      isWeekly: isWeekly ?? this.isWeekly,
      isWeekend: isWeekend ?? this.isWeekend,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      maxSnoozes: maxSnoozes ?? this.maxSnoozes,
      snoozeDurationMinutes: snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      requireGame: requireGame ?? this.requireGame,
      gameConfig: gameConfig ?? this.gameConfig,
      syncToCloud: syncToCloud ?? this.syncToCloud,
      activeOnlyIn: activeOnlyIn ?? this.activeOnlyIn,
      maxVolumePercent: maxVolumePercent ?? this.maxVolumePercent,
      volumeRampUpDurationSeconds: volumeRampUpDurationSeconds ?? this.volumeRampUpDurationSeconds,
      tempVolumeReductionPercent: tempVolumeReductionPercent ?? this.tempVolumeReductionPercent,
      tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds ?? this.tempVolumeReductionDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ?? (this.fieldUpdatedAt == null ? null : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}
