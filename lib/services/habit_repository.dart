import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit_models.dart';
import 'habit_firebase_service.dart';
import 'habit_local_service.dart';

class HabitCloudBatch {
  final List<HabitModel> effectiveHabits;
  final List<String> deletedIds;

  HabitCloudBatch({
    required this.effectiveHabits,
    required this.deletedIds,
  });
}

class HabitRepository {
  final HabitLocalService _local;
  final HabitFirebaseService _cloud;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _habitsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completionsSub;

  HabitRepository({
    HabitLocalService? local,
    HabitFirebaseService? cloud,
  })  : _local = local ?? HabitLocalService(),
        _cloud = cloud ?? HabitFirebaseService();

  Future<List<HabitModel>> loadLocalHabits({bool includeDeleted = false}) =>
      _local.getAllHabits(includeDeleted: includeDeleted);

  Future<HabitModel?> loadLocalHabit(String habitId) => _local.getHabit(habitId);

  Future<List<HabitCompletionModel>> loadLocalCompletionsForHabit(
    String habitId, {
    bool includeDeleted = false,
    int? limit,
  }) =>
      _local.getCompletionsForHabit(habitId, includeDeleted: includeDeleted, limit: limit);

  Future<void> reconcile({
    required String userId,
  }) async {
    await pullOnce(userId: userId);
    await pushPendingChanges(userId: userId);
  }

  Future<void> pullOnce({
    required String userId,
  }) async {
    final habitsSnap = await _cloud.getHabitsQueryStream(userId).first;
    for (final doc in habitsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= doc.id;
      data['ownerUid'] ??= userId;
      final habit = HabitModel.fromJson(data);
      await _local.upsertHabit(habit);
    }
    await _local.setLastPullHabitsTime(DateTime.now());

    final completionsSnap = await _cloud.getCompletionsQueryStream(userId).first;
    for (final doc in completionsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= doc.id;
      data['ownerUid'] ??= userId;
      final completion = HabitCompletionModel.fromJson(data);
      await _local.upsertCompletion(completion);
    }
    await _local.setLastPullCompletionsTime(DateTime.now());
  }

  Future<void> startCloudSync({
    required String userId,
    Future<void> Function(HabitCloudBatch batch)? onHabitsBatchApplied,
    Future<void> Function()? onCompletionsApplied,
  }) async {
    await stopAllCloudSync();

    _habitsSub = _cloud.getHabitsQueryStream(userId).listen((snapshot) async {
      final effective = <HabitModel>[];
      final deletedIds = <String>[];

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['ownerUid'] ??= userId;
        final habit = HabitModel.fromJson(data);
        final localBefore = await _local.getHabit(habit.id);
        if (localBefore != null && !localBefore.syncToCloud) {
          continue;
        }

        await _local.upsertHabit(habit);
        effective.add(habit);

        final isDeleted = habit.deletedAt != null || habit.extras['deleted'] == true;
        if (isDeleted) deletedIds.add(habit.id);
      }

      await _local.setLastPullHabitsTime(DateTime.now());
      await _persistBootRestorePayload();
      if (onHabitsBatchApplied != null && (effective.isNotEmpty || deletedIds.isNotEmpty)) {
        await onHabitsBatchApplied(HabitCloudBatch(effectiveHabits: effective, deletedIds: deletedIds));
      }
    });

