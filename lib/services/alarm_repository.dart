import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelo_alarm.dart';
import 'alarm_firebase_service.dart';
import 'alarm_local_service.dart';

class AlarmCloudBatch {
  final List<Alarm> effectiveAlarms;
  final List<int> deletedIds;

  AlarmCloudBatch({
    required this.effectiveAlarms,
    required this.deletedIds,
  });
}

class AlarmRepository {
  final AlarmLocalService _local;
  final AlarmFirebaseService _cloud;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cloudSubscription;

  AlarmRepository({
    AlarmLocalService? local,
    AlarmFirebaseService? cloud,
  })  : _local = local ?? AlarmLocalService(),
        _cloud = cloud ?? AlarmFirebaseService();

  Future<void> ensureMigrated() async {
    await _local.migrateFromSharedPreferencesIfNeeded();
    await _persistBootRestorePayload();
  }

  Future<List<Alarm>> loadLocalAlarms({bool includeDeleted = false}) =>
      _local.getAllAlarms(includeDeleted: includeDeleted);

  Future<List<Alarm>> pullOnce({
    required String userId,
  }) async {
    final snapshot = await _cloud.getAlarmsQueryStream(userId).first;
    final alarms = <Alarm>[];
    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= int.tryParse(doc.id) ?? (data['id'] as int?);
      final alarm = Alarm.fromJson(data);
      await _local.updateAlarmFromCloud(alarm);
      alarms.add(alarm);
    }
    await _local.setLastPullTime(DateTime.now());
    await _persistBootRestorePayload();
    return alarms;
  }

  Future<void> reconcile({
    required String userId,
  }) async {
    await ensureMigrated();
    await pullOnce(userId: userId);
    await pushPendingChanges(userId: userId);
  }

  Future<void> startCloudSync({
    required String userId,
    Future<void> Function(AlarmCloudBatch batch)? onBatchApplied,
  }) async {
    await stopCloudSync();
    _cloudSubscription = _cloud.getAlarmsQueryStream(userId).listen((snapshot) async {
      final effective = <Alarm>[];
      final deletedIds = <int>[];

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] ??= int.tryParse(doc.id) ?? (data['id'] as int?);
        final alarm = Alarm.fromJson(data);
        final localBefore = await _local.getAlarm(alarm.id);
        if (localBefore != null && !localBefore.syncToCloud) {
          continue;
        }

        await _local.updateAlarmFromCloud(alarm);
        final merged = await _local.getAlarm(alarm.id) ?? alarm;
        effective.add(merged);

        final isDeleted = merged.deletedAt != null || merged.extras['deleted'] == true;
        if (isDeleted) {
          deletedIds.add(merged.id);
        }
      }
      await _local.setLastPullTime(DateTime.now());

      if (onBatchApplied != null && (effective.isNotEmpty || deletedIds.isNotEmpty)) {
        await onBatchApplied(AlarmCloudBatch(effectiveAlarms: effective, deletedIds: deletedIds));
      }

      if (effective.isNotEmpty || deletedIds.isNotEmpty) {
        await _persistBootRestorePayload();
      }
    });
  }

  Future<void> stopCloudSync() async {
    await _cloudSubscription?.cancel();
    _cloudSubscription = null;
  }

  Future<void> upsertAlarm({
    required Alarm alarm,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getAlarm(alarm.id);
    final now = DateTime.now();
    final normalized = alarm.copyWith(
      updatedAt: now,
      createdAt: alarm.createdAt ?? existing?.createdAt ?? now,
      deletedAt: null,
    );

    await _local.upsertAlarm(normalized);
    await _persistBootRestorePayload();

    final dirtyFields = _diffTopLevelFields(existing, normalized);
    await _local.markDirtyFields(alarm.id, dirtyFields);

    if (cloudSyncEnabled && userId != null && normalized.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> deleteAlarm({
    required int alarmId,
    required bool cloudSyncEnabled,
    required String? userId,
  }) async {
    final existing = await _local.getAlarm(alarmId);
    if (existing == null) return;

    final updated = existing.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _local.upsertAlarm(updated);
    await _persistBootRestorePayload();
    await _local.markDirtyFields(alarmId, {'deletedAt'});

    if (cloudSyncEnabled && userId != null && existing.syncToCloud) {
      await pushPendingChanges(userId: userId);
    }
  }

  Future<void> pushPendingChanges({
    required String userId,
  }) async {
    final deviceId = await _getDeviceId();
    final ids = await _local.getAlarmIdsWithDirtyFields();

    for (final alarmId in ids) {
      final alarm = await _local.getAlarm(alarmId);
      if (alarm == null) {
        await _local.clearDirty(alarmId);
        continue;
      }

      final dirtyFields = await _local.getDirtyFields(alarmId);
      if (dirtyFields.isEmpty) continue;

      if (!alarm.syncToCloud) {
        await _local.clearDirty(alarmId);
        continue;
      }

      final baseFieldUpdatedAt = _local.getBaseFieldUpdatedAt(alarmId);

      final patch = _buildPatchFromAlarm(alarm, dirtyFields);
      await _cloud.applyAlarmPatch(
        userId: userId,
        alarmId: alarmId,
        patch: patch,
        baseFieldUpdatedAt: baseFieldUpdatedAt,
        deviceId: deviceId,
      );

      await _local.clearDirty(alarmId);
    }
  }

  Set<String> _diffTopLevelFields(Alarm? oldAlarm, Alarm newAlarm) {
    if (oldAlarm == null) {
      return _buildComparableJson(newAlarm).keys.toSet();
    }

    final oldJson = _buildComparableJson(oldAlarm);
    final newJson = _buildComparableJson(newAlarm);

    final keys = <String>{...oldJson.keys, ...newJson.keys};
    final changed = <String>{};
    for (final key in keys) {
      if (oldJson[key] != newJson[key]) {
        changed.add(key);
      }
    }
    return changed;
  }

  Map<String, dynamic> _buildComparableJson(Alarm alarm) {
    final json = Map<String, dynamic>.from(alarm.toJson());
    json.remove('createdAt');
    json.remove('updatedAt');
    json.remove('revision');
    json.remove('fieldUpdatedAt');
    return json;
  }

  Map<String, dynamic> _buildPatchFromAlarm(Alarm alarm, Set<String> dirtyFields) {
    final json = _buildComparableJson(alarm);
    final patch = <String, dynamic>{};
    for (final field in dirtyFields) {
      if (json.containsKey(field)) {
        patch[field] = json[field];
      }
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
    final alarms = await _local.getAllAlarms();

    final payload = alarms
        .where((a) => a.isActive && a.deletedAt == null)
        .map((a) => <String, dynamic>{
              'id': a.id,
              'title': a.title,
              'message': a.message,
              'isActive': a.isActive,
              'repeatDays': a.repeatDays,
              'isDaily': a.isDaily,
              'isWeekly': a.isWeekly,
              'isWeekend': a.isWeekend,
              'maxSnoozes': a.maxSnoozes,
              'snoozeDurationMinutes': a.snoozeDurationMinutes,
              'hour': a.time.hour,
              'minute': a.time.minute,
              'maxVolumePercent': a.maxVolumePercent,
              'volumeRampUpDurationSeconds': a.volumeRampUpDurationSeconds,
              'tempVolumeReductionPercent': a.tempVolumeReductionPercent,
              'tempVolumeReductionDurationSeconds': a.tempVolumeReductionDurationSeconds,
            })
        .toList();

    await prefs.setString('alarms', jsonEncode(payload));
  }
}
