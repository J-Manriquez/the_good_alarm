import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/medication_models.dart';

class MedicationFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _currentDeviceId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  CollectionReference<Map<String, dynamic>> _medicationsCollection(
      String userId) {
    return _firestore
        .collection('usuarios')
        .doc(userId)
        .collection('medicamentos');
  }

  CollectionReference<Map<String, dynamic>> _completionsCollection(
      String userId) {
    return _firestore
        .collection('usuarios')
        .doc(userId)
        .collection('medication_completions');
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

  Map<String, dynamic> _initialFieldUpdatedAtForData(
      Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final key in data.keys) {
      result[key] = FieldValue.serverTimestamp();
    }
    return result;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getMedicationsStream(
      String userId) {
    return _medicationsCollection(userId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getCompletionsStream(
      String userId) {
    return _completionsCollection(userId).snapshots();
  }

  Future<void> applyMedicationPatch({
    required String userId,
    required String medicationId,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    final docRef = _medicationsCollection(userId).doc(medicationId);
    await _applyPatchTransaction(
      docRef: docRef,
      patch: patch,
      baseFieldUpdatedAt: baseFieldUpdatedAt,
      deviceId: deviceId,
    );
  }

  Future<void> upsertCompletion({
    required String userId,
    required MedicationCompletionModel completion,
    required String deviceId,
  }) async {
    try {
      final docRef = _completionsCollection(userId).doc(completion.id);
      final data = _stripCloudMetadata(completion.toJson());
      await docRef.set({
        ...data,
        'id': completion.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByDevice': deviceId,
        'revision': FieldValue.increment(1),
        'deletedAt': null,
        'fieldUpdatedAt': _initialFieldUpdatedAtForData(data),
      }, SetOptions(merge: true));
      print('[MedicationFirebase] upsertCompletion OK: ${completion.id}');
    } catch (e) {
      print('[MedicationFirebase] upsertCompletion error: $e');
      rethrow;
    }
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
      final remote =
          exists ? (snap.data() ?? <String, dynamic>{}) : <String, dynamic>{};

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
          continue;
        }
        updates[field] = newValue;
        fieldUpdatedAtUpdates['fieldUpdatedAt.$field'] =
            FieldValue.serverTimestamp();
      }

      if (updates.isEmpty) return;

      tx.set(
        docRef,
        {
          ...updates,
          ...fieldUpdatedAtUpdates,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByDevice': deviceId,
          'revision': remoteRevision + 1,
          if (!exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
