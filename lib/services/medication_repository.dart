import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import 'medication_firebase_service.dart';
import 'medication_local_service.dart';

class MedicationCloudBatch {
  final List<MedicationModel> effectiveMedications;
  final List<String> deletedIds;

  MedicationCloudBatch({
    required this.effectiveMedications,
    required this.deletedIds,
  });
}

class MedicationRepository {
  final MedicationLocalService _local;
  final MedicationFirebaseService _cloud;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medicationsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completionsSub;

  MedicationRepository({
    MedicationLocalService? local,
    MedicationFirebaseService? cloud,
  })  : _local = local ?? MedicationLocalService(),
        _cloud = cloud ?? MedicationFirebaseService();

  Future<List<MedicationModel>> loadLocalMedications(
          {bool includeDeleted = false}) =>
      _local.getAllMedications(includeDeleted: includeDeleted);

  Future<MedicationModel?> loadLocalMedication(String medicationId) =>
      _local.getMedication(medicationId);

  Future<List<MedicationCompletionModel>> loadLocalCompletionsForMedication(
    String medicationId, {
    bool includeDeleted = false,
    int? limit,
  }) =>
      _local.getCompletionsForMedication(medicationId,
          includeDeleted: includeDeleted, limit: limit);

  Future<MedicationCompletionModel?> getCompletionForOccurrence(
          String occurrenceKey) =>
      _local.getCompletionForOccurrence(occurrenceKey);

  Future<void> reconcile({required String userId}) async {
    await pullOnce(userId: userId);
    await pushPendingChanges(userId: userId);
  }

  Future<void> pullOnce({required String userId}) async {
    final medsSnap =
        await _cloud.getMedicationsStream(userId).first;
    for (final doc in medsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= doc.id;
      data['ownerUid'] ??= userId;
      final med = MedicationModel.fromJson(data);
      await _local.upsertMedication(med);
    }

    final completionsSnap =
        await _cloud.getCompletionsStream(userId).first;
    for (final doc in completionsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= doc.id;
      data['ownerUid'] ??= userId;
      final completion = MedicationCompletionModel.fromJson(data);
      await _local.upsertCompletion(completion);
    }
  }

  Future<void> startCloudSync({
    required String userId,
    Future<void> Function(MedicationCloudBatch batch)? onMedicationsBatchApplied,
    Future<void> Function()? onCompletionsApplied,
  }) async {
    await stopAllCloudSync();

    _medicationsSub =
        _cloud.getMedicationsStream(userId).listen((snapshot) async {
      final effective = <MedicationModel>[];
      final deletedIds = <String>[];

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['ownerUid'] ??= userId;
        final med = MedicationModel.fromJson(data);
        final localBefore = await _local.getMedication(med.id);
        if (localBefore != null && !localBefore.syncToCloud) continue;

        await _local.upsertMedication(med);
        effective.add(med);

        final isDeleted =
            med.deletedAt != null || med.extras['deleted'] == true;
        if (isDeleted) deletedIds.add(med.id);
      }

      await _persistBootRestorePayload();
      if (onMedicationsBatchApplied != null &&
          (effective.isNotEmpty || deletedIds.isNotEmpty)) {
        await onMedicationsBatchApplied(
          MedicationCloudBatch(
              effectiveMedications: effective, deletedIds: deletedIds),
        );
      }
    });

