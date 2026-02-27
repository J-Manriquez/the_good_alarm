import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models/calendar_models.dart';
import 'services/calendar_repository.dart';

class CalendarScreen extends StatefulWidget {
  final bool embedInShell;

  const CalendarScreen({super.key, this.embedInShell = false});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarRepository _repo = CalendarRepository();

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

    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid;
    _userId = userId;

    if (userId == null) {
      setState(() {
        _loading = false;
        _calendars = const [];
        _events = const [];
      });
      return;
    }

    await _repo.reconcile(userId: userId);
    await _reloadLocal();
    _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month, 1);
    await _refreshMonthData();

    final calendarId = _selectedCalendarId;
    if (calendarId != null) {
      await _repo.startEventsCloudSync(
        calendarId: calendarId,
        onBatchApplied: (_) async {
          if (!mounted) return;
          await _reloadLocal();
          await _refreshMonthData();
        },
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
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

    final occurrences = await _repo.loadLocalOccurrencesForCalendarInWindow(
      calendarId: calendarId,
      windowStart: windowStartUtc,
      windowEnd: windowEndUtc,
    );

    final overridesByEventId = <String, Map<int, CalendarEventOverride>>{};
    final occEventIds = occurrences.map((o) => o.eventId).toSet();
    for (final eventId in occEventIds) {
      final overrides = await _repo.loadLocalOverridesForEvent(eventId);
      final map = <int, CalendarEventOverride>{};
      for (final ov in overrides) {
        map[ov.instanceStartMillisUtc] = ov;
      }
      overridesByEventId[eventId] = map;
    }

    final eventIsTaskById = <String, bool>{
      for (final e in _events)
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

    for (final e in _events) {
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
    final userId = _userId;
    final calendarId = _selectedCalendarId;
    if (userId == null || calendarId == null) return;

    setState(() {
      _createFabExpanded = false;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CalendarEventEditorScreen(
          userId: userId,
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

  Future<void> _toggleTaskCompletion(_CalendarListItem item, bool next) async {
    final userId = _userId;
    final calendarId = _selectedCalendarId;
    if (userId == null || calendarId == null) return;
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
        cloudSyncEnabled: true,
        userId: userId,
      );
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
        cloudSyncEnabled: true,
        userId: userId,
      );
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
    final fab = _selectedCalendarId == null || _userId == null
        ? null
        : SizedBox(
            width: 56,
            height: _createFabExpanded ? 190 : 56,
            child: Stack(
              alignment: Alignment.bottomRight,
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
                  Positioned(
                    bottom: 70,
                    right: 0,
                    child: FloatingActionButton.small(
                      heroTag: 'calendar_create_task_fab',
                      backgroundColor: scheme.primary,
                      onPressed: () => _openEditor(kind: 'task'),
                      child: Icon(Icons.task_alt, color: scheme.onPrimary),
                    ),
                  ),
                  Positioned(
                    bottom: 130,
                    right: 0,
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

    final body = _loading
        ? Center(child: CircularProgressIndicator(color: scheme.primary))
        : _userId == null
            ? Center(
                child: Text(
                  'Inicia sesión para usar el calendario',
                  style: TextStyle(color: scheme.onSurface),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
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
                                  await _repo.stopAllCloudSync();
                                  setState(() {
                                    _selectedCalendarId = value;
                                  });
                                  await _reloadLocal();
                                  await _repo.startEventsCloudSync(
                                    calendarId: value,
                                    onBatchApplied: (_) async {
                                      if (!mounted) return;
                                      await _reloadLocal();
                                      await _refreshMonthData();
                                    },
                                  );
                                  await _refreshMonthData();
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
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              'Sin eventos para este día',
                              style: TextStyle(color: scheme.onSurface),
                            ),
                          )
                        : ListView.builder(
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
                                    instanceStartMillisUtc: i.source == 'occurrence'
                                        ? i.instanceStartMillisUtc
                                        : null,
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
            if (fab == null) return body;
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

            return Stack(
              children: [
                body,
                Positioned(
                  left: clamped.dx,
                  top: clamped.dy,
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
        if (fab == null) {
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

        return Stack(
          children: [
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: body,
            ),
            Positioned(
              left: clamped.dx,
              top: clamped.dy,
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
                        if (preview.isNotEmpty) ...[
                          const SizedBox(height: 4),
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
  String? _userId;
  String? _calendarId;
  String _kind = 'event';
  DateTime _day = DateTime.now();
  int _hour = 9;
  int _minute = 0;
  String _recurrence = 'none';

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
    final userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    _userId = userId;

    final calendarId = widget.calendarId ??
        (await _repo.ensureDefaultCalendar(userId: userId)).id;
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

  Future<void> _save() async {
    final userId = _userId;
    final calendarId = _calendarId;
    if (userId == null || calendarId == null) return;

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

    if (editingEvent != null && instanceMillisUtc != null) {
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
        cloudSyncEnabled: true,
        userId: userId,
      );
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

    final event = CalendarEvent(
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
      createdAt: editingEvent?.createdAt ?? now,
      updatedAt: now,
      deletedAt: null,
      revision: editingEvent?.revision ?? 0,
      fieldUpdatedAt: editingEvent?.fieldUpdatedAt,
      extras: <String, dynamic>{
        ...editingEvent?.extras ?? const <String, dynamic>{},
        ...baseExtras,
        'isTemplate': false,
      },
    );

    await _repo.upsertEvent(
      event: event,
      cloudSyncEnabled: true,
      userId: userId,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _saveAsTemplate() async {
    final userId = _userId;
    final calendarId = _calendarId;
    if (userId == null || calendarId == null) return;
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
      cloudSyncEnabled: true,
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
                      if (value == null) return;
                      setState(() {
                        _recurrence = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Repetición'),
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
