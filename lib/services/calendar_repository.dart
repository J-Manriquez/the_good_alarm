import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_models.dart';
import 'calendar_firebase_service.dart';
import 'calendar_local_service.dart';

class CalendarCloudEventsBatch {
  final String calendarId;
  final List<CalendarEvent> effectiveEvents;
  final List<String> deletedIds;

  CalendarCloudEventsBatch({
    required this.calendarId,
    required this.effectiveEvents,
    required this.deletedIds,
  });
}

class CalendarRepository {
  final CalendarLocalService _local;
  final CalendarFirebaseService _cloud;

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _eventsSubscriptions = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _overridesSubscriptions = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};

  static const int _occurrenceWindowPastDays = 30;
  static const int _occurrenceWindowFutureDays = 180;

  CalendarRepository({
    CalendarLocalService? local,
    CalendarFirebaseService? cloud,
  })  : _local = local ?? CalendarLocalService(),
        _cloud = cloud ?? CalendarFirebaseService();

  Future<List<CalendarModel>> loadLocalCalendars({bool includeDeleted = false}) =>
      _local.getAllCalendars(includeDeleted: includeDeleted);

  Future<List<CalendarEvent>> loadLocalEventsForCalendar(
    String calendarId, {
    bool includeDeleted = false,
  }) =>
      _local.getEventsForCalendar(calendarId, includeDeleted: includeDeleted);

  Future<List<CalendarOccurrence>> loadLocalOccurrencesForCalendarInWindow({
    required String calendarId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) =>
      _local.getOccurrencesForCalendarInWindow(
        calendarId: calendarId,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

  Future<CalendarEventOverride?> loadLocalOverrideForOccurrence({
    required String eventId,
    required DateTime instanceStartAtUtc,
  }) =>
      _local.getOverride('${eventId}:${instanceStartAtUtc.millisecondsSinceEpoch}');

  Future<List<CalendarEventOverride>> loadLocalOverridesForEvent(
    String eventId, {
    bool includeDeleted = false,
  }) =>
      _local.getOverridesForEvent(eventId, includeDeleted: includeDeleted);

  Future<CalendarModel> ensureDefaultCalendar({
    required String userId,
  }) async {
    final deviceId = await _getDeviceId();
    final calendar =
        await _cloud.ensureDefaultCalendarForUser(userId: userId, deviceId: deviceId);
    final now = DateTime.now();
    await _local.upsertCalendar(calendar.copyWith(updatedAt: now, createdAt: calendar.createdAt ?? now));
    return calendar;
  }

  Future<List<CalendarModel>> pullOnce({
    required String userId,
  }) async {
    await ensureDefaultCalendar(userId: userId);
    final calendarIds = await _cloud.getCalendarIdsForUser(userId);
    final calendars = await _cloud.getCalendarsByIds(calendarIds);

    for (final calendar in calendars) {
      await _local.upsertCalendar(calendar);
    }
    await _local.setLastPullCalendarsTime(DateTime.now());

    final nowUtc = DateTime.now().toUtc();
    final windowStart = nowUtc.subtract(const Duration(days: _occurrenceWindowPastDays));
    final windowEnd = nowUtc.add(const Duration(days: _occurrenceWindowFutureDays));

    for (final calendar in calendars) {
      final snapshot = await _cloud.getEventsQueryStream(calendar.id).first;
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['calendarId'] ??= calendar.id;
        final event = CalendarEvent.fromJson(data);
        await _local.upsertEvent(event);
        await _materializeOccurrencesForEvent(
          event: event,
          windowStart: windowStart,
          windowEnd: windowEnd,
        );

        if (event.recurrenceKind != 'none') {
          final overridesSnap =
              await _cloud.getOverridesQueryStream(calendar.id, event.id).first;
          for (final ovDoc in overridesSnap.docs) {
            final ovData = Map<String, dynamic>.from(ovDoc.data());
            ovData['eventId'] ??= event.id;
            ovData['calendarId'] ??= calendar.id;
            ovData['instanceStartMillisUtc'] ??= _tryParseOverrideMillisFromId(ovDoc.id);
            final override = CalendarEventOverride.fromJson(ovData);
            await _local.upsertOverride(override);
          }
        }
      }
    }
    await _local.setLastPullEventsTime(DateTime.now());
    await _local.setLastPullOverridesTime(DateTime.now());

    return calendars;
  }

  Future<void> reconcile({
    required String userId,
  }) async {
    await pullOnce(userId: userId);
    await pushPendingChanges(userId: userId);
  }

  Future<void> startEventsCloudSync({
    required String calendarId,
    Future<void> Function(CalendarCloudEventsBatch batch)? onBatchApplied,
  }) async {
    await stopEventsCloudSync(calendarId: calendarId);
    _eventsSubscriptions[calendarId] =
        _cloud.getEventsQueryStream(calendarId).listen((snapshot) async {
      final effective = <CalendarEvent>[];
      final deletedIds = <String>[];

      final nowUtc = DateTime.now().toUtc();
      final windowStart = nowUtc.subtract(const Duration(days: _occurrenceWindowPastDays));
      final windowEnd = nowUtc.add(const Duration(days: _occurrenceWindowFutureDays));

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['calendarId'] ??= calendarId;
        final event = CalendarEvent.fromJson(data);
        await _local.upsertEvent(event);
        effective.add(event);

        final isDeleted = event.deletedAt != null || event.extras['deleted'] == true;
        if (isDeleted) {
          deletedIds.add(event.id);
          await _local.deleteOccurrencesForEventInWindow(
            eventId: event.id,
            windowStart: windowStart,
            windowEnd: windowEnd,
          );
          await _stopOverridesCloudSyncForEvent(calendarId: calendarId, eventId: event.id);
        } else {
          await _materializeOccurrencesForEvent(
            event: event,
            windowStart: windowStart,
            windowEnd: windowEnd,
          );
          if (event.recurrenceKind != 'none') {
            await _startOverridesCloudSyncForEvent(
              calendarId: calendarId,
              eventId: event.id,
            );
          } else {
            await _stopOverridesCloudSyncForEvent(calendarId: calendarId, eventId: event.id);
          }
        }
      }

      await _local.setLastPullEventsTime(DateTime.now());
      if (onBatchApplied != null && (effective.isNotEmpty || deletedIds.isNotEmpty)) {
        await onBatchApplied(CalendarCloudEventsBatch(
          calendarId: calendarId,
          effectiveEvents: effective,
          deletedIds: deletedIds,
        ));
      }
    });
  }

  Future<void> stopEventsCloudSync({required String calendarId}) async {
    await _eventsSubscriptions[calendarId]?.cancel();
    _eventsSubscriptions.remove(calendarId);

    final keysToStop = _overridesSubscriptions.keys
        .where((k) => k.startsWith('$calendarId:'))
        .toList(growable: false);
    for (final key in keysToStop) {
      await _overridesSubscriptions[key]?.cancel();
      _overridesSubscriptions.remove(key);
    }
  }

  Future<void> stopAllCloudSync() async {
    for (final sub in _eventsSubscriptions.values) {
      await sub.cancel();
    }
    _eventsSubscriptions.clear();

    for (final sub in _overridesSubscriptions.values) {
      await sub.cancel();
    }
    _overridesSubscriptions.clear();
  }

  Future<void> upsertCalendar({
    required CalendarModel calendar,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getCalendar(calendar.id);
    final now = DateTime.now();
    final normalized = calendar.copyWith(
      updatedAt: now,
      createdAt: calendar.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertCalendar(normalized);
    final dirtyFields = _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'calendar',
      entityId: normalized.id,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> deleteCalendar({
    required String calendarId,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getCalendar(calendarId);
    if (existing == null) return;
    final updated = existing.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _local.upsertCalendar(updated);
    await _local.markDirtyFields(
      entityType: 'calendar',
      entityId: calendarId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> upsertEvent({
    required CalendarEvent event,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getEvent(event.id);
    final now = DateTime.now();
    final normalized = event.copyWith(
      updatedAt: now,
      createdAt: event.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );
    await _local.upsertEvent(normalized);

    final nowUtc = DateTime.now().toUtc();
    final windowStart = nowUtc.subtract(const Duration(days: _occurrenceWindowPastDays));
    final windowEnd = nowUtc.add(const Duration(days: _occurrenceWindowFutureDays));
    await _materializeOccurrencesForEvent(
      event: normalized,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    final dirtyFields = _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'event',
      entityId: normalized.id,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> upsertOverride({
    required CalendarEventOverride override,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getOverride(override.key);
    final now = DateTime.now();
    final normalized = override.copyWith(
      updatedAt: now,
      createdAt: override.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertOverride(normalized);
    final dirtyFields =
        _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'override',
      entityId: normalized.key,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> deleteEvent({
    required String eventId,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getEvent(eventId);
    if (existing == null) return;
    final updated = existing.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _local.upsertEvent(updated);

    final nowUtc = DateTime.now().toUtc();
    final windowStart = nowUtc.subtract(const Duration(days: _occurrenceWindowPastDays));
    final windowEnd = nowUtc.add(const Duration(days: _occurrenceWindowFutureDays));
    await _local.deleteOccurrencesForEventInWindow(
      eventId: eventId,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    await _local.markDirtyFields(
      entityType: 'event',
      entityId: eventId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> pushPendingChanges({
    required String userId,
  }) async {
    final deviceId = await _getDeviceId();

    final calendarIds = await _local.getEntityIdsWithDirtyFields('calendar');
    for (final calendarId in calendarIds) {
      final calendar = await _local.getCalendar(calendarId);
      if (calendar == null) {
        await _local.clearDirty('calendar', calendarId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields('calendar', calendarId);
      if (dirtyFields.isEmpty) continue;

      final baseFieldUpdatedAt = _local.getBaseFieldUpdatedAt('calendar', calendarId);
      final patch = _buildPatchFromJson(calendar.toJson(), dirtyFields);
      await _cloud.applyCalendarPatch(
        calendarId: calendarId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );
      await _cloud.ensureCalendarLinkedToUser(
        userId: userId,
        calendarId: calendarId,
        deviceId: deviceId,
      );
      await _local.clearDirty('calendar', calendarId);
    }

    final eventIds = await _local.getEntityIdsWithDirtyFields('event');
    for (final eventId in eventIds) {
      final event = await _local.getEvent(eventId);
      if (event == null) {
        await _local.clearDirty('event', eventId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields('event', eventId);
      if (dirtyFields.isEmpty) continue;

      final baseFieldUpdatedAt = _local.getBaseFieldUpdatedAt('event', eventId);
      final patch = _buildPatchFromJson(event.toJson(), dirtyFields);
      await _cloud.applyEventPatch(
        calendarId: event.calendarId,
        eventId: eventId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );
      await _local.clearDirty('event', eventId);
    }

    final overrideIds = await _local.getEntityIdsWithDirtyFields('override');
    for (final overrideId in overrideIds) {
      final override = await _local.getOverride(overrideId);
      if (override == null) {
        await _local.clearDirty('override', overrideId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields('override', overrideId);
      if (dirtyFields.isEmpty) continue;

      final baseFieldUpdatedAt = _local.getBaseFieldUpdatedAt('override', overrideId);
      final patch = _buildPatchFromJson(override.toJson(), dirtyFields);
      await _cloud.applyOverridePatch(
        calendarId: override.calendarId,
        eventId: override.eventId,
        overrideId: overrideId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );
      await _local.clearDirty('override', overrideId);
    }
  }

  Set<String> _diffTopLevelFields(Map<String, dynamic>? oldJson, Map<String, dynamic> newJson) {
    if (oldJson == null) {
      return _buildComparableJson(newJson).keys.toSet();
    }

    final comparableOld = _buildComparableJson(oldJson);
    final comparableNew = _buildComparableJson(newJson);
    final keys = <String>{...comparableOld.keys, ...comparableNew.keys};
    final changed = <String>{};
    for (final key in keys) {
      if (comparableOld[key] != comparableNew[key]) {
        changed.add(key);
      }
    }
    return changed;
  }

  Map<String, dynamic> _buildComparableJson(Map<String, dynamic> json) {
    final comparable = Map<String, dynamic>.from(json);
    comparable.remove('createdAt');
    comparable.remove('updatedAt');
    comparable.remove('revision');
    comparable.remove('fieldUpdatedAt');
    return comparable;
  }

  Map<String, dynamic> _buildPatchFromJson(Map<String, dynamic> json, Set<String> dirtyFields) {
    final comparable = _buildComparableJson(json);
    final patch = <String, dynamic>{};
    for (final field in dirtyFields) {
      if (comparable.containsKey(field)) {
        patch[field] = comparable[field];
      }
    }
    return patch;
  }

  String _overrideSubscriptionKey(String calendarId, String eventId) => '$calendarId:$eventId';

  Future<void> _startOverridesCloudSyncForEvent({
    required String calendarId,
    required String eventId,
  }) async {
    final key = _overrideSubscriptionKey(calendarId, eventId);
    if (_overridesSubscriptions.containsKey(key)) return;
    _overridesSubscriptions[key] =
        _cloud.getOverridesQueryStream(calendarId, eventId).listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['eventId'] ??= eventId;
        data['calendarId'] ??= calendarId;
        data['instanceStartMillisUtc'] ??= _tryParseOverrideMillisFromId(doc.id);
        final override = CalendarEventOverride.fromJson(data);
        await _local.upsertOverride(override);
      }
      await _local.setLastPullOverridesTime(DateTime.now());
    });
  }

  Future<void> _stopOverridesCloudSyncForEvent({
    required String calendarId,
    required String eventId,
  }) async {
    final key = _overrideSubscriptionKey(calendarId, eventId);
    await _overridesSubscriptions[key]?.cancel();
    _overridesSubscriptions.remove(key);
  }

  int? _tryParseOverrideMillisFromId(String docId) {
    final parts = docId.split(':');
    if (parts.length < 2) return null;
    return int.tryParse(parts.last);
  }

  Future<void> _materializeOccurrencesForEvent({
    required CalendarEvent event,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (event.deletedAt != null) return;
    if (event.recurrenceKind == 'none') return;

    final dtStart = _eventStartDateTimeUtc(event);
    if (dtStart == null) return;

    final duration = _eventDuration(event) ?? const Duration(hours: 1);

    await _local.deleteOccurrencesForEventInWindow(
      eventId: event.id,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    final rruleRaw = event.rrule;
    if (rruleRaw == null || rruleRaw.trim().isEmpty) return;

    final rule = _parseRrule(rruleRaw);
    final freq = (rule['FREQ'] ?? '').toUpperCase();
    final interval = int.tryParse(rule['INTERVAL'] ?? '') ?? 1;
    final countLimit = int.tryParse(rule['COUNT'] ?? '');
    final until = _parseRruleUntil(rule['UNTIL']);
    final byday = _parseByDay(rule['BYDAY']);

    final effectiveWindowEnd = until != null && until.isBefore(windowEnd) ? until : windowEnd;
    final scanStart = windowStart.isAfter(dtStart) ? windowStart : dtStart;

    int emitted = 0;
    DateTime cursor = DateTime.utc(
      scanStart.year,
      scanStart.month,
      scanStart.day,
      dtStart.hour,
      dtStart.minute,
      dtStart.second,
      dtStart.millisecond,
      dtStart.microsecond,
    );

    final dtStartDate = DateTime.utc(dtStart.year, dtStart.month, dtStart.day);
    final exDates = event.exDatesMillisUtc.toSet();
    final rDates = event.rDatesMillisUtc.toSet();

    while (!cursor.isAfter(effectiveWindowEnd)) {
      final candidateStart = DateTime.utc(
        cursor.year,
        cursor.month,
        cursor.day,
        dtStart.hour,
        dtStart.minute,
        dtStart.second,
        dtStart.millisecond,
        dtStart.microsecond,
      );
      final shouldInclude = _matchesRuleDate(
        freq: freq,
        interval: interval,
        dtStartDate: dtStartDate,
        candidateDate: DateTime.utc(candidateStart.year, candidateStart.month, candidateStart.day),
        dtStart: dtStart,
        candidateStart: candidateStart,
        byday: byday,
      );

      if (shouldInclude) {
        final millis = candidateStart.millisecondsSinceEpoch;
        if (!exDates.contains(millis)) {
          if (countLimit == null || emitted < countLimit) {
            final occ = CalendarOccurrence(
              id: '${event.id}:$millis',
              calendarId: event.calendarId,
              eventId: event.id,
              instanceStartAt: candidateStart,
              instanceEndAt: candidateStart.add(duration),
              allDay: event.allDay,
              status: event.status,
              titleSnapshot: event.title,
              colorSnapshotArgb: 0,
              source: 'rrule_local',
              generatedAt: DateTime.now().toUtc(),
            );
            await _local.upsertOccurrence(occ);
            emitted++;
          }
        }
      }

      cursor = cursor.add(const Duration(days: 1));
      if (countLimit != null && emitted >= countLimit) break;
    }

    if (rDates.isNotEmpty) {
      for (final millis in rDates) {
        final rStart = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
        if (rStart.isBefore(windowStart) || rStart.isAfter(windowEnd)) continue;
        if (exDates.contains(millis)) continue;
        final occ = CalendarOccurrence(
          id: '${event.id}:$millis',
          calendarId: event.calendarId,
          eventId: event.id,
          instanceStartAt: rStart,
          instanceEndAt: rStart.add(duration),
          allDay: event.allDay,
          status: event.status,
          titleSnapshot: event.title,
          colorSnapshotArgb: 0,
          source: 'rdate',
          generatedAt: DateTime.now().toUtc(),
        );
        await _local.upsertOccurrence(occ);
      }
    }
  }

  DateTime? _eventStartDateTimeUtc(CalendarEvent event) {
    final start = event.startAt;
    if (start != null) return start.toUtc();
    final startDate = event.startDate;
    if (startDate != null && startDate.trim().isNotEmpty) {
      final parsed = DateTime.tryParse('${startDate}T00:00:00Z');
      return parsed?.toUtc();
    }
    return null;
  }

  Duration? _eventDuration(CalendarEvent event) {
    final start = event.startAt;
    final end = event.endAt;
    if (start != null && end != null) {
      return end.difference(start);
    }
    return null;
  }

  Map<String, String> _parseRrule(String rrule) {
    final raw = rrule.trim();
    final normalized = raw.startsWith('RRULE:') ? raw.substring(6) : raw;
    final parts = normalized.split(';');
    final map = <String, String>{};
    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toUpperCase();
      final value = kv[1].trim();
      if (key.isEmpty || value.isEmpty) continue;
      map[key] = value;
    }
    return map;
  }

  DateTime? _parseRruleUntil(String? untilRaw) {
    if (untilRaw == null) return null;
    final raw = untilRaw.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('T')) {
      final z = raw.endsWith('Z') ? raw : '${raw}Z';
      if (z.length < 16) return null;
      final yyyy = int.tryParse(z.substring(0, 4));
      final mm = int.tryParse(z.substring(4, 6));
      final dd = int.tryParse(z.substring(6, 8));
      final hh = int.tryParse(z.substring(9, 11));
      final mi = int.tryParse(z.substring(11, 13));
      final ss = int.tryParse(z.substring(13, 15));
      if (yyyy == null || mm == null || dd == null || hh == null || mi == null || ss == null) return null;
      return DateTime.utc(yyyy, mm, dd, hh, mi, ss);
    }
    if (raw.length < 8) return null;
    final yyyy = int.tryParse(raw.substring(0, 4));
    final mm = int.tryParse(raw.substring(4, 6));
    final dd = int.tryParse(raw.substring(6, 8));
    if (yyyy == null || mm == null || dd == null) return null;
    return DateTime.utc(yyyy, mm, dd, 23, 59, 59);
  }

  Set<int> _parseByDay(String? bydayRaw) {
    if (bydayRaw == null) return <int>{};
    final raw = bydayRaw.trim();
    if (raw.isEmpty) return <int>{};
    final set = <int>{};
    for (final part in raw.split(',')) {
      final v = part.trim().toUpperCase();
      switch (v) {
        case 'MO':
          set.add(DateTime.monday);
          break;
        case 'TU':
          set.add(DateTime.tuesday);
          break;
        case 'WE':
          set.add(DateTime.wednesday);
          break;
        case 'TH':
          set.add(DateTime.thursday);
          break;
        case 'FR':
          set.add(DateTime.friday);
          break;
        case 'SA':
          set.add(DateTime.saturday);
          break;
        case 'SU':
          set.add(DateTime.sunday);
          break;
      }
    }
    return set;
  }

  bool _matchesRuleDate({
    required String freq,
    required int interval,
    required DateTime dtStartDate,
    required DateTime candidateDate,
    required DateTime dtStart,
    required DateTime candidateStart,
    required Set<int> byday,
  }) {
    if (candidateStart.isBefore(dtStart)) return false;
    if (freq == 'DAILY') {
      final diff = candidateDate.difference(dtStartDate).inDays;
      return diff % interval == 0;
    }
    if (freq == 'WEEKLY') {
      final diffDays = candidateDate.difference(dtStartDate).inDays;
      final diffWeeks = diffDays ~/ 7;
      if (diffWeeks % interval != 0) return false;
      if (byday.isEmpty) {
        return candidateStart.weekday == dtStart.weekday;
      }
      return byday.contains(candidateStart.weekday);
    }
    if (freq == 'MONTHLY') {
      final monthsDiff = (candidateDate.year - dtStartDate.year) * 12 + (candidateDate.month - dtStartDate.month);
      if (monthsDiff % interval != 0) return false;
      final targetDay = _targetDayOfMonth(
        year: candidateDate.year,
        month: candidateDate.month,
        desiredDay: dtStartDate.day,
      );
      return candidateDate.day == targetDay;
    }
    if (freq == 'YEARLY') {
      final yearsDiff = candidateDate.year - dtStartDate.year;
      if (yearsDiff % interval != 0) return false;
      if (candidateDate.month != dtStartDate.month) return false;
      final targetDay = _targetDayOfMonth(
        year: candidateDate.year,
        month: candidateDate.month,
        desiredDay: dtStartDate.day,
      );
      return candidateDate.day == targetDay;
    }
    return false;
  }

  int _targetDayOfMonth({
    required int year,
    required int month,
    required int desiredDay,
  }) {
    final firstOfNextMonth = (month == 12) ? DateTime.utc(year + 1, 1, 1) : DateTime.utc(year, month + 1, 1);
    final lastOfMonth = firstOfNextMonth.subtract(const Duration(days: 1));
    final maxDay = lastOfMonth.day;
    return desiredDay <= maxDay ? desiredDay : maxDay;
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_name');
    if (deviceName != null && deviceName.trim().isNotEmpty) return deviceName.trim();
    return 'dispositivo_sin_nombre';
  }
}
