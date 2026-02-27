import 'package:hive/hive.dart';

import '../models/calendar_models.dart';

class CalendarLocalService {
  static const String calendarsBoxName = 'calendars_box';
  static const String eventsBoxName = 'calendar_events_box';
  static const String overridesBoxName = 'calendar_overrides_box';
  static const String occurrencesBoxName = 'calendar_occurrences_box';
  static const String syncBoxName = 'calendar_sync_box';

  static const String _lastPullCalendarsIsoKey = '_last_pull_calendars_iso';
  static const String _lastPullEventsIsoKey = '_last_pull_events_iso';
  static const String _lastPullOverridesIsoKey = '_last_pull_overrides_iso';
  static const String _lastPullOccurrencesIsoKey = '_last_pull_occurrences_iso';

  Box get _calendarsBox => Hive.box(calendarsBoxName);
  Box get _eventsBox => Hive.box(eventsBoxName);
  Box get _overridesBox => Hive.box(overridesBoxName);
  Box get _occurrencesBox => Hive.box(occurrencesBoxName);
  Box get _syncBox => Hive.box(syncBoxName);

  DateTime? getLastPullCalendarsTime() => _getLastPull(_lastPullCalendarsIsoKey);
  DateTime? getLastPullEventsTime() => _getLastPull(_lastPullEventsIsoKey);
  DateTime? getLastPullOverridesTime() => _getLastPull(_lastPullOverridesIsoKey);
  DateTime? getLastPullOccurrencesTime() => _getLastPull(_lastPullOccurrencesIsoKey);

  Future<void> setLastPullCalendarsTime(DateTime time) =>
      _setLastPull(_lastPullCalendarsIsoKey, time);
  Future<void> setLastPullEventsTime(DateTime time) =>
      _setLastPull(_lastPullEventsIsoKey, time);
  Future<void> setLastPullOverridesTime(DateTime time) =>
      _setLastPull(_lastPullOverridesIsoKey, time);
  Future<void> setLastPullOccurrencesTime(DateTime time) =>
      _setLastPull(_lastPullOccurrencesIsoKey, time);

