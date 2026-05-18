import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_models.dart';
import '../settings_screen.dart';
import 'calendar_repository.dart';

class CalendarAlarmScheduler {
  static const MethodChannel _platform = MethodChannel('com.andodevs.the_good_alarm/alarm');
  static const String _prefsKey = 'calendarAlarms';

  final CalendarRepository _repo;

  CalendarAlarmScheduler({CalendarRepository? repo}) : _repo = repo ?? CalendarRepository();

  Future<void> rescheduleAllForUser({
    required String userId,
    required bool cloudSyncEnabled,
    int futureDays = 30,
    int maxScheduled = 80,
  }) async {
    if (cloudSyncEnabled) {
      await _repo.reconcile(userId: userId);
    }

    final nowLocal = DateTime.now();
    final windowStartUtc = nowLocal.toUtc();
    final windowEndUtc = nowLocal.add(Duration(days: futureDays)).toUtc();

    final calendars = await _repo.loadLocalCalendars();
    final desired = <_CalendarAlarmOccurrence>[];

    for (final calendar in calendars) {
      final events = await _repo.loadLocalEventsForCalendar(calendar.id);
      final eventsById = <String, CalendarEvent>{
        for (final e in events) e.id: e,
      };

      final occurrences = await _repo.loadLocalOccurrencesForCalendarInWindow(
        calendarId: calendar.id,
        windowStart: windowStartUtc,
        windowEnd: windowEndUtc,
      );

      final overridesByKey = <String, CalendarEventOverride>{};
      for (final e in events) {
        if (e.recurrenceKind == 'none') continue;
        final ovs = await _repo.loadLocalOverridesForEvent(e.id);
        for (final ov in ovs) {
          overridesByKey['${ov.eventId}:${ov.instanceStartMillisUtc}'] = ov;
        }
      }

      for (final e in events) {
        if (e.deletedAt != null) continue;
        if (e.extras['deleted'] == true) continue;
        if (e.extras['isTemplate'] == true) continue;
        if (e.recurrenceKind != 'none') continue;

        final title = e.title;
        final message = (e.description ?? '').trim();
        final kind = (e.extras['kind'] as String?) ?? 'event';
        final completed = (e.extras['completed'] as bool?) ?? false;
        if (kind == 'task' && completed) continue;

        final alarms = _parseAlarms(e.extras['alarms']);
        if (alarms.isEmpty) continue;

        final dayLocal = _eventDayLocal(e);
        if (dayLocal == null) continue;

        final instanceStartMillisUtc = _instanceStartMillisUtcForSingleEvent(e, dayLocal);
        for (final t in alarms) {
          final whenLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, t.hour, t.minute);
          if (!whenLocal.isAfter(nowLocal)) continue;
          if (whenLocal.isAfter(nowLocal.add(Duration(days: futureDays)))) continue;
          desired.add(_CalendarAlarmOccurrence(
            occurrenceKey: _occurrenceKey(
              calendarId: calendar.id,
              eventId: e.id,
              instanceStartMillisUtc: instanceStartMillisUtc,
              hour: t.hour,
              minute: t.minute,
            ),
            timeInMillis: whenLocal.millisecondsSinceEpoch,
            title: title,
            message: message,
            hour: t.hour,
            minute: t.minute,
          ));
        }
      }

      for (final occ in occurrences) {
        final base = eventsById[occ.eventId];
        if (base == null) continue;
        if (base.deletedAt != null) continue;
        if (base.extras['deleted'] == true) continue;
        if (base.extras['isTemplate'] == true) continue;

        final ov = overridesByKey['${occ.eventId}:${occ.instanceStartAt.millisecondsSinceEpoch}'];
        if (ov != null && ov.cancelled) continue;

        final patch = ov?.patch ?? const <String, dynamic>{};
        final kind = (patch['kind'] as String?) ?? (base.extras['kind'] as String?) ?? 'event';
        final completed = (patch['completed'] as bool?) ?? (base.extras['completed'] as bool?) ?? false;
        if (kind == 'task' && completed) continue;

        final title = (patch['title'] as String?) ?? occ.titleSnapshot ?? base.title;
        final message = ((patch['description'] as String?) ?? base.description ?? '').trim();
        final alarms = _parseAlarms(patch.containsKey('alarms') ? patch['alarms'] : base.extras['alarms']);
        if (alarms.isEmpty) continue;

        final dayLocal = _occurrenceDayLocal(base, occ.instanceStartAt, patch);
        if (dayLocal == null) continue;

        final instanceStartMillisUtc = occ.instanceStartAt.millisecondsSinceEpoch;
        for (final t in alarms) {
          final whenLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, t.hour, t.minute);
          if (!whenLocal.isAfter(nowLocal)) continue;
          if (whenLocal.isAfter(nowLocal.add(Duration(days: futureDays)))) continue;
          desired.add(_CalendarAlarmOccurrence(
            occurrenceKey: _occurrenceKey(
              calendarId: calendar.id,
              eventId: base.id,
              instanceStartMillisUtc: instanceStartMillisUtc,
              hour: t.hour,
              minute: t.minute,
            ),
            timeInMillis: whenLocal.millisecondsSinceEpoch,
            title: title,
            message: message,
            hour: t.hour,
            minute: t.minute,
          ));
        }
      }
    }

    desired.sort((a, b) => a.timeInMillis.compareTo(b.timeInMillis));
    final limited = desired.take(maxScheduled).toList(growable: false);
    final desiredKeys = limited.map((e) => e.occurrenceKey).toSet();

    final prefs = await SharedPreferences.getInstance();
    final previous = _loadPersisted(prefs);
    for (final old in previous) {
      if (!desiredKeys.contains(old.occurrenceKey)) {
        try {
          await _platform.invokeMethod('cancelCalendarAlarm', {
            'occurrenceKey': old.occurrenceKey,
          });
        } catch (_) {}
      }
    }

    final maxSnoozes = prefs.getInt(SettingsScreen.maxSnoozesKey) ?? 3;
    final snoozeDuration = prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
    final maxVolumePercent = prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100;
    final volumeRampUpDurationSeconds = prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30;
    final tempVolumeReductionPercent = prefs.getInt(SettingsScreen.defaultTempVolumeReductionKey) ?? 30;
    final tempVolumeReductionDurationSeconds =
        prefs.getInt(SettingsScreen.defaultTempVolumeReductionDurationKey) ?? 60;

    final persisted = <_CalendarAlarmOccurrence>[
      for (final item in limited)
        _CalendarAlarmOccurrence(
          occurrenceKey: item.occurrenceKey,
          timeInMillis: item.timeInMillis,
          title: item.title,
          message: item.message,
          hour: item.hour,
          minute: item.minute,
          maxSnoozes: maxSnoozes,
          snoozeDurationMinutes: snoozeDuration,
          maxVolumePercent: maxVolumePercent,
          volumeRampUpDurationSeconds: volumeRampUpDurationSeconds,
          tempVolumeReductionPercent: tempVolumeReductionPercent,
          tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        ),
    ];

    for (final item in persisted) {
      try {
        await _platform.invokeMethod('setCalendarAlarm', {
          'occurrenceKey': item.occurrenceKey,
          'timeInMillis': item.timeInMillis,
          'title': item.title,
          'message': item.message,
          'hour': item.hour,
          'minute': item.minute,
          'maxSnoozes': item.maxSnoozes,
          'snoozeDurationMinutes': item.snoozeDurationMinutes,
          'maxVolumePercent': item.maxVolumePercent,
          'volumeRampUpDurationSeconds': item.volumeRampUpDurationSeconds,
          'tempVolumeReductionPercent': item.tempVolumeReductionPercent,
          'tempVolumeReductionDurationSeconds': item.tempVolumeReductionDurationSeconds,
        });
      } catch (_) {}
    }

    await prefs.setString(
      _prefsKey,
      jsonEncode(persisted.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<void> rescheduleAllLocal({
    int futureDays = 30,
    int maxScheduled = 80,
  }) async {
    final nowLocal = DateTime.now();
    final windowStartUtc = nowLocal.toUtc();
    final windowEndUtc = nowLocal.add(Duration(days: futureDays)).toUtc();

    final calendars = await _repo.loadLocalCalendars();
    final desired = <_CalendarAlarmOccurrence>[];

    for (final calendar in calendars) {
      final events = await _repo.loadLocalEventsForCalendar(calendar.id);
      final eventsById = <String, CalendarEvent>{
        for (final e in events) e.id: e,
      };

      final occurrences = await _repo.loadLocalOccurrencesForCalendarInWindow(
        calendarId: calendar.id,
        windowStart: windowStartUtc,
        windowEnd: windowEndUtc,
      );

      final overridesByKey = <String, CalendarEventOverride>{};
      for (final e in events) {
        if (e.recurrenceKind == 'none') continue;
        final ovs = await _repo.loadLocalOverridesForEvent(e.id);
        for (final ov in ovs) {
          overridesByKey['${ov.eventId}:${ov.instanceStartMillisUtc}'] = ov;
        }
      }

      for (final e in events) {
        if (e.deletedAt != null) continue;
        if (e.extras['deleted'] == true) continue;
        if (e.extras['isTemplate'] == true) continue;
        if (e.recurrenceKind != 'none') continue;

        final title = e.title;
        final message = (e.description ?? '').trim();
        final kind = (e.extras['kind'] as String?) ?? 'event';
        final completed = (e.extras['completed'] as bool?) ?? false;
        if (kind == 'task' && completed) continue;

        final alarms = _parseAlarms(e.extras['alarms']);
        if (alarms.isEmpty) continue;

        final dayLocal = _eventDayLocal(e);
        if (dayLocal == null) continue;

        final instanceStartMillisUtc = _instanceStartMillisUtcForSingleEvent(e, dayLocal);
        for (final t in alarms) {
          final whenLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, t.hour, t.minute);
          if (!whenLocal.isAfter(nowLocal)) continue;
          if (whenLocal.isAfter(nowLocal.add(Duration(days: futureDays)))) continue;
          desired.add(_CalendarAlarmOccurrence(
            occurrenceKey: _occurrenceKey(
              calendarId: calendar.id,
              eventId: e.id,
              instanceStartMillisUtc: instanceStartMillisUtc,
              hour: t.hour,
              minute: t.minute,
            ),
            timeInMillis: whenLocal.millisecondsSinceEpoch,
            title: title,
            message: message,
            hour: t.hour,
            minute: t.minute,
          ));
        }
      }

      for (final occ in occurrences) {
        final base = eventsById[occ.eventId];
        if (base == null) continue;
        if (base.deletedAt != null) continue;
        if (base.extras['deleted'] == true) continue;
        if (base.extras['isTemplate'] == true) continue;

        final ov = overridesByKey['${occ.eventId}:${occ.instanceStartAt.millisecondsSinceEpoch}'];
        if (ov != null && ov.cancelled) continue;

        final patch = ov?.patch ?? const <String, dynamic>{};
        final kind = (patch['kind'] as String?) ?? (base.extras['kind'] as String?) ?? 'event';
        final completed = (patch['completed'] as bool?) ?? (base.extras['completed'] as bool?) ?? false;
        if (kind == 'task' && completed) continue;

        final title = (patch['title'] as String?) ?? occ.titleSnapshot ?? base.title;
        final message = ((patch['description'] as String?) ?? base.description ?? '').trim();
        final alarms = _parseAlarms(patch.containsKey('alarms') ? patch['alarms'] : base.extras['alarms']);
        if (alarms.isEmpty) continue;

        final dayLocal = _occurrenceDayLocal(base, occ.instanceStartAt, patch);
        if (dayLocal == null) continue;

        final instanceStartMillisUtc = occ.instanceStartAt.millisecondsSinceEpoch;
        for (final t in alarms) {
          final whenLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, t.hour, t.minute);
          if (!whenLocal.isAfter(nowLocal)) continue;
          if (whenLocal.isAfter(nowLocal.add(Duration(days: futureDays)))) continue;
          desired.add(_CalendarAlarmOccurrence(
            occurrenceKey: _occurrenceKey(
              calendarId: calendar.id,
              eventId: base.id,
              instanceStartMillisUtc: instanceStartMillisUtc,
              hour: t.hour,
              minute: t.minute,
            ),
            timeInMillis: whenLocal.millisecondsSinceEpoch,
            title: title,
            message: message,
            hour: t.hour,
            minute: t.minute,
          ));
        }
      }
    }

    desired.sort((a, b) => a.timeInMillis.compareTo(b.timeInMillis));
    final limited = desired.take(maxScheduled).toList(growable: false);
    final desiredKeys = limited.map((e) => e.occurrenceKey).toSet();

    final prefs = await SharedPreferences.getInstance();
    final previous = _loadPersisted(prefs);
    for (final old in previous) {
      if (!desiredKeys.contains(old.occurrenceKey)) {
        try {
          await _platform.invokeMethod('cancelCalendarAlarm', {
            'occurrenceKey': old.occurrenceKey,
          });
        } catch (_) {}
      }
    }

    final maxSnoozes = prefs.getInt(SettingsScreen.maxSnoozesKey) ?? 3;
    final snoozeDuration = prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5;
    final maxVolumePercent = prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100;
    final volumeRampUpDurationSeconds = prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30;
    final tempVolumeReductionPercent = prefs.getInt(SettingsScreen.defaultTempVolumeReductionKey) ?? 30;
    final tempVolumeReductionDurationSeconds =
        prefs.getInt(SettingsScreen.defaultTempVolumeReductionDurationKey) ?? 60;

    final persisted = <_CalendarAlarmOccurrence>[
      for (final item in limited)
        _CalendarAlarmOccurrence(
          occurrenceKey: item.occurrenceKey,
          timeInMillis: item.timeInMillis,
          title: item.title,
          message: item.message,
          hour: item.hour,
          minute: item.minute,
          maxSnoozes: maxSnoozes,
          snoozeDurationMinutes: snoozeDuration,
          maxVolumePercent: maxVolumePercent,
          volumeRampUpDurationSeconds: volumeRampUpDurationSeconds,
          tempVolumeReductionPercent: tempVolumeReductionPercent,
          tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        ),
    ];

    for (final item in persisted) {
      try {
        await _platform.invokeMethod('setCalendarAlarm', {
          'occurrenceKey': item.occurrenceKey,
          'timeInMillis': item.timeInMillis,
          'title': item.title,
          'message': item.message,
          'hour': item.hour,
          'minute': item.minute,
          'maxSnoozes': item.maxSnoozes,
          'snoozeDurationMinutes': item.snoozeDurationMinutes,
          'maxVolumePercent': item.maxVolumePercent,
          'volumeRampUpDurationSeconds': item.volumeRampUpDurationSeconds,
          'tempVolumeReductionPercent': item.tempVolumeReductionPercent,
          'tempVolumeReductionDurationSeconds': item.tempVolumeReductionDurationSeconds,
        });
      } catch (_) {}
    }

    await prefs.setString(
      _prefsKey,
      jsonEncode(persisted.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<_CalendarAlarmOccurrence?> _nextScheduledLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = _loadPersisted(prefs)
      ..sort((a, b) => a.timeInMillis.compareTo(b.timeInMillis));
    for (final item in all) {
      if (item.timeInMillis > now) return item;
    }
    return null;
  }

  List<_CalendarAlarmOccurrence> _loadPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return <_CalendarAlarmOccurrence>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <_CalendarAlarmOccurrence>[];
      final out = <_CalendarAlarmOccurrence>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        out.add(_CalendarAlarmOccurrence.fromJson(Map<String, dynamic>.from(item)));
      }
      return out;
    } catch (_) {
      return <_CalendarAlarmOccurrence>[];
    }
  }

  DateTime? _eventDayLocal(CalendarEvent e) {
    if (e.allDay) {
      final startDate = (e.startDate ?? '').trim();
      if (startDate.isEmpty) return null;
      final parsed = DateTime.tryParse('${startDate}T00:00:00');
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final startAt = e.startAt;
    if (startAt == null) return null;
    final local = startAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  int _instanceStartMillisUtcForSingleEvent(CalendarEvent e, DateTime dayLocal) {
    final startAt = e.startAt;
    if (startAt != null) return startAt.toUtc().millisecondsSinceEpoch;
    return DateTime(dayLocal.year, dayLocal.month, dayLocal.day).toUtc().millisecondsSinceEpoch;
  }

  DateTime? _occurrenceDayLocal(
    CalendarEvent base,
    DateTime instanceStartAtUtc,
    Map<String, dynamic> patch,
  ) {
    if (base.allDay) {
      final startDate = (patch['startDate'] as String?) ?? base.startDate;
      if (startDate == null || startDate.trim().isEmpty) return null;
      final parsed = DateTime.tryParse('${startDate.trim()}T00:00:00');
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final patchedStartAt = patch['startAt'] as String?;
    if (patchedStartAt != null) {
      final parsed = DateTime.tryParse(patchedStartAt);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }

    final local = instanceStartAtUtc.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  List<TimeOfDay> _parseAlarms(dynamic value) {
    if (value is! List) return const <TimeOfDay>[];
    final out = <TimeOfDay>[];
    for (final item in value) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final hour = (map['hour'] as num?)?.toInt();
        final minute = (map['minute'] as num?)?.toInt();
        if (hour == null || minute == null) continue;
        if (hour < 0 || hour > 23) continue;
        if (minute < 0 || minute > 59) continue;
        out.add(TimeOfDay(hour: hour, minute: minute));
      }
    }
    out.sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));
    return out;
  }

  String _occurrenceKey({
    required String calendarId,
    required String eventId,
    required int instanceStartMillisUtc,
    required int hour,
    required int minute,
  }) {
    final timeKey = '${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';
    return 'cal|$calendarId|$eventId|$instanceStartMillisUtc|$timeKey';
  }
}

