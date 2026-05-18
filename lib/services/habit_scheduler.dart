import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit_models.dart';

class HabitScheduler {
  static const MethodChannel _platform = MethodChannel('com.andodevs.the_good_alarm/alarm');

  DateTime? nextOccurrenceLocal(HabitModel habit, DateTime nowLocal) {
    if (!habit.isActive) return null;
    if (habit.deletedAt != null) return null;
    if (habit.times.isEmpty) return null;

    final allowedDays = habit.repeatMode == 'customDays'
        ? habit.weekdays.where((d) => d >= 1 && d <= 7).toSet()
        : <int>{1, 2, 3, 4, 5, 6, 7};
    if (allowedDays.isEmpty) return null;

    final times = List<TimeOfDay>.from(habit.times)
      ..sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));

    final baseDay = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    for (var dayOffset = 0; dayOffset <= 14; dayOffset++) {
      final day = baseDay.add(Duration(days: dayOffset));
      if (!allowedDays.contains(day.weekday)) continue;

      for (final t in times) {
        final candidate = DateTime(day.year, day.month, day.day, t.hour, t.minute);
        if (candidate.isAfter(nowLocal)) return candidate;
      }
    }
    return null;
  }

  String occurrenceKeyFor(String habitId, DateTime whenLocal) {
    final dateKey =
        '${whenLocal.year.toString().padLeft(4, '0')}${whenLocal.month.toString().padLeft(2, '0')}${whenLocal.day.toString().padLeft(2, '0')}';
    final timeKey =
        '${whenLocal.hour.toString().padLeft(2, '0')}${whenLocal.minute.toString().padLeft(2, '0')}';
    return '$habitId|$dateKey|$timeKey';
  }

  Future<void> scheduleOccurrence({
    required HabitModel habit,
    required DateTime whenLocal,
  }) async {
    final key = occurrenceKeyFor(habit.id, whenLocal);
    await _platform.invokeMethod('setHabit', {
      'habitId': habit.id,
      'occurrenceKey': key,
      'timeInMillis': whenLocal.millisecondsSinceEpoch,
      'title': habit.title,
      'message': habit.description,
      'screenRoute': '/habit',
    });
  }

  Future<void> cancelOccurrence({
    required String occurrenceKey,
  }) async {
    await _platform.invokeMethod('cancelHabit', {
      'occurrenceKey': occurrenceKey,
    });
  }

  Future<void> clearScreenFlag({
    required String occurrenceKey,
  }) async {
    await _platform.invokeMethod('clearHabitScreenFlag', {
      'occurrenceKey': occurrenceKey,
    });
  }
}