  DateTime? _getLastPull(String key) {
    final raw = _syncBox.get(key);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> _setLastPull(String key, DateTime time) async {
    await _syncBox.put(key, time.toIso8601String());
  }

  String _syncKey(String entityType, String entityId) => '$entityType:$entityId';

  Future<Set<String>> getDirtyFields(String entityType, String entityId) async {
    final state = _getSyncState(entityType, entityId);
    final raw = state['dirtyFields'];
    if (raw is List) return raw.whereType<String>().toSet();
    return <String>{};
  }

  Map<String, DateTime?> getBaseFieldUpdatedAt(String entityType, String entityId) {
    final state = _getSyncState(entityType, entityId);
    final raw = state['baseFieldUpdatedAt'];
    if (raw is! Map) return <String, DateTime?>{};
    final result = <String, DateTime?>{};
    raw.forEach((k, v) {
      if (k is! String) return;
      if (v is String) {
        result[k] = DateTime.tryParse(v);
      } else if (v is int) {
        result[k] = DateTime.fromMillisecondsSinceEpoch(v);
      }
    });
    return result;
  }

  Future<void> markDirtyFields({
    required String entityType,
    required String entityId,
    required Set<String> dirtyFields,
    DateTime? updatedAtFallback,
    Map<String, DateTime>? fieldUpdatedAt,
  }) async {
    if (dirtyFields.isEmpty) return;

    final baseFieldUpdatedAt =
        Map<String, DateTime?>.from(getBaseFieldUpdatedAt(entityType, entityId));
    if (fieldUpdatedAt != null) {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => fieldUpdatedAt[field]);
      }
    } else {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => updatedAtFallback);
      }
    }

    final state = _getSyncState(entityType, entityId);
    final existingDirty = (state['dirtyFields'] is List)
        ? (state['dirtyFields'] as List).whereType<String>().toSet()
        : <String>{};
    final mergedDirty = <String>{...existingDirty, ...dirtyFields};

    state['dirtyFields'] = mergedDirty.toList();
    state['baseFieldUpdatedAt'] =
        baseFieldUpdatedAt.map((k, v) => MapEntry(k, v?.toIso8601String()));
    await _syncBox.put(_syncKey(entityType, entityId), state);
  }

  Future<void> clearDirty(String entityType, String entityId) async {
    final state = _getSyncState(entityType, entityId);
    state.remove('dirtyFields');
    state.remove('baseFieldUpdatedAt');
    await _syncBox.put(_syncKey(entityType, entityId), state);
  }

  Future<List<String>> getEntityIdsWithDirtyFields(String entityType) async {
    final ids = <String>[];
    for (final entry in _syncBox.toMap().entries) {
      final key = entry.key;
      if (key is! String) continue;
      if (!key.startsWith('$entityType:')) continue;
      final value = entry.value;
      if (value is Map) {
        final dirty = value['dirtyFields'];
        if (dirty is List && dirty.whereType<String>().isNotEmpty) {
          ids.add(key.substring(entityType.length + 1));
        }
      }
    }
    return ids;
  }

  Map<String, dynamic> _getSyncState(String entityType, String entityId) {
    final raw = _syncBox.get(_syncKey(entityType, entityId));
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<void> upsertCalendar(CalendarModel calendar) async {
    await _calendarsBox.put(calendar.id, calendar.toJson());
  }

  Future<CalendarModel?> getCalendar(String calendarId) async {
    final value = _calendarsBox.get(calendarId);
    if (value is Map) {
      return CalendarModel.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<CalendarModel>> getAllCalendars({bool includeDeleted = false}) async {
    final calendars = <CalendarModel>[];
    for (final entry in _calendarsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final cal = CalendarModel.fromJson(Map<String, dynamic>.from(value));
        if (!includeDeleted && cal.deletedAt != null) continue;
        calendars.add(cal);
      }
    }
    calendars.sort((a, b) => a.name.compareTo(b.name));
    return calendars;
  }

  Future<void> markCalendarDeleted(String calendarId) async {
    final existing = await getCalendar(calendarId);
    if (existing == null) return;
    final updated = existing.copyWith(deletedAt: DateTime.now());
    await upsertCalendar(updated);
    await markDirtyFields(
      entityType: 'calendar',
      entityId: calendarId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );
  }

  Future<void> upsertEvent(CalendarEvent event) async {
    await _eventsBox.put(event.id, event.toJson());
  }

  Future<CalendarEvent?> getEvent(String eventId) async {
    final value = _eventsBox.get(eventId);
    if (value is Map) {
      return CalendarEvent.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<CalendarEvent>> getEventsForCalendar(
    String calendarId, {
    bool includeDeleted = false,
  }) async {
    final events = <CalendarEvent>[];
    for (final entry in _eventsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final event = CalendarEvent.fromJson(Map<String, dynamic>.from(value));
        if (event.calendarId != calendarId) continue;
        if (!includeDeleted && event.deletedAt != null) continue;
        events.add(event);
      }
    }
    events.sort((a, b) {
      final aStart = a.startAt ?? DateTime.tryParse('${a.startDate}T00:00:00Z') ?? DateTime(0);
      final bStart = b.startAt ?? DateTime.tryParse('${b.startDate}T00:00:00Z') ?? DateTime(0);
      return aStart.compareTo(bStart);
    });
    return events;
  }

  Future<void> markEventDeleted(String eventId) async {
    final existing = await getEvent(eventId);
    if (existing == null) return;
    final updated = existing.copyWith(deletedAt: DateTime.now());
    await upsertEvent(updated);
    await markDirtyFields(
      entityType: 'event',
      entityId: eventId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );
  }

  Future<void> upsertOverride(CalendarEventOverride override) async {
    await _overridesBox.put(override.key, override.toJson());
  }

  Future<CalendarEventOverride?> getOverride(String overrideKey) async {
    final value = _overridesBox.get(overrideKey);
    if (value is Map) {
      return CalendarEventOverride.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<CalendarEventOverride>> getOverridesForEvent(
    String eventId, {
    bool includeDeleted = false,
  }) async {
    final overrides = <CalendarEventOverride>[];
    for (final entry in _overridesBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final ov = CalendarEventOverride.fromJson(Map<String, dynamic>.from(value));
        if (ov.eventId != eventId) continue;
        if (!includeDeleted && ov.deletedAt != null) continue;
        overrides.add(ov);
      }
    }
    overrides.sort((a, b) => a.instanceStartMillisUtc.compareTo(b.instanceStartMillisUtc));
    return overrides;
  }

  Future<void> upsertOccurrence(CalendarOccurrence occurrence) async {
    await _occurrencesBox.put(occurrence.id, occurrence.toJson());
  }

  Future<void> deleteOccurrencesForEventInWindow({
    required String eventId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final keysToDelete = <dynamic>[];
    for (final entry in _occurrencesBox.toMap().entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final occ = CalendarOccurrence.fromJson(Map<String, dynamic>.from(value));
      if (occ.eventId != eventId) continue;
      if (occ.instanceStartAt.isBefore(windowStart) ||
          occ.instanceStartAt.isAfter(windowEnd)) {
        continue;
      }
      keysToDelete.add(entry.key);
    }
    if (keysToDelete.isNotEmpty) {
      await _occurrencesBox.deleteAll(keysToDelete);
    }
  }

  Future<void> deleteOccurrencesForCalendarInWindow({
    required String calendarId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final keysToDelete = <dynamic>[];
    for (final entry in _occurrencesBox.toMap().entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final occ = CalendarOccurrence.fromJson(Map<String, dynamic>.from(value));
      if (occ.calendarId != calendarId) continue;
      if (occ.instanceStartAt.isBefore(windowStart) ||
          occ.instanceStartAt.isAfter(windowEnd)) {
        continue;
      }
      keysToDelete.add(entry.key);
    }
    if (keysToDelete.isNotEmpty) {
      await _occurrencesBox.deleteAll(keysToDelete);
    }
  }

  Future<List<CalendarOccurrence>> getOccurrencesForCalendarInWindow({
    required String calendarId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final occurrences = <CalendarOccurrence>[];
    for (final entry in _occurrencesBox.toMap().entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final occ = CalendarOccurrence.fromJson(Map<String, dynamic>.from(value));
      if (occ.calendarId != calendarId) continue;
      if (occ.instanceStartAt.isBefore(windowStart) ||
          occ.instanceStartAt.isAfter(windowEnd)) {
        continue;
      }
      occurrences.add(occ);
    }
    occurrences.sort((a, b) => a.instanceStartAt.compareTo(b.instanceStartAt));
    return occurrences;
  }
}