    _completionsSub =
        _cloud.getCompletionsStream(userId).listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['ownerUid'] ??= userId;
        final completion = MedicationCompletionModel.fromJson(data);
        await _local.upsertCompletion(completion);
      }
      if (onCompletionsApplied != null) {
        await onCompletionsApplied();
      }
    });
  }

  Future<void> stopAllCloudSync() async {
    await _medicationsSub?.cancel();
    _medicationsSub = null;
    await _completionsSub?.cancel();
    _completionsSub = null;
  }

  Future<void> upsertMedication({
    required MedicationModel medication,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getMedication(medication.id);
    final now = DateTime.now();
    final normalized = medication.copyWith(
      updatedAt: now,
      createdAt: medication.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertMedication(normalized);
    await _persistBootRestorePayload();

    final dirtyFields =
        _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'medication',
      entityId: normalized.id,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null && normalized.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> deleteMedication({
    required String medicationId,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getMedication(medicationId);
    if (existing == null) return;
    final updated = existing.copyWith(
        deletedAt: DateTime.now(), updatedAt: DateTime.now());
    await _local.upsertMedication(updated);
    await _persistBootRestorePayload();
    await _local.markDirtyFields(
      entityType: 'medication',
      entityId: medicationId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null && existing.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> upsertCompletion({
    required MedicationCompletionModel completion,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getCompletion(completion.id);
    final now = DateTime.now();
    final normalized = completion.copyWith(
      updatedAt: now,
      createdAt: completion.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertCompletion(normalized);
    final dirtyFields =
        _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'completion',
      entityId: normalized.id,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> pushPendingChanges({required String userId}) async {
    final deviceId = await _getDeviceId();

    final medicationIds =
        await _local.getEntityIdsWithDirtyFields('medication');
    for (final medicationId in medicationIds) {
      final med = await _local.getMedication(medicationId);
      if (med == null) {
        await _local.clearDirty('medication', medicationId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields('medication', medicationId);
      if (dirtyFields.isEmpty) continue;

      if (!med.syncToCloud) {
        await _local.clearDirty('medication', medicationId);
        continue;
      }

      final baseFieldUpdatedAt =
          _local.getBaseFieldUpdatedAt('medication', medicationId);
      final patch = _buildPatchFromJson(med.toJson(), dirtyFields);
      await _cloud.applyMedicationPatch(
        userId: userId,
        medicationId: medicationId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );

      await _local.clearDirty('medication', medicationId);
    }

    final completionIds =
        await _local.getEntityIdsWithDirtyFields('completion');
    for (final completionId in completionIds) {
      final completion = await _local.getCompletion(completionId);
      if (completion == null) {
        await _local.clearDirty('completion', completionId);
        continue;
      }

      await _cloud.upsertCompletion(
          userId: userId, completion: completion, deviceId: deviceId);
      await _local.clearDirty('completion', completionId);
    }
  }

  Set<String> _diffTopLevelFields(
      Map<String, dynamic>? oldJson, Map<String, dynamic> newJson) {
    if (oldJson == null) {
      return _buildComparableJson(newJson).keys.toSet();
    }
    final o = _buildComparableJson(oldJson);
    final n = _buildComparableJson(newJson);
    final keys = <String>{...o.keys, ...n.keys};
    final changed = <String>{};
    for (final key in keys) {
      if (o[key] != n[key]) changed.add(key);
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

  Map<String, dynamic> _buildPatchFromJson(
      Map<String, dynamic> json, Set<String> dirtyFields) {
    final comparable = _buildComparableJson(json);
    final patch = <String, dynamic>{};
    for (final field in dirtyFields) {
      if (comparable.containsKey(field)) patch[field] = comparable[field];
    }
    return patch;
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_name');
    if (deviceName != null && deviceName.trim().isNotEmpty) {
      return deviceName.trim();
    }
    return 'dispositivo_sin_nombre';
  }

  Future<void> _persistBootRestorePayload() async {
    final prefs = await SharedPreferences.getInstance();
    final meds = await _local.getAllMedications();

    final payload = meds
        .where((m) =>
            m.isActive &&
            m.deletedAt == null &&
            m.nextScheduledAtLocal != null)
        .map((m) {
          final whenLocal = m.nextScheduledAtLocal!;
          final dateKey =
              '${whenLocal.year.toString().padLeft(4, '0')}${whenLocal.month.toString().padLeft(2, '0')}${whenLocal.day.toString().padLeft(2, '0')}';
          final timeKey =
              '${whenLocal.hour.toString().padLeft(2, '0')}${whenLocal.minute.toString().padLeft(2, '0')}';
          final occurrenceKey = 'med|${m.id}|$dateKey|$timeKey';
          return <String, dynamic>{
            'medicationId': m.id,
            'occurrenceKey': occurrenceKey,
            'title': m.medicationName,
            'message': m.instructions.isEmpty ? '' : m.instructions,
            'timeInMillis': whenLocal.millisecondsSinceEpoch,
            'dosageAmount': m.dosageAmount,
            'dosageUnit': m.dosageUnit,
            'confirmationDelayMinutes': m.confirmationDelayMinutes,
          };
        })
        .toList();

    await prefs.setString('medications', jsonEncode(payload));
  }
}
