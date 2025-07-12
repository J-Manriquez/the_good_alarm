
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
  });

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
  };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
    id: json['id'] as int,
    time: DateTime.parse(json['time'] as String),
    title: json['title'] as String,
    message: json['message'] as String,
    isActive: json['isActive'] as bool? ?? true,
    repeatDays: json['repeatDays'] != null
        ? List<int>.from(json['repeatDays'])
        : [],
    isDaily: json['isDaily'] as bool? ?? false,
    isWeekly: json['isWeekly'] as bool? ?? false,
    isWeekend: json['isWeekend'] as bool? ?? false,
    snoozeCount: json['snoozeCount'] as int? ?? 0,
    maxSnoozes: json['maxSnoozes'] as int? ?? 3,
    snoozeDurationMinutes: json['snoozeDurationMinutes'] as int? ?? 5,
    requireGame: json['requireGame'] as bool? ?? false,
    gameConfig: json['gameConfig'] != null 
        ? GameConfig.fromJson(json['gameConfig']) 
        : null,
    syncToCloud: json['syncToCloud'] as bool? ?? true,
    activeOnlyIn: json['activeOnlyIn'] != null
        ? List<Map<String, dynamic>>.from(json['activeOnlyIn'])
        : null,
    maxVolumePercent: json['maxVolumePercent'] as int? ?? 100,
    volumeRampUpDurationSeconds: json['volumeRampUpDurationSeconds'] as int? ?? 30,
    tempVolumeReductionPercent: json['tempVolumeReductionPercent'] as int? ?? 30,
    tempVolumeReductionDurationSeconds: json['tempVolumeReductionDurationSeconds'] as int? ?? 60,
  );
  
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
    );
  }
}