    _completionsSub = _cloud.getCompletionsQueryStream(userId).listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= doc.id;
        data['ownerUid'] ??= userId;
        final completion = HabitCompletionModel.fromJson(data);
        await _local.upsertCompletion(completion);
      }
      await _local.setLastPullCompletionsTime(DateTime.now());
      if (onCompletionsApplied != null) {
        await onCompletionsApplied();
      }
    });
  }

  Future<void> stopAllCloudSync() async {
    await _habitsSub?.cancel();
    _habitsSub = null;
    await _completionsSub?.cancel();
    _completionsSub = null;
  }

  Future<void> upsertHabit({
    required HabitModel habit,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getHabit(habit.id);
    final now = DateTime.now();
    final normalized = habit.copyWith(
      updatedAt: now,
      createdAt: habit.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertHabit(normalized);
    await _persistBootRestorePayload();

    final dirtyFields = _diffTopLevelFields(existing?.toJson(), normalized.toJson());
    await _local.markDirtyFields(
      entityType: 'habit',
      entityId: normalized.id,
      dirtyFields: dirtyFields,
      updatedAtFallback: normalized.updatedAt,
      fieldUpdatedAt: normalized.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null && normalized.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> deleteHabit({
    required String habitId,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getHabit(habitId);
    if (existing == null) return;
    final updated = existing.copyWith(deletedAt: DateTime.now(), updatedAt: DateTime.now());
    await _local.upsertHabit(updated);
    await _persistBootRestorePayload();
    await _local.markDirtyFields(
      entityType: 'habit',
      entityId: habitId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );

    if (cloudSyncEnabled && userId != null && existing.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> upsertCompletion({
    required HabitCompletionModel completion,
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
    final dirtyFields = _diffTopLevelFields(existing?.toJson(), normalized.toJson());
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

  Future<void> pushPendingChanges({
    required String userId,
  }) async {
    final deviceId = await _getDeviceId();

    final habitIds = await _local.getEntityIdsWithDirtyFields('habit');
    for (final habitId in habitIds) {
      final habit = await _local.getHabit(habitId);
      if (habit == null) {
        await _local.clearDirty('habit', habitId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields('habit', habitId);
      if (dirtyFields.isEmpty) continue;

      if (!habit.syncToCloud) {
        await _local.clearDirty('habit', habitId);
        continue;
      }

      final baseFieldUpdatedAt = _local.getBaseFieldUpdatedAt('habit', habitId);
      final patch = _buildPatchFromJson(habit.toJson(), dirtyFields);
      await _cloud.applyHabitPatch(
        userId: userId,
        habitId: habitId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );

      await _local.clearDirty('habit', habitId);
    }

    final completionIds = await _local.getEntityIdsWithDirtyFields('completion');
    for (final completionId in completionIds) {
      final completion = await _local.getCompletion(completionId);
      if (completion == null) {
        await _local.clearDirty('completion', completionId);
        continue;
      }

      await _cloud.upsertCompletion(userId: userId, completion: completion, deviceId: deviceId);
      await _local.clearDirty('completion', completionId);
    }
  }

  Set<String> _diffTopLevelFields(Map<String, dynamic>? oldJson, Map<String, dynamic> newJson) {
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

  Map<String, dynamic> _buildPatchFromJson(Map<String, dynamic> json, Set<String> dirtyFields) {
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
    if (deviceName != null && deviceName.trim().isNotEmpty) return deviceName.trim();
    return 'dispositivo_sin_nombre';
  }

  Future<void> _persistBootRestorePayload() async {
    final prefs = await SharedPreferences.getInstance();
    final habits = await _local.getAllHabits();

    final payload = habits
        .where((h) => h.isActive && h.deletedAt == null && h.nextScheduledAtLocal != null)
        .map((h) {
          final whenLocal = h.nextScheduledAtLocal!;
          final dateKey =
              '${whenLocal.year.toString().padLeft(4, '0')}${whenLocal.month.toString().padLeft(2, '0')}${whenLocal.day.toString().padLeft(2, '0')}';
          final timeKey =
              '${whenLocal.hour.toString().padLeft(2, '0')}${whenLocal.minute.toString().padLeft(2, '0')}';
          final occurrenceKey = '${h.id}|$dateKey|$timeKey';
          return <String, dynamic>{
            'habitId': h.id,
            'occurrenceKey': occurrenceKey,
            'title': h.title,
            'message': h.description,
            'timeInMillis': whenLocal.millisecondsSinceEpoch,
          };
        })
        .toList();

    await prefs.setString('habits', jsonEncode(payload));
  }
}

