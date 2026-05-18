import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/calendar_models.dart';
import 'services/calendar_alarm_scheduler.dart';
import 'services/calendar_repository.dart';
import 'services/google_calendar_service.dart';
import 'settings_screen.dart';

class CalendarScreen extends StatefulWidget {
  final bool embedInShell;

  const CalendarScreen({super.key, this.embedInShell = false});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarRepository _repo = CalendarRepository();
  final CalendarAlarmScheduler _alarmScheduler = CalendarAlarmScheduler();
  final GoogleCalendarService _googleCalendar = GoogleCalendarService();

  bool _loading = true;
  String? _userId;
  List<CalendarModel> _calendars = const [];
  String? _selectedCalendarId;
  DateTime _selectedDay = DateTime.now();
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<CalendarEvent> _events = const [];
  List<_CalendarListItem> _items = const [];
  List<DateTime> _monthGridDays = const [];
  Map<int, List<_CalendarListItem>> _itemsByDayKey = const {};
  Offset? _fabOffset;
  static const double _fabSize = 56;
  static const double _fabMargin = 16;
  bool _createFabExpanded = false;
  bool _cloudSyncEnabled = false;
  String _mode = 'local';

  bool get _isGoogleMode => _mode == 'google';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repo.stopAllCloudSync();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;

    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid;
    _userId = userId;

