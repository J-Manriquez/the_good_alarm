import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/calendar_models.dart';

class CalendarFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _userCalendarRefs(String userId) {
    return _firestore
        .collection('usuarios')
        .doc(userId)
        .collection('calendarios_ref');
  }

  CollectionReference<Map<String, dynamic>> get _calendarsCollection {
    return _firestore.collection('calendarios');
  }

  CollectionReference<Map<String, dynamic>> _eventsCollection(String calendarId) {
    return _calendarsCollection.doc(calendarId).collection('eventos');
  }

  CollectionReference<Map<String, dynamic>> _overridesCollection(
    String calendarId,
    String eventId,
  ) {
    return _eventsCollection(calendarId).doc(eventId).collection('overrides');
  }

  Map<String, dynamic> _stripCloudMetadata(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json);
    data.remove('createdAt');
    data.remove('updatedAt');
    data.remove('deletedAt');
    data.remove('revision');
    data.remove('fieldUpdatedAt');
    return data;
  }

  Map<String, dynamic> _initialFieldUpdatedAtForData(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final key in data.keys) {
      result[key] = FieldValue.serverTimestamp();
    }
    return result;
  }

  Future<CalendarModel> ensureDefaultCalendarForUser({
    required String userId,
    required String deviceId,
  }) async {
    final refsSnap = await _userCalendarRefs(userId).limit(1).get();
    if (refsSnap.docs.isNotEmpty) {
      final firstId = refsSnap.docs.first.id;
      final calSnap = await _calendarsCollection.doc(firstId).get();
      if (calSnap.exists) {
        final data = calSnap.data() ?? <String, dynamic>{};
        data['id'] ??= calSnap.id;
        return CalendarModel.fromJson(data);
      }
    }

    final newCalendarRef = _calendarsCollection.doc();
    final calendarId = newCalendarRef.id;

    final calendar = CalendarModel(
      id: calendarId,
      ownerUid: userId,
      name: 'Mi calendario',
      colorArgb: 0xFF2196F3,
      timeZone: 'UTC',
      visibility: 'private',
    );

    final data = _stripCloudMetadata(calendar.toJson());
    await newCalendarRef.set({
      ...data,
      'id': calendarId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByDevice': deviceId,
      'revision': 1,
      'deletedAt': null,
      'fieldUpdatedAt': _initialFieldUpdatedAtForData(data),
    }, SetOptions(merge: true));

    await newCalendarRef.collection('miembros').doc(userId).set({
      'uid': userId,
      'role': 'owner',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
    }, SetOptions(merge: true));

    await _userCalendarRefs(userId).doc(calendarId).set({
      'calendarId': calendarId,
      'role': 'owner',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
    }, SetOptions(merge: true));

    return calendar;
  }

  Future<List<String>> getCalendarIdsForUser(String userId) async {
    final snap = await _userCalendarRefs(userId).get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<List<CalendarModel>> getCalendarsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final calendars = <CalendarModel>[];
    for (final id in ids) {
      final snap = await _calendarsCollection.doc(id).get();
      if (!snap.exists) continue;
      final data = snap.data() ?? <String, dynamic>{};
      data['id'] ??= snap.id;
      calendars.add(CalendarModel.fromJson(data));
    }
    return calendars;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getEventsQueryStream(String calendarId) {
    return _eventsCollection(calendarId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getOverridesQueryStream(
    String calendarId,
    String eventId,
  ) {
    return _overridesCollection(calendarId, eventId).snapshots();
  }

  Future<void> applyCalendarPatch({
    required String calendarId,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    final docRef = _calendarsCollection.doc(calendarId);
    await _applyPatchTransaction(
      docRef: docRef,
      patch: patch,
      baseFieldUpdatedAt: baseFieldUpdatedAt,
      deviceId: deviceId,
    );
  }

  Future<void> applyEventPatch({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    final docRef = _eventsCollection(calendarId).doc(eventId);
    await _applyPatchTransaction(
      docRef: docRef,
      patch: patch,
      baseFieldUpdatedAt: baseFieldUpdatedAt,
      deviceId: deviceId,
    );
  }

  Future<void> applyOverridePatch({
    required String calendarId,
    required String eventId,
    required String overrideId,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    final docRef = _overridesCollection(calendarId, eventId).doc(overrideId);
    await _applyPatchTransaction(
      docRef: docRef,
      patch: patch,
      baseFieldUpdatedAt: baseFieldUpdatedAt,
      deviceId: deviceId,
    );
  }

  Future<void> _applyPatchTransaction({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final exists = snap.exists;
      final remote = exists ? (snap.data() ?? <String, dynamic>{}) : <String, dynamic>{};

      final remoteRevision = (remote['revision'] as num?)?.toInt() ?? 0;
      final remoteFieldUpdatedAtRaw = remote['fieldUpdatedAt'];
      final remoteFieldUpdatedAt = <String, Timestamp>{};
      if (remoteFieldUpdatedAtRaw is Map) {
        remoteFieldUpdatedAtRaw.forEach((k, v) {
          if (k is String && v is Timestamp) {
            remoteFieldUpdatedAt[k] = v;
          }
        });
      }

      final updates = <String, dynamic>{};
      final fieldUpdatedAtUpdates = <String, dynamic>{};

      for (final entry in patch.entries) {
        final field = entry.key;
        final newValue = entry.value;

        final base = baseFieldUpdatedAt[field];
        final remoteUpdated = remoteFieldUpdatedAt[field]?.toDate();
        final remoteValue = remote[field];

        if (base != null &&
            remoteUpdated != null &&
            remoteUpdated.isAfter(base) &&
            remoteValue != newValue) {
          final changeRef = docRef.collection('cambios').doc();
          tx.set(changeRef, {
            'field': field,
            'remoteValue': remoteValue,
            'incomingValue': newValue,
            'baseFieldUpdatedAt': base.toIso8601String(),
            'remoteFieldUpdatedAt': remoteUpdated.toIso8601String(),
            'deviceId': deviceId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        updates[field] = newValue;
        fieldUpdatedAtUpdates['fieldUpdatedAt.$field'] = FieldValue.serverTimestamp();
      }

      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedByDevice'] = deviceId;
      updates['revision'] = remoteRevision + 1;
      updates.addAll(fieldUpdatedAtUpdates);

      if (!exists) {
        updates['createdAt'] = FieldValue.serverTimestamp();
        if (!updates.containsKey('deletedAt')) {
          updates['deletedAt'] = null;
        }
      }

      tx.set(docRef, updates, SetOptions(merge: true));
    });
  }
}