class _CalendarAlarmOccurrence {
  final String occurrenceKey;
  final int timeInMillis;
  final String title;
  final String message;
  final int hour;
  final int minute;
  final int maxSnoozes;
  final int snoozeDurationMinutes;
  final int maxVolumePercent;
  final int volumeRampUpDurationSeconds;
  final int tempVolumeReductionPercent;
  final int tempVolumeReductionDurationSeconds;

  const _CalendarAlarmOccurrence({
    required this.occurrenceKey,
    required this.timeInMillis,
    required this.title,
    required this.message,
    required this.hour,
    required this.minute,
    this.maxSnoozes = 3,
    this.snoozeDurationMinutes = 5,
    this.maxVolumePercent = 100,
    this.volumeRampUpDurationSeconds = 30,
    this.tempVolumeReductionPercent = 30,
    this.tempVolumeReductionDurationSeconds = 60,
  });

  factory _CalendarAlarmOccurrence.fromJson(Map<String, dynamic> json) {
    return _CalendarAlarmOccurrence(
      occurrenceKey: (json['occurrenceKey'] as String?) ?? '',
      timeInMillis: (json['timeInMillis'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      maxSnoozes: (json['maxSnoozes'] as num?)?.toInt() ?? 3,
      snoozeDurationMinutes: (json['snoozeDurationMinutes'] as num?)?.toInt() ?? 5,
      maxVolumePercent: (json['maxVolumePercent'] as num?)?.toInt() ?? 100,
      volumeRampUpDurationSeconds:
          (json['volumeRampUpDurationSeconds'] as num?)?.toInt() ?? 30,
      tempVolumeReductionPercent:
          (json['tempVolumeReductionPercent'] as num?)?.toInt() ?? 30,
      tempVolumeReductionDurationSeconds:
          (json['tempVolumeReductionDurationSeconds'] as num?)?.toInt() ?? 60,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'occurrenceKey': occurrenceKey,
      'timeInMillis': timeInMillis,
      'title': title,
      'message': message,
      'hour': hour,
      'minute': minute,
      'maxSnoozes': maxSnoozes,
      'snoozeDurationMinutes': snoozeDurationMinutes,
      'maxVolumePercent': maxVolumePercent,
      'volumeRampUpDurationSeconds': volumeRampUpDurationSeconds,
      'tempVolumeReductionPercent': tempVolumeReductionPercent,
      'tempVolumeReductionDurationSeconds': tempVolumeReductionDurationSeconds,
    };
  }
}
