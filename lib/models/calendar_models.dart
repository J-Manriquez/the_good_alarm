import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

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

class CalendarModel {
  final String id;
  final String ownerUid;
  final String name;
  final int colorArgb;
  final String timeZone;
  final String visibility;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  CalendarModel({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.colorArgb,
    required this.timeZone,
    this.visibility = 'private',
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
        'name': name,
        'colorArgb': colorArgb,
        'timeZone': timeZone,
        'visibility': visibility,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory CalendarModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'ownerUid',
      'name',
      'colorArgb',
      'timeZone',
      'visibility',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }
    return CalendarModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFF2196F3,
      timeZone: json['timeZone'] as String? ?? 'UTC',
      visibility: json['visibility'] as String? ?? 'private',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  CalendarModel copyWith({
    String? id,
    String? ownerUid,
    String? name,
    int? colorArgb,
    String? timeZone,
    String? visibility,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return CalendarModel(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      name: name ?? this.name,
      colorArgb: colorArgb ?? this.colorArgb,
      timeZone: timeZone ?? this.timeZone,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ??
          (this.fieldUpdatedAt == null
              ? null
              : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

class CalendarEvent {
  final String id;
  final String calendarId;
  final String title;
  final String description;
  final String locationText;
  final bool allDay;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final String timeZone;
  final String status;
  final String privacy;
  final String recurrenceKind;
  final String? rrule;
  final List<int> exDatesMillisUtc;
  final List<int> rDatesMillisUtc;
  final List<Map<String, dynamic>> reminders;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    this.description = '',
    this.locationText = '',
    this.allDay = false,
    this.startAt,
    this.endAt,
    this.startDate,
    this.endDate,
    this.timeZone = 'UTC',
    this.status = 'confirmed',
    this.privacy = 'default',
    this.recurrenceKind = 'none',
    this.rrule,
    this.exDatesMillisUtc = const [],
    this.rDatesMillisUtc = const [],
    this.reminders = const [],
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'calendarId': calendarId,
        'title': title,
        'description': description,
        'locationText': locationText,
        'allDay': allDay,
        'startAt': startAt?.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'startDate': startDate,
        'endDate': endDate,
        'timeZone': timeZone,
        'status': status,
        'privacy': privacy,
        'recurrenceKind': recurrenceKind,
        'rrule': rrule,
        'exDatesMillisUtc': exDatesMillisUtc,
        'rDatesMillisUtc': rDatesMillisUtc,
        'reminders': reminders,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'calendarId',
      'title',
      'description',
      'locationText',
      'allDay',
      'startAt',
      'endAt',
      'startDate',
      'endDate',
      'timeZone',
      'status',
      'privacy',
      'recurrenceKind',
      'rrule',
      'exDatesMillisUtc',
      'rDatesMillisUtc',
      'reminders',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }
    return CalendarEvent(
      id: json['id'] as String,
      calendarId: json['calendarId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      locationText: json['locationText'] as String? ?? '',
      allDay: json['allDay'] as bool? ?? false,
      startAt: _parseDate(json['startAt']),
      endAt: _parseDate(json['endAt']),
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      timeZone: json['timeZone'] as String? ?? 'UTC',
      status: json['status'] as String? ?? 'confirmed',
      privacy: json['privacy'] as String? ?? 'default',
      recurrenceKind: json['recurrenceKind'] as String? ?? 'none',
      rrule: json['rrule'] as String?,
      exDatesMillisUtc: (json['exDatesMillisUtc'] is List)
          ? (json['exDatesMillisUtc'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      rDatesMillisUtc: (json['rDatesMillisUtc'] is List)
          ? (json['rDatesMillisUtc'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      reminders: (json['reminders'] is List)
          ? (json['reminders'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  CalendarEvent copyWith({
    String? id,
    String? calendarId,
    String? title,
    String? description,
    String? locationText,
    bool? allDay,
    DateTime? startAt,
    DateTime? endAt,
    String? startDate,
    String? endDate,
    String? timeZone,
    String? status,
    String? privacy,
    String? recurrenceKind,
    String? rrule,
    List<int>? exDatesMillisUtc,
    List<int>? rDatesMillisUtc,
    List<Map<String, dynamic>>? reminders,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      description: description ?? this.description,
      locationText: locationText ?? this.locationText,
      allDay: allDay ?? this.allDay,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      timeZone: timeZone ?? this.timeZone,
      status: status ?? this.status,
      privacy: privacy ?? this.privacy,
      recurrenceKind: recurrenceKind ?? this.recurrenceKind,
      rrule: rrule ?? this.rrule,
      exDatesMillisUtc:
          exDatesMillisUtc ?? List<int>.from(this.exDatesMillisUtc),
      rDatesMillisUtc:
          rDatesMillisUtc ?? List<int>.from(this.rDatesMillisUtc),
      reminders: reminders ?? List<Map<String, dynamic>>.from(this.reminders),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ??
          (this.fieldUpdatedAt == null
              ? null
              : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

class CalendarEventOverride {
  final String eventId;
  final String calendarId;
  final int instanceStartMillisUtc;
  final String type;
  final Map<String, dynamic> patch;
  final bool cancelled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  CalendarEventOverride({
    required this.eventId,
    required this.calendarId,
    required this.instanceStartMillisUtc,
    required this.type,
    this.patch = const {},
    this.cancelled = false,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  String get key => '$eventId:$instanceStartMillisUtc';

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'calendarId': calendarId,
        'instanceStartMillisUtc': instanceStartMillisUtc,
        'type': type,
        'patch': patch,
        'cancelled': cancelled,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory CalendarEventOverride.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'eventId',
      'calendarId',
      'instanceStartMillisUtc',
      'type',
      'patch',
      'cancelled',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }
    return CalendarEventOverride(
      eventId: json['eventId'] as String? ?? '',
      calendarId: json['calendarId'] as String? ?? '',
      instanceStartMillisUtc:
          (json['instanceStartMillisUtc'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'modify',
      patch: (json['patch'] is Map)
          ? Map<String, dynamic>.from(json['patch'] as Map)
          : const {},
      cancelled: json['cancelled'] as bool? ?? false,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }

  CalendarEventOverride copyWith({
    String? eventId,
    String? calendarId,
    int? instanceStartMillisUtc,
    String? type,
    Map<String, dynamic>? patch,
    bool? cancelled,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? revision,
    Map<String, DateTime>? fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) {
    return CalendarEventOverride(
      eventId: eventId ?? this.eventId,
      calendarId: calendarId ?? this.calendarId,
      instanceStartMillisUtc:
          instanceStartMillisUtc ?? this.instanceStartMillisUtc,
      type: type ?? this.type,
      patch: patch ?? Map<String, dynamic>.from(this.patch),
      cancelled: cancelled ?? this.cancelled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revision: revision ?? this.revision,
      fieldUpdatedAt: fieldUpdatedAt ??
          (this.fieldUpdatedAt == null
              ? null
              : Map<String, DateTime>.from(this.fieldUpdatedAt!)),
      extras: extras ?? Map<String, dynamic>.from(this.extras),
    );
  }
}

class CalendarOccurrence {
  final String id;
  final String calendarId;
  final String eventId;
  final DateTime instanceStartAt;
  final DateTime instanceEndAt;
  final bool allDay;
  final String status;
  final String titleSnapshot;
  final int colorSnapshotArgb;
  final String source;
  final DateTime? generatedAt;
  final Map<String, dynamic> extras;

  CalendarOccurrence({
    required this.id,
    required this.calendarId,
    required this.eventId,
    required this.instanceStartAt,
    required this.instanceEndAt,
    required this.allDay,
    required this.status,
    required this.titleSnapshot,
    required this.colorSnapshotArgb,
    required this.source,
    this.generatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'calendarId': calendarId,
        'eventId': eventId,
        'instanceStartAt': instanceStartAt.toIso8601String(),
        'instanceEndAt': instanceEndAt.toIso8601String(),
        'allDay': allDay,
        'status': status,
        'titleSnapshot': titleSnapshot,
        'colorSnapshotArgb': colorSnapshotArgb,
        'source': source,
        'generatedAt': generatedAt?.toIso8601String(),
        ...extras,
      };

  factory CalendarOccurrence.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'calendarId',
      'eventId',
      'instanceStartAt',
      'instanceEndAt',
      'allDay',
      'status',
      'titleSnapshot',
      'colorSnapshotArgb',
      'source',
      'generatedAt',
    }) {
      extras.remove(key);
    }
    return CalendarOccurrence(
      id: json['id'] as String,
      calendarId: json['calendarId'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
      instanceStartAt: _parseDate(json['instanceStartAt']) ?? DateTime.now(),
      instanceEndAt: _parseDate(json['instanceEndAt']) ?? DateTime.now(),
      allDay: json['allDay'] as bool? ?? false,
      status: json['status'] as String? ?? 'confirmed',
      titleSnapshot: json['titleSnapshot'] as String? ?? '',
      colorSnapshotArgb: (json['colorSnapshotArgb'] as num?)?.toInt() ?? 0,
      source: json['source'] as String? ?? 'single',
      generatedAt: _parseDate(json['generatedAt']),
      extras: extras,
    );
  }
}

class TaskListModel {
  final String id;
  final String ownerUid;
  final String name;
  final int colorArgb;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  TaskListModel({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.colorArgb,
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
        'name': name,
        'colorArgb': colorArgb,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory TaskListModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'ownerUid',
      'name',
      'colorArgb',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }
    return TaskListModel(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFF4CAF50,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }
}

class TaskItemModel {
  final String id;
  final String taskListId;
  final String title;
  final String notes;
  final String status;
  final DateTime? dueAt;
  final String? dueDate;
  final int priority;
  final List<String> labels;
  final String? rrule;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final Map<String, DateTime>? fieldUpdatedAt;
  final Map<String, dynamic> extras;

  TaskItemModel({
    required this.id,
    required this.taskListId,
    required this.title,
    this.notes = '',
    this.status = 'needsAction',
    this.dueAt,
    this.dueDate,
    this.priority = 0,
    this.labels = const [],
    this.rrule,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.revision = 0,
    this.fieldUpdatedAt,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskListId': taskListId,
        'title': title,
        'notes': notes,
        'status': status,
        'dueAt': dueAt?.toIso8601String(),
        'dueDate': dueDate,
        'priority': priority,
        'labels': labels,
        'rrule': rrule,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'revision': revision,
        'fieldUpdatedAt':
            fieldUpdatedAt?.map((k, v) => MapEntry(k, v.toIso8601String())),
        ...extras,
      };

  factory TaskItemModel.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'id',
      'taskListId',
      'title',
      'notes',
      'status',
      'dueAt',
      'dueDate',
      'priority',
      'labels',
      'rrule',
      'createdAt',
      'updatedAt',
      'deletedAt',
      'revision',
      'fieldUpdatedAt',
    }) {
      extras.remove(key);
    }
    return TaskItemModel(
      id: json['id'] as String,
      taskListId: json['taskListId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? 'needsAction',
      dueAt: _parseDate(json['dueAt']),
      dueDate: json['dueDate'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      labels: (json['labels'] is List)
          ? (json['labels'] as List).whereType<String>().toList()
          : const [],
      rrule: json['rrule'] as String?,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      fieldUpdatedAt: _parseFieldUpdatedAt(json['fieldUpdatedAt']),
      extras: extras,
    );
  }
}

