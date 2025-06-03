// Modelo para la alarma con soporte para repetición
class Alarm {
  final int id;
  final DateTime time;
  final String title;
  final String message;
  bool isActive; // Para saber si la alarma está activa o ya sonó
  List<int> repeatDays; // Días de repetición (1-7 para lunes-domingo)
  bool isDaily;
  bool isWeekly;
  bool isWeekend;
  int snoozeCount;
  int maxSnoozes;
  int snoozeDurationMinutes; // NUEVA PROPIEDAD

  Alarm({
    required this.id,
    required this.time,
    required this.title,
    required this.message,
    this.isActive = true, // Por defecto, la alarma está activa al crearse
    this.repeatDays = const [],
    this.isDaily = false,
    this.isWeekly = false,
    this.isWeekend = false,
    this.snoozeCount = 0,
    this.maxSnoozes = 3,
    this.snoozeDurationMinutes = 5, // VALOR POR DEFECTO
  });

  // Getter para determinar si la alarma es repetitiva
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
    'snoozeDurationMinutes': snoozeDurationMinutes, // AGREGAR
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
    snoozeDurationMinutes:
        json['snoozeDurationMinutes'] as int? ?? 5, // AGREGAR
  );
}