    await _ensureLocalDefaultCalendarIfNeeded();
    await _reloadLocal();
    _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month, 1);
    await _refreshMonthData();
    unawaited(_rescheduleCalendarAlarms());

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }

    if (userId != null && _cloudSyncEnabled) {
      unawaited(_syncFromCloud(userId));
    }
  }

  Future<void> _setMode(String next) async {
    if (_mode == next) return;
    setState(() {
      _mode = next;
      _createFabExpanded = false;
      _selectedCalendarId = null;
      _calendars = const [];
      _events = const [];
      _items = const [];
      _monthGridDays = const [];
      _itemsByDayKey = const {};
    });

    if (!_isGoogleMode) {
      await _repo.stopAllCloudSync();
      await _ensureLocalDefaultCalendarIfNeeded();
      await _reloadLocal();
      await _refreshMonthData();
      unawaited(_rescheduleCalendarAlarms());
      return;
    }

    try {
      await _reloadGoogle(interactive: false);
      await _refreshMonthData();
    } catch (_) {}
  }

  int _parseGoogleHexColorToArgb(String? hex) {
    if (hex == null) return 0xFF2196F3;
    final raw = hex.trim();
    if (!raw.startsWith('#')) return 0xFF2196F3;
    final v = raw.substring(1);
    if (v.length != 6) return 0xFF2196F3;
    final rgb = int.tryParse(v, radix: 16);
    if (rgb == null) return 0xFF2196F3;
    return 0xFF000000 | rgb;
  }

  CalendarModel _calendarModelFromGoogleEntry(gcal.CalendarListEntry entry) {
    return CalendarModel(
      id: entry.id ?? '',
      ownerUid: _userId ?? '',
      name: entry.summary ?? entry.id ?? '',
      colorArgb: _parseGoogleHexColorToArgb(entry.backgroundColor),
      timeZone: entry.timeZone ?? 'UTC',
      visibility: 'private',
      extras: <String, dynamic>{
        'provider': 'google',
        'googleCalendarId': entry.id,
        'googlePrimary': entry.primary == true,
        'googleAccessRole': entry.accessRole,
        'googleSelected': entry.selected == true,
        'googleHidden': entry.hidden == true,
        'googleColorId': entry.colorId,
        'googleEtag': entry.etag,
      },
    );
  }

  CalendarEvent _calendarEventFromGoogleEvent(gcal.Event e, String calendarId) {
    final startDateTime = e.start?.dateTime;
    final endDateTime = e.end?.dateTime;
    final startDate = e.start?.date;
    final endDate = e.end?.date;
    final isAllDay = startDate != null && startDateTime == null;

    final startAtUtc = startDateTime?.toUtc();
    final endAtUtc = endDateTime?.toUtc();

    String? startDateOnly;
    String? endDateOnly;
    if (isAllDay) {
      startDateOnly = startDate?.toIso8601String().split('T').first;
      endDateOnly = endDate?.toIso8601String().split('T').first;
    }

    final reminders = <Map<String, dynamic>>[];
    final ro = e.reminders?.overrides ?? const <gcal.EventReminder>[];
    for (final r in ro) {
      reminders.add(<String, dynamic>{
        'method': r.method,
        'minutes': r.minutes,
      }..removeWhere((k, v) => v == null));
    }

    return CalendarEvent(
      id: e.id ?? '',
      calendarId: calendarId,
      title: (e.summary?.trim().isNotEmpty == true) ? e.summary!.trim() : '(Sin título)',
      description: e.description ?? '',
      locationText: e.location ?? '',
      allDay: isAllDay,
      startAt: isAllDay ? null : startAtUtc,
      endAt: isAllDay ? null : (endAtUtc ?? startAtUtc),
      startDate: isAllDay ? startDateOnly : null,
      endDate: isAllDay ? endDateOnly : null,
      timeZone: e.start?.timeZone ?? 'UTC',
      status: e.status ?? 'confirmed',
      privacy: e.visibility ?? 'default',
      recurrenceKind: 'none',
      reminders: reminders,
      createdAt: e.created?.toUtc(),
      updatedAt: e.updated?.toUtc(),
      deletedAt: null,
      revision: e.sequence ?? 0,
      extras: <String, dynamic>{
        'provider': 'google',
        'googleCalendarId': calendarId,
        'googleEventId': e.id,
        'googleEtag': e.etag,
        'googleICalUID': e.iCalUID,
        'googleHtmlLink': e.htmlLink,
        'googleHangoutLink': e.hangoutLink,
        'googleRecurringEventId': e.recurringEventId,
        'googleTransparency': e.transparency,
        'googleColorId': e.colorId,
        'googleOrganizer': e.organizer?.email,
        'googleCreator': e.creator?.email,
        'googleAttendees': (e.attendees ?? const <gcal.EventAttendee>[])
            .where((a) => (a.email ?? '').trim().isNotEmpty)
            .map((a) => <String, dynamic>{
                  'email': a.email,
                  'displayName': a.displayName,
                  'responseStatus': a.responseStatus,
                  'optional': a.optional,
                  'organizer': a.organizer,
                }..removeWhere((k, v) => v == null))
            .toList(),
      }..removeWhere((k, v) => v == null),
    );
  }

  Future<void> _connectGoogle() async {
    setState(() {
      _loading = true;
    });
    try {
      final account = await _googleCalendar.signInInteractive();
      if (account == null) return;
      await _googleCalendar.ensureFirebaseSignedIn(account);
      _userId = FirebaseAuth.instance.currentUser?.uid;
      await _reloadGoogle(interactive: true);
      await _refreshMonthData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo conectar con Google Calendar: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _disconnectGoogle() async {
    try {
      await _googleCalendar.disconnect();
    } catch (_) {
      try {
        await _googleCalendar.signOut();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _calendars = const [];
      _selectedCalendarId = null;
      _events = const [];
      _items = const [];
      _monthGridDays = const [];
      _itemsByDayKey = const {};
    });
  }

  Future<void> _reloadGoogle({required bool interactive}) async {
    final entries = await _googleCalendar.listCalendars(interactive: interactive);
    final calendars = entries
        .where((e) => (e.id ?? '').trim().isNotEmpty)
        .map(_calendarModelFromGoogleEntry)
        .toList();
    calendars.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final selected = _selectedCalendarId;
    final selectedId = selected ?? (calendars.isNotEmpty ? calendars.first.id : null);
    setState(() {
      _calendars = calendars;
      _selectedCalendarId = selectedId;
    });
  }

  Future<void> _openGoogleCalendarEditor({String? calendarId, bool createNew = false}) async {
    if (!_isGoogleMode) return;
    final targetId = createNew ? null : (calendarId ?? _selectedCalendarId);

    if (_googleCalendar.currentUser == null) {
      await _connectGoogle();
    }
    if (_googleCalendar.currentUser == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GoogleCalendarEditorScreen(
          service: _googleCalendar,
          calendarId: targetId,
        ),
      ),
    );

    await _reloadGoogle(interactive: false);
    await _refreshMonthData();
  }

  String _newLocalCalendarId() => 'local_cal_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _ensureLocalDefaultCalendarIfNeeded() async {
    final existing = await _repo.loadLocalCalendars();
    if (existing.isNotEmpty) return;

    final calendar = CalendarModel(
      id: _newLocalCalendarId(),
      ownerUid: '',
      name: 'Mi calendario',
      colorArgb: 0xFF2196F3,
      timeZone: 'UTC',
      visibility: 'private',
    );
    await _repo.upsertCalendar(
      calendar: calendar,
      cloudSyncEnabled: false,
      userId: null,
    );
  }

  Future<void> _syncFromCloud(String userId) async {
    await _repo.reconcile(userId: userId);
    if (!mounted) return;
    await _reloadLocal();
    await _refreshMonthData();
    unawaited(_rescheduleCalendarAlarms());

    final calendarId = _selectedCalendarId;
    if (calendarId == null) return;
    await _repo.startEventsCloudSync(
      calendarId: calendarId,
      onBatchApplied: (_) async {
        if (!mounted) return;
        await _reloadLocal();
        await _refreshMonthData();
        unawaited(_rescheduleCalendarAlarms());
      },
    );
  }

  Future<void> _reloadLocal() async {
    final calendars = await _repo.loadLocalCalendars();
    final selected = _selectedCalendarId;
    final selectedId = selected ??
        (calendars.isNotEmpty ? calendars.first.id : null);
    List<CalendarEvent> events = const [];
    if (selectedId != null) {
      events = await _repo.loadLocalEventsForCalendar(selectedId);
    }
    if (!mounted) return;
    setState(() {
      _calendars = calendars;
      _selectedCalendarId = selectedId;
      _events = events;
    });
  }

  int _dayKeyLocal(DateTime local) => local.year * 10000 + local.month * 100 + local.day;

  DateTime _dayAtLocalMidnight(DateTime local) => DateTime(local.year, local.month, local.day);

  DateTime _monthStartLocal(DateTime month) => DateTime(month.year, month.month, 1);

  DateTime _monthEndLocal(DateTime month) => DateTime(month.year, month.month + 1, 0);

  DateTime _gridStartLocal(DateTime month) {
    final start = _monthStartLocal(month);
    final offset = (start.weekday + 6) % 7;
    return start.subtract(Duration(days: offset));
  }

  DateTime _gridEndLocal(DateTime month) {
    final end = _monthEndLocal(month);
    final offset = (7 - end.weekday) % 7;
    return end.add(Duration(days: offset));
  }

  Future<void> _refreshMonthData() async {
    final calendarId = _selectedCalendarId;
    if (calendarId == null) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _monthGridDays = const [];
        _itemsByDayKey = const {};
      });
      return;
    }

    final gridStart = _gridStartLocal(_visibleMonth);
    final gridEnd = _gridEndLocal(_visibleMonth);

    final windowStartUtc = _dayAtLocalMidnight(gridStart).toUtc();
    final windowEndUtc = _dayAtLocalMidnight(gridEnd)
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1))
        .toUtc();

    List<CalendarEvent> effectiveEvents = _events;
    List<CalendarOccurrence> occurrences = const [];
    final overridesByEventId = <String, Map<int, CalendarEventOverride>>{};

    if (_isGoogleMode) {
      try {
        final raw = await _googleCalendar.listEventsInWindow(
          calendarId: calendarId,
          timeMinUtc: windowStartUtc,
          timeMaxUtc: windowEndUtc,
          interactive: false,
        );
        effectiveEvents = raw
            .where((e) => (e.id ?? '').trim().isNotEmpty)
            .map((e) => _calendarEventFromGoogleEvent(e, calendarId))
            .where((e) => e.id.trim().isNotEmpty)
            .toList();
      } catch (_) {
        effectiveEvents = const [];
      }
    } else {
      occurrences = await _repo.loadLocalOccurrencesForCalendarInWindow(
        calendarId: calendarId,
        windowStart: windowStartUtc,
        windowEnd: windowEndUtc,
      );

      final occEventIds = occurrences.map((o) => o.eventId).toSet();
      for (final eventId in occEventIds) {
        final overrides = await _repo.loadLocalOverridesForEvent(eventId);
        final map = <int, CalendarEventOverride>{};
        for (final ov in overrides) {
          map[ov.instanceStartMillisUtc] = ov;
        }
        overridesByEventId[eventId] = map;
      }
    }

    final eventIsTaskById = <String, bool>{
      for (final e in effectiveEvents)
        e.id: (e.extras['kind'] == 'task') || (e.extras['isTask'] == true),
    };

    final mapByDay = <int, List<_CalendarListItem>>{};

    for (final occ in occurrences) {
      final ov = overridesByEventId[occ.eventId]?[occ.instanceStartAt.millisecondsSinceEpoch];
      if (ov != null && ov.deletedAt == null && ov.cancelled) {
        continue;
      }

      final patch = (ov != null && ov.deletedAt == null) ? ov.patch : const <String, dynamic>{};
      final title = (patch['title'] as String?)?.trim().isNotEmpty == true
          ? patch['title'] as String
          : occ.titleSnapshot;
      final patchedStart = _parseDateFromPatch(patch['startAt']) ?? occ.instanceStartAt;
      final patchedEnd = _parseDateFromPatch(patch['endAt']) ?? occ.instanceEndAt;
      final isTask = (patch['kind'] == 'task') || (eventIsTaskById[occ.eventId] == true);
      final isCompleted = (patch['completed'] == true);

      final localDay = _dayAtLocalMidnight(patchedStart.toLocal());
      final key = _dayKeyLocal(localDay);
      final list = mapByDay.putIfAbsent(key, () => <_CalendarListItem>[]);
      list.add(_CalendarListItem(
        id: occ.id,
        eventId: occ.eventId,
        instanceStartMillisUtc: occ.instanceStartAt.millisecondsSinceEpoch,
        title: title,
        startAt: patchedStart,
        endAt: patchedEnd,
        source: 'occurrence',
        isTask: isTask,
        isCompleted: isCompleted,
      ));
    }

    for (final e in effectiveEvents) {
      if (e.deletedAt != null) continue;
      if (e.calendarId != calendarId) continue;
      if (e.extras['isTemplate'] == true) continue;
      if (e.recurrenceKind != 'none') continue;

      final isTask = (e.extras['kind'] == 'task') || (e.extras['isTask'] == true);
      final isCompleted = e.extras['completed'] == true;
      if (e.allDay) {
        final local = _parseLocalDateOnly(e.startDate);
        if (local == null) continue;
        if (local.isBefore(gridStart) || local.isAfter(gridEnd)) continue;
        final key = _dayKeyLocal(local);
        final list = mapByDay.putIfAbsent(key, () => <_CalendarListItem>[]);
        list.add(_CalendarListItem(
          id: e.id,
          eventId: e.id,
          instanceStartMillisUtc: 0,
          title: e.title,
          startAt: DateTime(local.year, local.month, local.day).toUtc(),
          endAt: DateTime(local.year, local.month, local.day).toUtc(),
          source: 'event',
          isTask: isTask,
          isCompleted: isCompleted,
        ));
        continue;
      }

      final startLocal = e.startAt?.toLocal();
      if (startLocal == null) continue;
      if (startLocal.isBefore(gridStart) || startLocal.isAfter(gridEnd.add(const Duration(days: 1)))) {
        continue;
      }
      final localDay = _dayAtLocalMidnight(startLocal);
      final key = _dayKeyLocal(localDay);
      final list = mapByDay.putIfAbsent(key, () => <_CalendarListItem>[]);
      list.add(_CalendarListItem(
        id: e.id,
        eventId: e.id,
        instanceStartMillisUtc: 0,
        title: e.title,
        startAt: e.startAt!.toUtc(),
        endAt: (e.endAt ?? e.startAt!).toUtc(),
        source: 'event',
        isTask: isTask,
        isCompleted: isCompleted,
      ));
    }

    if (!mounted) return;
    final gridDays = <DateTime>[];
    final totalDays = gridEnd.difference(gridStart).inDays + 1;
    for (int i = 0; i < totalDays; i++) {
      gridDays.add(gridStart.add(Duration(days: i)));
    }

    final selectedKey = _dayKeyLocal(_dayAtLocalMidnight(_selectedDay));
    final selectedItems = List<_CalendarListItem>.from(mapByDay[selectedKey] ?? const []);
    selectedItems.sort((a, b) => a.startAt.toLocal().compareTo(b.startAt.toLocal()));

    setState(() {
      _monthGridDays = gridDays;
      _itemsByDayKey = mapByDay;
      _items = selectedItems;
      if (_isGoogleMode) {
        _events = effectiveEvents;
      }
    });
  }

  DateTime? _parseDateFromPatch(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    return null;
  }

  DateTime? _parseLocalDateOnly(String? yyyyMmDd) {
    if (yyyyMmDd == null) return null;
    final parts = yyyyMmDd.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _selectedDay = picked;
      _visibleMonth = DateTime(picked.year, picked.month, 1);
    });
    await _refreshMonthData();
  }

  Future<void> _selectDay(DateTime day) async {
    final normalized = _dayAtLocalMidnight(day);
    setState(() {
      _selectedDay = normalized;
    });
    final key = _dayKeyLocal(normalized);
    final items = List<_CalendarListItem>.from(_itemsByDayKey[key] ?? const []);
    items.sort((a, b) => a.startAt.toLocal().compareTo(b.startAt.toLocal()));
    if (!mounted) return;
    setState(() {
      _items = items;
    });
  }

  Future<void> _goToPrevMonth() async {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    setState(() {
      _visibleMonth = prev;
    });
    await _refreshMonthData();
  }

  Future<void> _goToNextMonth() async {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    setState(() {
      _visibleMonth = next;
    });
    await _refreshMonthData();
  }

  Future<void> _goToToday() async {
    final now = DateTime.now();
    setState(() {
      _selectedDay = _dayAtLocalMidnight(now);
      _visibleMonth = DateTime(now.year, now.month, 1);
    });
    await _refreshMonthData();
  }

  Future<void> _openEditor({
    required String kind,
    String? eventId,
    int? instanceStartMillisUtc,
  }) async {
    final calendarId = _selectedCalendarId;
    if (calendarId == null) return;

    setState(() {
      _createFabExpanded = false;
    });

    if (_isGoogleMode) {
      if (kind == 'task') return;
      final existing = eventId == null
          ? null
          : _events.where((e) => e.id == eventId).cast<CalendarEvent?>().firstWhere(
                (e) => e != null,
                orElse: () => null,
              );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => GoogleCalendarEventEditorScreen(
            service: _googleCalendar,
            calendarId: calendarId,
            initialDay: _selectedDay,
            existingEvent: existing,
          ),
        ),
      );
      await _refreshMonthData();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CalendarEventEditorScreen(
          userId: _userId,
          calendarId: calendarId,
          initialDay: _selectedDay,
          initialKind: kind,
          eventId: eventId,
          instanceStartMillisUtc: instanceStartMillisUtc,
        ),
      ),
    );

    await _reloadLocal();
    await _refreshMonthData();
  }

  Future<void> _rescheduleCalendarAlarms() async {
    final userId = _userId;
    if (userId != null && _cloudSyncEnabled) {
      await _alarmScheduler.rescheduleAllForUser(
        userId: userId,
        cloudSyncEnabled: true,
      );
      return;
    }
    await _alarmScheduler.rescheduleAllLocal();
  }

  Future<void> _toggleTaskCompletion(_CalendarListItem item, bool next) async {
    final userId = _userId;
    final calendarId = _selectedCalendarId;
    if (calendarId == null) return;
    if (!item.isTask) return;

    if (item.source == 'event') {
      final index = _events.indexWhere((e) => e.id == item.eventId);
      if (index < 0) return;
      final existing = _events[index];
      final extras = Map<String, dynamic>.from(existing.extras);
      extras['completed'] = next;
      final updated = existing.copyWith(extras: extras);
      await _repo.upsertEvent(
        event: updated,
        cloudSyncEnabled: _cloudSyncEnabled && userId != null,
        userId: userId,
      );
      unawaited(_rescheduleCalendarAlarms());
      await _reloadLocal();
      await _refreshMonthData();
      return;
    }

    if (item.source == 'occurrence') {
      final now = DateTime.now();
      final instanceStartAtUtc = DateTime.fromMillisecondsSinceEpoch(
        item.instanceStartMillisUtc,
        isUtc: true,
      );
      final existing = await _repo.loadLocalOverrideForOccurrence(
        eventId: item.eventId,
        instanceStartAtUtc: instanceStartAtUtc,
      );
      final patch = Map<String, dynamic>.from(existing?.patch ?? const <String, dynamic>{});
      patch['completed'] = next;
      patch['kind'] = 'task';
      final override = CalendarEventOverride(
        eventId: item.eventId,
        calendarId: calendarId,
        instanceStartMillisUtc: item.instanceStartMillisUtc,
        type: 'modify',
        patch: patch,
        cancelled: false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: null,
        revision: existing?.revision ?? 0,
        fieldUpdatedAt: existing?.fieldUpdatedAt,
        extras: existing?.extras,
      );
      await _repo.upsertOverride(
        override: override,
        cloudSyncEnabled: _cloudSyncEnabled && userId != null,
        userId: userId,
      );
      unawaited(_rescheduleCalendarAlarms());
      await _reloadLocal();
      await _refreshMonthData();
    }
  }

  String? _rruleForRecurrence(String recurrence, DateTime startAt) {
    if (recurrence == 'none') return null;
    if (recurrence == 'daily') return 'FREQ=DAILY;INTERVAL=1';
    if (recurrence == 'weekly') {
      final byday = _weekdayToByDay(startAt.weekday);
      return 'FREQ=WEEKLY;INTERVAL=1;BYDAY=$byday';
    }
    if (recurrence == 'monthly') return 'FREQ=MONTHLY;INTERVAL=1';
    if (recurrence == 'yearly') return 'FREQ=YEARLY;INTERVAL=1';
    return null;
  }

  String _weekdayToByDay(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'MO';
      case DateTime.tuesday:
        return 'TU';
      case DateTime.wednesday:
        return 'WE';
      case DateTime.thursday:
        return 'TH';
      case DateTime.friday:
        return 'FR';
      case DateTime.saturday:
        return 'SA';
      case DateTime.sunday:
        return 'SU';
    }
    return 'MO';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    Widget? buildCreateFab({required bool expandUp}) {
      if (_selectedCalendarId == null) return null;
      final expandedHeight = _isGoogleMode ? 130.0 : 190.0;
      return SizedBox(
        width: 56,
        height: _createFabExpanded ? expandedHeight : 56,
        child: Stack(
          alignment: expandUp ? Alignment.bottomRight : Alignment.topRight,
          children: [
            FloatingActionButton(
              heroTag: 'calendar_create_main_fab',
              backgroundColor: scheme.primary,
              onPressed: () {
                setState(() {
                  _createFabExpanded = !_createFabExpanded;
                });
              },
              child: Icon(
                _createFabExpanded ? Icons.close : Icons.add,
                color: scheme.onPrimary,
              ),
            ),
            if (_createFabExpanded) ...[
              if (!_isGoogleMode)
                Positioned(
                  right: 0,
                  bottom: expandUp ? 70 : null,
                  top: expandUp ? null : 70,
                  child: FloatingActionButton.small(
                    heroTag: 'calendar_create_task_fab',
                    backgroundColor: scheme.primary,
                    onPressed: () => _openEditor(kind: 'task'),
                    child: Icon(Icons.task_alt, color: scheme.onPrimary),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: expandUp ? (_isGoogleMode ? 70 : 130) : null,
                top: expandUp ? null : (_isGoogleMode ? 70 : 130),
                child: FloatingActionButton.small(
                  heroTag: 'calendar_create_event_fab',
                  backgroundColor: scheme.primary,
                  onPressed: () => _openEditor(kind: 'event'),
                  child: Icon(Icons.event, color: scheme.onPrimary),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final body = _loading
        ? Center(child: CircularProgressIndicator(color: scheme.primary))
        : CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ToggleButtons(
                              isSelected: [_mode == 'local', _mode == 'google'],
                              onPressed: (index) async {
                                final next = index == 0 ? 'local' : 'google';
                                await _setMode(next);
                              },
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text('Local'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text('Google'),
                                ),
                              ],
                            ),
                          ),
                          if (_isGoogleMode) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: _googleCalendar.currentUser == null ? 'Conectar' : 'Actualizar',
                              onPressed: () async {
                                if (_googleCalendar.currentUser == null) {
                                  await _connectGoogle();
                                  return;
                                }
                                await _reloadGoogle(interactive: false);
                                await _refreshMonthData();
                              },
                              icon: Icon(
                                _googleCalendar.currentUser == null ? Icons.login : Icons.refresh,
                                color: scheme.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Crear calendario',
                              onPressed: _googleCalendar.currentUser == null
                                  ? null
                                  : () => _openGoogleCalendarEditor(createNew: true),
                              icon: Icon(Icons.add, color: scheme.primary),
                            ),
                            IconButton(
                              tooltip: 'Editar calendario',
                              onPressed: _googleCalendar.currentUser == null
                                  ? null
                                  : () => _openGoogleCalendarEditor(),
                              icon: Icon(Icons.edit_calendar, color: scheme.primary),
                            ),
                            IconButton(
                              tooltip: 'Cerrar sesión Google',
                              onPressed: _googleCalendar.currentUser == null ? null : _disconnectGoogle,
                              icon: Icon(Icons.logout, color: scheme.primary),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: scheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: scheme.surface,
                              isExpanded: true,
                              value: _selectedCalendarId,
                              items: _calendars
                                  .map((c) => DropdownMenuItem<String>(
                                        value: c.id,
                                        child: Text(
                                          c.name,
                                          style: TextStyle(color: scheme.onSurface),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (value) async {
                                if (value == null) return;
                                if (_isGoogleMode) {
                                  setState(() {
                                    _selectedCalendarId = value;
                                  });
                                  await _refreshMonthData();
                                  return;
                                }

                                await _repo.stopAllCloudSync();
                                setState(() {
                                  _selectedCalendarId = value;
                                });
                                await _reloadLocal();
                                if (_userId != null && _cloudSyncEnabled) {
                                  await _repo.startEventsCloudSync(
                                    calendarId: value,
                                    onBatchApplied: (_) async {
                                      if (!mounted) return;
                                      await _reloadLocal();
                                      await _refreshMonthData();
                                      unawaited(_rescheduleCalendarAlarms());
                                    },
                                  );
                                }
                                await _refreshMonthData();
                                unawaited(_rescheduleCalendarAlarms());
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _goToPrevMonth,
                            icon: Icon(Icons.chevron_left, color: scheme.primary),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                '${_monthNameEs(_visibleMonth.month)} ${_visibleMonth.year}',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _goToToday,
                            child: Text(
                              'Hoy',
                              style: TextStyle(color: scheme.primary, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            onPressed: _goToNextMonth,
                            icon: Icon(Icons.chevron_right, color: scheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildWeekdayHeader(),
                      const SizedBox(height: 8),
                      _buildMonthGrid(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedDay.day.toString().padLeft(2, '0')}/${_selectedDay.month.toString().padLeft(2, '0')}/${_selectedDay.year}',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _pickDay,
                            child: Text(
                              'Ir a fecha',
                              style: TextStyle(color: scheme.primary, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Sin eventos para este día',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 12),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final i = items[index];
                      final start = i.startAt.toLocal();
                      final time = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
                      return Card(
                        color: Theme.of(context).colorScheme.surface,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            i.isTask ? Icons.check_circle_outline : Icons.event,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            i.title,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                          subtitle: Text(
                            i.isTask ? 'Tarea' : time,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                          trailing: i.isTask
                              ? Checkbox(
                                  value: i.isCompleted,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    _toggleTaskCompletion(i, value);
                                  },
                                )
                              : null,
                          onTap: () => _openEditor(
                            kind: i.isTask ? 'task' : 'event',
                            eventId: i.eventId,
                            instanceStartMillisUtc:
                                i.source == 'occurrence' ? i.instanceStartMillisUtc : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );

    if (!widget.embedInShell) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Calendario'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final baseFab = buildCreateFab(expandUp: true);
            if (baseFab == null) return body;
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final initial = Offset(
              size.width - _fabSize - _fabMargin,
              size.height - _fabSize - _fabMargin,
            );
            final current = _fabOffset ?? initial;
            final clamped = Offset(
              current.dx.clamp(_fabMargin, size.width - _fabSize - _fabMargin),
              current.dy.clamp(_fabMargin, size.height - _fabSize - _fabMargin),
            );
            _fabOffset = clamped;
            const expandedHeight = 190.0;
            final extra = expandedHeight - _fabSize;
            final spaceAbove = clamped.dy - _fabMargin;
            final spaceBelow = size.height - (clamped.dy + _fabSize) - _fabMargin;
            final expandUp = spaceAbove >= extra && (spaceBelow < extra || spaceAbove >= spaceBelow);
            final fab = buildCreateFab(expandUp: expandUp)!;
            final top = _createFabExpanded && expandUp ? clamped.dy - extra : clamped.dy;

            return Stack(
              children: [
                body,
                Positioned(
                  left: clamped.dx,
                  top: top,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final next = Offset(
                        (_fabOffset!.dx + details.delta.dx).clamp(
                          _fabMargin,
                          size.width - _fabSize - _fabMargin,
                        ),
                        (_fabOffset!.dy + details.delta.dy).clamp(
                          _fabMargin,
                          size.height - _fabSize - _fabMargin,
                        ),
                      );
                      setState(() {
                        _fabOffset = next;
                      });
                    },
                    child: fab,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseFab = buildCreateFab(expandUp: true);
        if (baseFab == null) {
          return Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: body,
          );
        }
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final initial = Offset(
          size.width - _fabSize - _fabMargin,
          size.height - _fabSize - _fabMargin,
        );
        final current = _fabOffset ?? initial;
        final clamped = Offset(
          current.dx.clamp(_fabMargin, size.width - _fabSize - _fabMargin),
          current.dy.clamp(_fabMargin, size.height - _fabSize - _fabMargin),
        );
        _fabOffset = clamped;
        const expandedHeight = 190.0;
        final extra = expandedHeight - _fabSize;
        final spaceAbove = clamped.dy - _fabMargin;
        final spaceBelow = size.height - (clamped.dy + _fabSize) - _fabMargin;
        final expandUp = spaceAbove >= extra && (spaceBelow < extra || spaceAbove >= spaceBelow);
        final fab = buildCreateFab(expandUp: expandUp)!;
        final top = _createFabExpanded && expandUp ? clamped.dy - extra : clamped.dy;

        return Stack(
          children: [
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: body,
            ),
            Positioned(
              left: clamped.dx,
              top: top,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final next = Offset(
                    (_fabOffset!.dx + details.delta.dx).clamp(
                      _fabMargin,
                      size.width - _fabSize - _fabMargin,
                    ),
                    (_fabOffset!.dy + details.delta.dy).clamp(
                      _fabMargin,
                      size.height - _fabSize - _fabMargin,
                    ),
                  );
                  setState(() {
                    _fabOffset = next;
                  });
                },
                child: fab,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Row(
      children: labels
          .map(
            (l) => Expanded(
              child: Center(
                child: Text(
                  l,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMonthGrid() {
    final days = _monthGridDays;
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = 56.0;
        final rows = (days.length / 7).ceil();
        final height = rows * cellHeight;
        return SizedBox(
          height: height,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: cellWidth / cellHeight,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final inMonth = day.month == _visibleMonth.month && day.year == _visibleMonth.year;
              final isToday = _dayKeyLocal(_dayAtLocalMidnight(DateTime.now())) == _dayKeyLocal(day);
              final isSelected = _dayKeyLocal(_dayAtLocalMidnight(_selectedDay)) == _dayKeyLocal(day);
              final key = _dayKeyLocal(day);
              final entries = _itemsByDayKey[key] ?? const <_CalendarListItem>[];
              final preview = entries.take(2).toList(growable: false);
              final more = entries.length - preview.length;

              return GestureDetector(
                onTap: () async {
                  if (!inMonth) {
                    setState(() {
                      _visibleMonth = DateTime(day.year, day.month, 1);
                    });
                    await _refreshMonthData();
                  }
                  await _selectDay(day);
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected || isToday
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      width: isSelected || isToday ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (preview.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ClipRect(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final p in preview)
                                      Text(
                                        p.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.isTask
                                              ? Theme.of(context).colorScheme.secondary
                                              : Theme.of(context).colorScheme.onSurface,
                                          fontSize: 10,
                                        ),
                                      ),
                                    if (more > 0)
                                      Text(
                                        '+$more',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _monthNameEs(int month) {
    switch (month) {
      case 1:
        return 'Enero';
      case 2:
        return 'Febrero';
      case 3:
        return 'Marzo';
      case 4:
        return 'Abril';
      case 5:
        return 'Mayo';
      case 6:
        return 'Junio';
      case 7:
        return 'Julio';
      case 8:
        return 'Agosto';
      case 9:
        return 'Septiembre';
      case 10:
        return 'Octubre';
      case 11:
        return 'Noviembre';
      case 12:
        return 'Diciembre';
    }
    return '';
  }
}

class CalendarEventEditorScreen extends StatefulWidget {
  final String? userId;
  final String? calendarId;
  final DateTime initialDay;
  final String initialKind;
  final String? eventId;
  final int? instanceStartMillisUtc;

  const CalendarEventEditorScreen({
    super.key,
    this.userId,
    this.calendarId,
    required this.initialDay,
    required this.initialKind,
    this.eventId,
    this.instanceStartMillisUtc,
  });

  @override
  State<CalendarEventEditorScreen> createState() => _CalendarEventEditorScreenState();
}

class _CalendarEventEditorScreenState extends State<CalendarEventEditorScreen> {
  final CalendarRepository _repo = CalendarRepository();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _loading = true;
  bool _cloudSyncEnabled = false;
  String? _userId;
  String? _calendarId;
  String _kind = 'event';
  DateTime _day = DateTime.now();
  int _hour = 9;
  int _minute = 0;
  String _recurrence = 'none';
  String _editScope = 'occurrence';

  bool _checklistEnabled = false;
  List<Map<String, dynamic>> _checklist = <Map<String, dynamic>>[];
  List<Map<String, int>> _alarms = <Map<String, int>>[];

  List<CalendarEvent> _templates = const [];
  String? _selectedTemplateId;
  CalendarEvent? _editingEvent;
  CalendarEventOverride? _editingOverride;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _day = DateTime(widget.initialDay.year, widget.initialDay.month, widget.initialDay.day);
    _init();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    _cloudSyncEnabled = (prefs.getBool(SettingsScreen.cloudSyncKey) ?? false) && userId != null;
    _userId = userId;

    final providedCalendarId = widget.calendarId;
    String calendarId;
    if (providedCalendarId != null) {
      calendarId = providedCalendarId;
    } else if (userId != null) {
      calendarId = (await _repo.ensureDefaultCalendar(userId: userId)).id;
    } else {
      final localCalendars = await _repo.loadLocalCalendars();
      if (localCalendars.isNotEmpty) {
        calendarId = localCalendars.first.id;
      } else {
        final now = DateTime.now();
        final local = CalendarModel(
          id: 'local_cal_${now.microsecondsSinceEpoch}',
          ownerUid: '',
          name: 'Mi calendario',
          colorArgb: 0xFF2196F3,
          timeZone: 'UTC',
          visibility: 'private',
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
          revision: 0,
        );
        await _repo.upsertCalendar(
          calendar: local,
          cloudSyncEnabled: false,
          userId: null,
        );
        calendarId = local.id;
      }
    }
    _calendarId = calendarId;

    final events = await _repo.loadLocalEventsForCalendar(calendarId);
    _templates = events.where((e) {
      if (e.deletedAt != null) return false;
      if (e.extras['isTemplate'] != true) return false;
      final k = e.extras['templateKind'];
      return k == null || k == _kind;
    }).toList();

    final editingEventId = widget.eventId;
    if (editingEventId != null) {
      _editingEvent = events.where((e) => e.id == editingEventId).cast<CalendarEvent?>().firstWhere(
            (e) => e != null,
            orElse: () => null,
          );

      if (_editingEvent != null && widget.instanceStartMillisUtc != null) {
        final instanceUtc = DateTime.fromMillisecondsSinceEpoch(
          widget.instanceStartMillisUtc!,
          isUtc: true,
        );
        _editingOverride = await _repo.loadLocalOverrideForOccurrence(
          eventId: editingEventId,
          instanceStartAtUtc: instanceUtc,
        );
      }
    }

    _applyInitialData();

    setState(() {
      _loading = false;
    });
  }

  DateTime? _parseDateFromPatch(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    return null;
  }

  void _applyInitialData() {
    final ov = _editingOverride;
    final patch = ov?.patch ?? const <String, dynamic>{};
    final e = _editingEvent;

    final kindFromEvent = (e?.extras['kind'] as String?) ?? (patch['kind'] as String?);
    if (kindFromEvent == 'task' || kindFromEvent == 'event') {
      _kind = kindFromEvent!;
    }

    final title = (patch['title'] as String?) ?? e?.title;
    if (title != null) {
      _titleController.text = title;
    }

    final desc = (patch['description'] as String?) ?? e?.description;
    if (desc != null) {
      _descriptionController.text = desc;
    }

    final rawChecklist = patch['checklist'] ?? e?.extras['checklist'];
    if (rawChecklist is List) {
      _checklist = rawChecklist
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      _checklistEnabled = _checklist.isNotEmpty;
    }

    final rawAlarms = patch['alarms'] ?? e?.extras['alarms'];
    if (rawAlarms is List) {
      _alarms = rawAlarms
          .whereType<Map>()
          .map((m) => <String, int>{
                'hour': (m['hour'] as num?)?.toInt() ?? 0,
                'minute': (m['minute'] as num?)?.toInt() ?? 0,
              })
          .toList();
    }

    final startAt = _parseDateFromPatch(patch['startAt']) ?? e?.startAt;
    final startDate = (patch['startDate'] as String?) ?? e?.startDate;
    if (startAt != null) {
      final local = startAt.toLocal();
      _day = DateTime(local.year, local.month, local.day);
      _hour = local.hour;
      _minute = local.minute;
    } else if (startDate != null && startDate.trim().isNotEmpty) {
      final local = DateTime.tryParse('${startDate}T00:00:00');
      if (local != null) {
        _day = DateTime(local.year, local.month, local.day);
      }
    }

    final isTemplate = e?.extras['isTemplate'] == true;
    if (isTemplate) {
      final data = e?.extras['templateData'];
      if (data is Map) {
        final d = Map<String, dynamic>.from(data);
        final r = d['recurrence'];
        if (r is String) _recurrence = r;
        final t = d['time'];
        if (t is Map) {
          _hour = (t['hour'] as num?)?.toInt() ?? _hour;
          _minute = (t['minute'] as num?)?.toInt() ?? _minute;
        }
      }
    } else {
      _recurrence = _recurrenceFromEvent(e);
    }

    final editingOccurrence = widget.instanceStartMillisUtc != null &&
        e != null &&
        e.recurrenceKind != 'none';
    _editScope = editingOccurrence ? 'occurrence' : 'series';
  }

  String _recurrenceFromEvent(CalendarEvent? e) {
    if (e == null) return 'none';
    if (e.recurrenceKind == 'none') return 'none';
    final rule = e.rrule ?? '';
    if (rule.contains('FREQ=DAILY')) return 'daily';
    if (rule.contains('FREQ=WEEKLY')) return 'weekly';
    if (rule.contains('FREQ=MONTHLY')) return 'monthly';
    if (rule.contains('FREQ=YEARLY')) return 'yearly';
    return 'none';
  }

  Future<void> _rescheduleCalendarAlarms() async {
    final userId = _userId;
    final scheduler = CalendarAlarmScheduler(repo: _repo);
    if (userId != null && _cloudSyncEnabled) {
      await scheduler.rescheduleAllForUser(
        userId: userId,
        cloudSyncEnabled: true,
      );
      return;
    }
    await scheduler.rescheduleAllLocal();
  }

  Future<void> _save() async {
    final userId = _userId;
    final calendarId = _calendarId;
    if (calendarId == null) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final now = DateTime.now();
    final recurrenceKind = _recurrence == 'none' ? 'none' : 'rrule';
    final startLocal = DateTime(_day.year, _day.month, _day.day, _kind == 'task' ? 0 : _hour, _kind == 'task' ? 0 : _minute);
    final startUtc = startLocal.toUtc();
    final endUtc = (_kind == 'task' ? startUtc : startUtc.add(const Duration(hours: 1)));
    final startDateOnly = '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';
    final rule = recurrenceKind == 'none' ? null : _rruleFor(_recurrence, startLocal);

    final baseExtras = <String, dynamic>{
      'kind': _kind,
      'checklist': _checklistEnabled ? _checklist : const <Map<String, dynamic>>[],
      'alarms': _alarms,
    };

    final editingEvent = _editingEvent;
    final instanceMillisUtc = widget.instanceStartMillisUtc;

    if (editingEvent != null &&
        instanceMillisUtc != null &&
        editingEvent.recurrenceKind != 'none' &&
        _editScope == 'occurrence') {
      final patch = <String, dynamic>{
        'title': title,
        'description': _descriptionController.text,
        'startAt': startUtc.toIso8601String(),
        'endAt': endUtc.toIso8601String(),
        'startDate': _kind == 'task' ? startDateOnly : null,
        ...baseExtras,
      }..removeWhere((k, v) => v == null);

      final existing = _editingOverride;
      final override = CalendarEventOverride(
        eventId: editingEvent.id,
        calendarId: calendarId,
        instanceStartMillisUtc: instanceMillisUtc,
        type: 'modify',
        patch: patch,
        cancelled: false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: null,
        revision: existing?.revision ?? 0,
        fieldUpdatedAt: existing?.fieldUpdatedAt,
        extras: existing?.extras,
      );
      await _repo.upsertOverride(
        override: override,
        cloudSyncEnabled: _cloudSyncEnabled && userId != null,
        userId: userId,
      );
      unawaited(_rescheduleCalendarAlarms());
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final eventId = editingEvent?.id ??
        FirebaseFirestore.instance
            .collection('calendarios')
            .doc(calendarId)
            .collection('eventos')
            .doc()
            .id;

    final event = (editingEvent != null)
        ? editingEvent.copyWith(
            title: title,
            description: _descriptionController.text,
            startAt: _kind == 'task' ? null : startUtc,
            endAt: _kind == 'task' ? null : endUtc,
            allDay: _kind == 'task',
            startDate: _kind == 'task' ? startDateOnly : null,
            recurrenceKind: recurrenceKind,
            rrule: rule,
            updatedAt: now,
            deletedAt: null,
            extras: <String, dynamic>{
              ...editingEvent.extras,
              ...baseExtras,
              'isTemplate': false,
            },
          )
        : CalendarEvent(
            id: eventId,
            calendarId: calendarId,
            title: title,
            description: _descriptionController.text,
            startAt: _kind == 'task' ? null : startUtc,
            endAt: _kind == 'task' ? null : endUtc,
            allDay: _kind == 'task',
            startDate: _kind == 'task' ? startDateOnly : null,
            timeZone: 'UTC',
            recurrenceKind: recurrenceKind,
            rrule: rule,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
            revision: 0,
            extras: <String, dynamic>{
              ...baseExtras,
              'isTemplate': false,
            },
          );

    await _repo.upsertEvent(
      event: event,
      cloudSyncEnabled: _cloudSyncEnabled && userId != null,
      userId: userId,
    );
    unawaited(_rescheduleCalendarAlarms());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _saveAsTemplate() async {
    final userId = _userId;
    final calendarId = _calendarId;
    if (calendarId == null) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final now = DateTime.now();
    final templateId = FirebaseFirestore.instance
        .collection('calendarios')
        .doc(calendarId)
        .collection('eventos')
        .doc()
        .id;

    final template = CalendarEvent(
      id: templateId,
      calendarId: calendarId,
      title: title,
      description: _descriptionController.text,
      allDay: true,
      startDate: '',
      timeZone: 'UTC',
      recurrenceKind: 'none',
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      revision: 0,
      extras: <String, dynamic>{
        'isTemplate': true,
        'templateKind': _kind,
        'templateData': <String, dynamic>{
          'recurrence': _recurrence,
          'time': <String, int>{'hour': _hour, 'minute': _minute},
          'checklist': _checklistEnabled ? _checklist : const <Map<String, dynamic>>[],
          'alarms': _alarms,
        },
      },
    );

    await _repo.upsertEvent(
      event: template,
      cloudSyncEnabled: _cloudSyncEnabled && userId != null,
      userId: userId,
    );

    final events = await _repo.loadLocalEventsForCalendar(calendarId);
    setState(() {
      _templates = events.where((e) {
        if (e.deletedAt != null) return false;
        if (e.extras['isTemplate'] != true) return false;
        final k = e.extras['templateKind'];
        return k == null || k == _kind;
      }).toList();
      _selectedTemplateId = templateId;
    });
  }

  void _applyTemplate(CalendarEvent template) {
    final data = template.extras['templateData'];
    if (data is! Map) return;
    final d = Map<String, dynamic>.from(data);
    _titleController.text = template.title;
    _descriptionController.text = template.description ?? '';
    final r = d['recurrence'];
    if (r is String) {
      _recurrence = r;
    }
    final t = d['time'];
    if (t is Map) {
      _hour = (t['hour'] as num?)?.toInt() ?? _hour;
      _minute = (t['minute'] as num?)?.toInt() ?? _minute;
    }
    final c = d['checklist'];
    if (c is List) {
      _checklist = c.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      _checklistEnabled = _checklist.isNotEmpty;
    }
    final a = d['alarms'];
    if (a is List) {
      _alarms = a
          .whereType<Map>()
          .map((m) => <String, int>{
                'hour': (m['hour'] as num?)?.toInt() ?? 0,
                'minute': (m['minute'] as num?)?.toInt() ?? 0,
              })
          .toList();
    }
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  String? _rruleFor(String recurrence, DateTime startLocal) {
    if (recurrence == 'none') return null;
    switch (recurrence) {
      case 'daily':
        return 'FREQ=DAILY;INTERVAL=1';
      case 'weekly':
        return 'FREQ=WEEKLY;INTERVAL=1;BYDAY=${_weekdayToByDay(startLocal.weekday)}';
      case 'monthly':
        return 'FREQ=MONTHLY;INTERVAL=1';
      case 'yearly':
        return 'FREQ=YEARLY;INTERVAL=1';
    }
    return null;
  }

  String _weekdayToByDay(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'MO';
      case DateTime.tuesday:
        return 'TU';
      case DateTime.wednesday:
        return 'WE';
      case DateTime.thursday:
        return 'TH';
      case DateTime.friday:
        return 'FR';
      case DateTime.saturday:
        return 'SA';
      case DateTime.sunday:
        return 'SU';
    }
    return 'MO';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEditingOccurrence = widget.instanceStartMillisUtc != null &&
        _editingEvent != null &&
        _editingEvent!.recurrenceKind != 'none';
    final allowSeriesScope = isEditingOccurrence;
    final recurrenceEditable = !(isEditingOccurrence && _editScope == 'occurrence');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventId == null ? 'Nuevo' : 'Editar'),
        actions: [
          IconButton(
            onPressed: _saveAsTemplate,
            tooltip: 'Guardar como plantilla',
            icon: const Icon(Icons.bookmark_add),
          ),
          IconButton(
            onPressed: _save,
            tooltip: 'Guardar',
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  DropdownButtonFormField<String>(
                    value: _kind,
                    items: const [
                      DropdownMenuItem(value: 'event', child: Text('Evento')),
                      DropdownMenuItem(value: 'task', child: Text('Tarea')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _kind = value;
                        _selectedTemplateId = null;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 12),
                  if (_templates.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedTemplateId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin plantilla')),
                        ..._templates.map(
                          (t) => DropdownMenuItem(value: t.id, child: Text(t.title)),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedTemplateId = value;
                          final t = _templates.where((e) => e.id == value).cast<CalendarEvent?>().firstWhere(
                                (e) => e != null,
                                orElse: () => null,
                              );
                          if (t != null) {
                            _applyTemplate(t);
                          }
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Plantilla'),
                    ),
                  if (_templates.isNotEmpty) const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _day.year,
                          items: List.generate(
                            101,
                            (i) {
                              final y = 2000 + i;
                              return DropdownMenuItem(value: y, child: Text('$y'));
                            },
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(value, _day.month);
                              final nextDay = _day.day > maxDay ? maxDay : _day.day;
                              _day = DateTime(value, _day.month, nextDay);
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Año'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _day.month,
                          items: List.generate(
                            12,
                            (i) {
                              final m = i + 1;
                              return DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')));
                            },
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(_day.year, value);
                              final nextDay = _day.day > maxDay ? maxDay : _day.day;
                              _day = DateTime(_day.year, value, nextDay);
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Mes'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _day.day,
                          items: List.generate(
                            _daysInMonth(_day.year, _day.month),
                            (i) {
                              final d = i + 1;
                              return DropdownMenuItem(value: d, child: Text(d.toString().padLeft(2, '0')));
                            },
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _day = DateTime(_day.year, _day.month, value);
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Día'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_kind == 'event')
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _hour,
                            items: List.generate(
                              24,
                              (i) => DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0'))),
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _hour = value;
                              });
                            },
                            decoration: const InputDecoration(labelText: 'Hora'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _minute,
                            items: List.generate(
                              12,
                              (i) {
                                final m = i * 5;
                                return DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')));
                              },
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _minute = value;
                              });
                            },
                            decoration: const InputDecoration(labelText: 'Minuto'),
                          ),
                        ),
                      ],
                    ),
                  if (_kind == 'event') const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _recurrence,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Sin repetición')),
                      DropdownMenuItem(value: 'daily', child: Text('Diario')),
                      DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                      DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                      DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                    ],
                    onChanged: (value) {
                      if (!recurrenceEditable) return;
                      if (value == null) return;
                      setState(() {
                        _recurrence = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Repetición'),
                  ),
                  if (allowSeriesScope) const SizedBox(height: 12),
                  if (allowSeriesScope)
                    DropdownButtonFormField<String>(
                      value: _editScope,
                      items: const [
                        DropdownMenuItem(value: 'occurrence', child: Text('Solo esta')),
                        DropdownMenuItem(value: 'series', child: Text('Toda la serie')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _editScope = value;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Aplicar cambios'),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _checklistEnabled = !_checklistEnabled;
                            if (!_checklistEnabled) {
                              _checklist = <Map<String, dynamic>>[];
                            } else if (_checklist.isEmpty) {
                              _checklist = <Map<String, dynamic>>[
                                <String, dynamic>{'text': '', 'checked': false},
                              ];
                            }
                          });
                        },
                        tooltip: 'Checklist',
                        icon: Icon(_checklistEnabled ? Icons.checklist : Icons.checklist_rtl, color: scheme.primary),
                      ),
                      Text(_checklistEnabled ? 'Checklist activado' : 'Checklist desactivado'),
                    ],
                  ),
                  if (_checklistEnabled)
                    Column(
                      children: [
                        const SizedBox(height: 8),
                        for (int i = 0; i < _checklist.length; i++)
                          Row(
                            children: [
                              Checkbox(
                                value: _checklist[i]['checked'] == true,
                                onChanged: (v) {
                                  setState(() {
                                    _checklist[i]['checked'] = v == true;
                                  });
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: (_checklist[i]['text'] as String?) ?? '')
                                    ..selection = TextSelection.collapsed(offset: ((_checklist[i]['text'] as String?) ?? '').length),
                                  onChanged: (value) {
                                    _checklist[i]['text'] = value;
                                  },
                                  decoration: InputDecoration(labelText: 'Ítem ${i + 1}'),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _checklist.removeAt(i);
                                  });
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _checklist.add(<String, dynamic>{'text': '', 'checked': false});
                              });
                            },
                            child: const Text('Añadir ítem'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.notifications_active, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text('Alarmas'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _alarms.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _alarms[i]['hour'] ?? 0,
                            items: List.generate(
                              24,
                              (h) => DropdownMenuItem(value: h, child: Text(h.toString().padLeft(2, '0'))),
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _alarms[i]['hour'] = value;
                              });
                            },
                            decoration: const InputDecoration(labelText: 'Hora'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _alarms[i]['minute'] ?? 0,
                            items: List.generate(
                              12,
                              (j) {
                                final m = j * 5;
                                return DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')));
                              },
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _alarms[i]['minute'] = value;
                              });
                            },
                            decoration: const InputDecoration(labelText: 'Minuto'),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _alarms.removeAt(i);
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _alarms.add(<String, int>{'hour': _hour, 'minute': _minute});
                        });
                      },
                      child: const Text('Añadir alarma'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
    );
  }
}

class GoogleCalendarEditorScreen extends StatefulWidget {
  final GoogleCalendarService service;
  final String? calendarId;

  const GoogleCalendarEditorScreen({
    super.key,
    required this.service,
    this.calendarId,
  });

  @override
  State<GoogleCalendarEditorScreen> createState() => _GoogleCalendarEditorScreenState();
}

class _GoogleCalendarEditorScreenState extends State<GoogleCalendarEditorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _timeZoneController = TextEditingController();
  final TextEditingController _colorIdController = TextEditingController();

  bool _loading = true;
  bool _selected = true;
  bool _hidden = false;
  String _defaultReminderMethod = 'popup';
  int _defaultReminderMinutes = 10;
  List<gcal.EventReminder> _defaultReminders = const <gcal.EventReminder>[];

  String? _calendarId;

  @override
  void initState() {
    super.initState();
    _calendarId = widget.calendarId;
    _init();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _timeZoneController.dispose();
    _colorIdController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
    });
    try {
      final id = _calendarId;
      if (id != null) {
        final cal = await widget.service.getCalendar(id, interactive: false);
        final entry = await widget.service.getCalendarListEntry(id, interactive: false);
        _nameController.text = cal.summary ?? entry.summary ?? '';
        _descriptionController.text = cal.description ?? '';
        _locationController.text = cal.location ?? '';
        _timeZoneController.text = cal.timeZone ?? entry.timeZone ?? 'UTC';
        _colorIdController.text = entry.colorId ?? '';
        _selected = entry.selected == true;
        _hidden = entry.hidden == true;
        _defaultReminders = (entry.defaultReminders ?? const <gcal.EventReminder>[])
            .where((r) => (r.minutes ?? 0) > 0)
            .toList();
      } else {
        _timeZoneController.text = 'UTC';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el calendario: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      final timeZone = _timeZoneController.text.trim().isEmpty ? 'UTC' : _timeZoneController.text.trim();
      final calendar = gcal.Calendar(
        summary: name,
        description: _descriptionController.text,
        location: _locationController.text,
        timeZone: timeZone,
      );

      final id = _calendarId;
      final saved = id == null
          ? await widget.service.insertCalendar(calendar, interactive: true)
          : await widget.service.updateCalendar(id, calendar, interactive: true);

      final savedId = saved.id;
      if (savedId != null && savedId.isNotEmpty) {
        _calendarId = savedId;
        final nextColorId = _colorIdController.text.trim();
        final entry = gcal.CalendarListEntry(
          id: savedId,
          selected: _selected,
          hidden: _hidden,
          colorId: nextColorId.isEmpty ? null : nextColorId,
          defaultReminders: _defaultReminders,
        );
        await widget.service.updateCalendarListEntry(savedId, entry, interactive: true);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el calendario: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _delete() async {
    final id = _calendarId;
    if (id == null) return;

    setState(() {
      _loading = true;
    });
    try {
      await widget.service.deleteCalendar(id, interactive: true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el calendario: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _addDefaultReminder() {
    final minutes = _defaultReminderMinutes;
    if (minutes <= 0) return;
    final method = _defaultReminderMethod.trim().isEmpty ? 'popup' : _defaultReminderMethod.trim();
    setState(() {
      _defaultReminders = <gcal.EventReminder>[
        ..._defaultReminders,
        gcal.EventReminder(method: method, minutes: minutes),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _calendarId == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nuevo calendario' : 'Editar calendario'),
        actions: [
          if (!isNew)
            IconButton(
              onPressed: _loading ? null : _delete,
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete),
            ),
          IconButton(
            onPressed: _loading ? null : _save,
            tooltip: 'Guardar',
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Ubicación'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timeZoneController,
                    decoration: const InputDecoration(labelText: 'Time zone (ej: America/Santiago)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _selected,
                          onChanged: (v) => setState(() => _selected = v),
                          title: const Text('Seleccionado'),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          value: _hidden,
                          onChanged: (v) => setState(() => _hidden = v),
                          title: const Text('Oculto'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _colorIdController,
                    decoration: const InputDecoration(labelText: 'Color ID (Google)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _defaultReminderMethod,
                          items: const [
                            DropdownMenuItem(value: 'popup', child: Text('popup')),
                            DropdownMenuItem(value: 'email', child: Text('email')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _defaultReminderMethod = v);
                          },
                          decoration: const InputDecoration(labelText: 'Recordatorio por defecto (método)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _defaultReminderMinutes,
                          items: const [
                            DropdownMenuItem(value: 5, child: Text('5')),
                            DropdownMenuItem(value: 10, child: Text('10')),
                            DropdownMenuItem(value: 15, child: Text('15')),
                            DropdownMenuItem(value: 30, child: Text('30')),
                            DropdownMenuItem(value: 60, child: Text('60')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _defaultReminderMinutes = v);
                          },
                          decoration: const InputDecoration(labelText: 'Minutos'),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _addDefaultReminder,
                      child: const Text('Añadir recordatorio por defecto'),
                    ),
                  ),
                  if (_defaultReminders.isNotEmpty)
                    for (int i = 0; i < _defaultReminders.length; i++)
                      Row(
                        children: [
                          Expanded(
                            child: Text('${_defaultReminders[i].method ?? 'popup'} - ${_defaultReminders[i].minutes ?? 0} min'),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                final next = List<gcal.EventReminder>.from(_defaultReminders);
                                next.removeAt(i);
                                _defaultReminders = next;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
    );
  }
}

class GoogleCalendarEventEditorScreen extends StatefulWidget {
  final GoogleCalendarService service;
  final String calendarId;
  final DateTime initialDay;
  final CalendarEvent? existingEvent;

  const GoogleCalendarEventEditorScreen({
    super.key,
    required this.service,
    required this.calendarId,
    required this.initialDay,
    this.existingEvent,
  });

  @override
  State<GoogleCalendarEventEditorScreen> createState() => _GoogleCalendarEventEditorScreenState();
}

class _GoogleCalendarEventEditorScreenState extends State<GoogleCalendarEventEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _attendeesController = TextEditingController();
  final TextEditingController _colorIdController = TextEditingController();
  final TextEditingController _recurrenceController = TextEditingController();

  bool _loading = true;
  bool _allDay = false;
  DateTime _startDay = DateTime.now();
  DateTime _endDay = DateTime.now();
  int _startHour = 9;
  int _startMinute = 0;
  int _endHour = 10;
  int _endMinute = 0;
  String _visibility = 'default';
  String _transparency = 'opaque';
  bool _useDefaultReminders = true;
  String _reminderMethod = 'popup';
  int _reminderMinutes = 10;
  List<gcal.EventReminder> _reminderOverrides = const <gcal.EventReminder>[];
  String _sendUpdates = 'none';
  bool _guestsCanInviteOthers = true;
  bool _guestsCanModify = false;
  bool _guestsCanSeeOtherGuests = true;

  gcal.Event? _remote;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay;
    _startDay = DateTime(d.year, d.month, d.day);
    _endDay = DateTime(d.year, d.month, d.day);
    _init();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _attendeesController.dispose();
    _colorIdController.dispose();
    _recurrenceController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
    });
    try {
      final existing = widget.existingEvent;
      if (existing != null) {
        final eventId = existing.id;
        final remote = await widget.service.withCalendarApi(
          interactive: false,
          run: (api) => api.events.get(widget.calendarId, eventId),
        );
        _remote = remote;
        _titleController.text = remote.summary ?? existing.title;
        _descriptionController.text = remote.description ?? existing.description;
        _locationController.text = remote.location ?? existing.locationText;
        _colorIdController.text = remote.colorId ?? '';

        final allDay = remote.start?.date != null && remote.start?.dateTime == null;
        _allDay = allDay;
        if (allDay) {
          final s = remote.start?.date?.toLocal() ?? _startDay;
          final e = remote.end?.date?.toLocal() ?? s.add(const Duration(days: 1));
          _startDay = DateTime(s.year, s.month, s.day);
          final endInclusive = e.subtract(const Duration(days: 1));
          _endDay = DateTime(endInclusive.year, endInclusive.month, endInclusive.day);
        } else {
          final s = remote.start?.dateTime?.toLocal();
          final e = remote.end?.dateTime?.toLocal();
          if (s != null) {
            _startDay = DateTime(s.year, s.month, s.day);
            _startHour = s.hour;
            _startMinute = s.minute;
          }
          if (e != null) {
            _endDay = DateTime(e.year, e.month, e.day);
            _endHour = e.hour;
            _endMinute = e.minute;
          } else if (s != null) {
            final fallback = s.add(const Duration(hours: 1));
            _endDay = DateTime(fallback.year, fallback.month, fallback.day);
            _endHour = fallback.hour;
            _endMinute = fallback.minute;
          }
        }

        _visibility = remote.visibility ?? 'default';
        _transparency = remote.transparency ?? 'opaque';

        final reminders = remote.reminders;
        _useDefaultReminders = reminders?.useDefault ?? true;
        _reminderOverrides = (reminders?.overrides ?? const <gcal.EventReminder>[])
            .where((r) => (r.minutes ?? 0) > 0)
            .toList();

        _guestsCanInviteOthers = remote.guestsCanInviteOthers ?? true;
        _guestsCanModify = remote.guestsCanModify ?? false;
        _guestsCanSeeOtherGuests = remote.guestsCanSeeOtherGuests ?? true;

        final attendees = (remote.attendees ?? const <gcal.EventAttendee>[])
            .map((a) => (a.email ?? '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
        _attendeesController.text = attendees.join(', ');

        final rec = remote.recurrence ?? const <String>[];
        _recurrenceController.text = rec.join('\n');
      } else {
        _titleController.text = '';
        _descriptionController.text = '';
        _locationController.text = '';
        _attendeesController.text = '';
        _colorIdController.text = '';
        _recurrenceController.text = '';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el evento: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  DateTime _startLocalDateTime() {
    return DateTime(_startDay.year, _startDay.month, _startDay.day, _startHour, _startMinute);
  }

  DateTime _endLocalDateTime() {
    return DateTime(_endDay.year, _endDay.month, _endDay.day, _endHour, _endMinute);
  }

  void _addReminderOverride() {
    final minutes = _reminderMinutes;
    if (minutes <= 0) return;
    final method = _reminderMethod.trim().isEmpty ? 'popup' : _reminderMethod.trim();
    setState(() {
      _reminderOverrides = <gcal.EventReminder>[
        ..._reminderOverrides,
        gcal.EventReminder(method: method, minutes: minutes),
      ];
    });
  }

  List<gcal.EventAttendee> _parseAttendees() {
    final raw = _attendeesController.text;
    final parts = raw.split(',');
    final emails = parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    return emails.map((email) => gcal.EventAttendee(email: email)).toList();
  }

  List<String>? _parseRecurrence() {
    final raw = _recurrenceController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return raw.isEmpty ? null : raw;
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      gcal.EventDateTime start;
      gcal.EventDateTime end;
      if (_allDay) {
        final s = DateTime.utc(_startDay.year, _startDay.month, _startDay.day);
        final endExclusive = DateTime.utc(_endDay.year, _endDay.month, _endDay.day).add(const Duration(days: 1));
        start = gcal.EventDateTime(date: s);
        end = gcal.EventDateTime(date: endExclusive);
      } else {
        final s = _startLocalDateTime().toUtc();
        var e = _endLocalDateTime().toUtc();
        if (!e.isAfter(s)) {
          e = s.add(const Duration(hours: 1));
        }
        start = gcal.EventDateTime(dateTime: s);
        end = gcal.EventDateTime(dateTime: e);
      }

      final reminders = gcal.EventReminders(
        useDefault: _useDefaultReminders,
        overrides: _useDefaultReminders ? null : _reminderOverrides,
      );

      final event = gcal.Event(
        summary: title,
        description: _descriptionController.text,
        location: _locationController.text,
        start: start,
        end: end,
        visibility: _visibility,
        transparency: _transparency,
        colorId: _colorIdController.text.trim().isEmpty ? null : _colorIdController.text.trim(),
        reminders: reminders,
        attendees: _parseAttendees(),
        recurrence: _parseRecurrence(),
        guestsCanInviteOthers: _guestsCanInviteOthers,
        guestsCanModify: _guestsCanModify,
        guestsCanSeeOtherGuests: _guestsCanSeeOtherGuests,
      );

      final existing = widget.existingEvent;
      if (existing == null) {
        await widget.service.insertEvent(
          calendarId: widget.calendarId,
          event: event,
          sendUpdates: _sendUpdates == 'none' ? null : _sendUpdates,
          interactive: true,
        );
      } else {
        await widget.service.updateEvent(
          calendarId: widget.calendarId,
          eventId: existing.id,
          event: event,
          sendUpdates: _sendUpdates == 'none' ? null : _sendUpdates,
          interactive: true,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el evento: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _delete() async {
    final existing = widget.existingEvent;
    if (existing == null) return;

    setState(() {
      _loading = true;
    });
    try {
      await widget.service.deleteEvent(
        calendarId: widget.calendarId,
        eventId: existing.id,
        sendUpdates: _sendUpdates == 'none' ? null : _sendUpdates,
        interactive: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el evento: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existingEvent == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nuevo evento' : 'Editar evento'),
        actions: [
          if (!isNew)
            IconButton(
              onPressed: _loading ? null : _delete,
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete),
            ),
          IconButton(
            onPressed: _loading ? null : _save,
            tooltip: 'Guardar',
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Ubicación'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _allDay,
                    onChanged: (v) => setState(() => _allDay = v),
                    title: const Text('Todo el día'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _startDay.year,
                          items: List.generate(101, (i) {
                            final y = 2000 + i;
                            return DropdownMenuItem(value: y, child: Text('$y'));
                          }),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(v, _startDay.month);
                              final nextDay = _startDay.day > maxDay ? maxDay : _startDay.day;
                              _startDay = DateTime(v, _startDay.month, nextDay);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Año (inicio)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _startDay.month,
                          items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(_startDay.year, v);
                              final nextDay = _startDay.day > maxDay ? maxDay : _startDay.day;
                              _startDay = DateTime(_startDay.year, v, nextDay);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Mes (inicio)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _startDay.day,
                          items: List.generate(_daysInMonth(_startDay.year, _startDay.month), (i) {
                            final d = i + 1;
                            return DropdownMenuItem(value: d, child: Text('$d'));
                          }),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _startDay = DateTime(_startDay.year, _startDay.month, v);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Día (inicio)'),
                        ),
                      ),
                    ],
                  ),
                  if (!_allDay) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _startHour,
                            items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0')))),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _startHour = v);
                            },
                            decoration: const InputDecoration(labelText: 'Hora (inicio)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _startMinute,
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('00')),
                              DropdownMenuItem(value: 5, child: Text('05')),
                              DropdownMenuItem(value: 10, child: Text('10')),
                              DropdownMenuItem(value: 15, child: Text('15')),
                              DropdownMenuItem(value: 20, child: Text('20')),
                              DropdownMenuItem(value: 30, child: Text('30')),
                              DropdownMenuItem(value: 45, child: Text('45')),
                              DropdownMenuItem(value: 55, child: Text('55')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _startMinute = v);
                            },
                            decoration: const InputDecoration(labelText: 'Minuto (inicio)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _endDay.year,
                          items: List.generate(101, (i) {
                            final y = 2000 + i;
                            return DropdownMenuItem(value: y, child: Text('$y'));
                          }),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(v, _endDay.month);
                              final nextDay = _endDay.day > maxDay ? maxDay : _endDay.day;
                              _endDay = DateTime(v, _endDay.month, nextDay);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Año (fin)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _endDay.month,
                          items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              final maxDay = _daysInMonth(_endDay.year, v);
                              final nextDay = _endDay.day > maxDay ? maxDay : _endDay.day;
                              _endDay = DateTime(_endDay.year, v, nextDay);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Mes (fin)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _endDay.day,
                          items: List.generate(_daysInMonth(_endDay.year, _endDay.month), (i) {
                            final d = i + 1;
                            return DropdownMenuItem(value: d, child: Text('$d'));
                          }),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _endDay = DateTime(_endDay.year, _endDay.month, v);
                              if (_endDay.isBefore(_startDay)) _endDay = _startDay;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Día (fin)'),
                        ),
                      ),
                    ],
                  ),
                  if (!_allDay) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _endHour,
                            items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0')))),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _endHour = v);
                            },
                            decoration: const InputDecoration(labelText: 'Hora (fin)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _endMinute,
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('00')),
                              DropdownMenuItem(value: 5, child: Text('05')),
                              DropdownMenuItem(value: 10, child: Text('10')),
                              DropdownMenuItem(value: 15, child: Text('15')),
                              DropdownMenuItem(value: 20, child: Text('20')),
                              DropdownMenuItem(value: 30, child: Text('30')),
                              DropdownMenuItem(value: 45, child: Text('45')),
                              DropdownMenuItem(value: 55, child: Text('55')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _endMinute = v);
                            },
                            decoration: const InputDecoration(labelText: 'Minuto (fin)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _visibility,
                    items: const [
                      DropdownMenuItem(value: 'default', child: Text('default')),
                      DropdownMenuItem(value: 'public', child: Text('public')),
                      DropdownMenuItem(value: 'private', child: Text('private')),
                      DropdownMenuItem(value: 'confidential', child: Text('confidential')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _visibility = v);
                    },
                    decoration: const InputDecoration(labelText: 'Visibilidad'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _transparency,
                    items: const [
                      DropdownMenuItem(value: 'opaque', child: Text('opaque')),
                      DropdownMenuItem(value: 'transparent', child: Text('transparent')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _transparency = v);
                    },
                    decoration: const InputDecoration(labelText: 'Transparencia'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _colorIdController,
                    decoration: const InputDecoration(labelText: 'Color ID (Google)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _attendeesController,
                    decoration: const InputDecoration(labelText: 'Invitados (emails separados por coma)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _useDefaultReminders,
                          onChanged: (v) => setState(() => _useDefaultReminders = v),
                          title: const Text('Usar recordatorios por defecto'),
                        ),
                      ),
                    ],
                  ),
                  if (!_useDefaultReminders) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _reminderMethod,
                            items: const [
                              DropdownMenuItem(value: 'popup', child: Text('popup')),
                              DropdownMenuItem(value: 'email', child: Text('email')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _reminderMethod = v);
                            },
                            decoration: const InputDecoration(labelText: 'Método'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _reminderMinutes,
                            items: const [
                              DropdownMenuItem(value: 5, child: Text('5')),
                              DropdownMenuItem(value: 10, child: Text('10')),
                              DropdownMenuItem(value: 15, child: Text('15')),
                              DropdownMenuItem(value: 30, child: Text('30')),
                              DropdownMenuItem(value: 60, child: Text('60')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _reminderMinutes = v);
                            },
                            decoration: const InputDecoration(labelText: 'Minutos'),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _addReminderOverride,
                        child: const Text('Añadir recordatorio'),
                      ),
                    ),
                    for (int i = 0; i < _reminderOverrides.length; i++)
                      Row(
                        children: [
                          Expanded(
                            child: Text('${_reminderOverrides[i].method ?? 'popup'} - ${_reminderOverrides[i].minutes ?? 0} min'),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                final next = List<gcal.EventReminder>.from(_reminderOverrides);
                                next.removeAt(i);
                                _reminderOverrides = next;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _sendUpdates,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('none')),
                      DropdownMenuItem(value: 'all', child: Text('all')),
                      DropdownMenuItem(value: 'externalOnly', child: Text('externalOnly')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sendUpdates = v);
                    },
                    decoration: const InputDecoration(labelText: 'Notificar invitados (sendUpdates)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _guestsCanInviteOthers,
                          onChanged: (v) => setState(() => _guestsCanInviteOthers = v),
                          title: const Text('Invitados pueden invitar'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _guestsCanModify,
                          onChanged: (v) => setState(() => _guestsCanModify = v),
                          title: const Text('Invitados pueden modificar'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _guestsCanSeeOtherGuests,
                          onChanged: (v) => setState(() => _guestsCanSeeOtherGuests = v),
                          title: const Text('Invitados ven otros invitados'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recurrenceController,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Recurrencia (una regla por línea: RRULE:...)'),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CalendarListItem {
  final String id;
  final String eventId;
  final int instanceStartMillisUtc;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String source;
  final bool isTask;
  final bool isCompleted;

  _CalendarListItem({
    required this.id,
    required this.eventId,
    required this.instanceStartMillisUtc,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.source,
    required this.isTask,
    required this.isCompleted,
  });
}
