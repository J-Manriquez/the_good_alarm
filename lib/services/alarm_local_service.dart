import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelo_alarm.dart';

class AlarmLocalService {
  static const String alarmsBoxName = 'alarms_box';
  static const String syncBoxName = 'alarm_sync_box';

  static const String _lastPullIsoKey = '_last_pull_iso';

  Box get _alarmsBox => Hive.box(alarmsBoxName);
  Box get _syncBox => Hive.box(syncBoxName);

  Future<void> migrateFromSharedPreferencesIfNeeded() async {
    if (_alarmsBox.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final alarmsString = prefs.getStringList('alarms_list');
    if (alarmsString == null || alarmsString.isEmpty) return;

    for (final s in alarmsString) {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        final alarm = Alarm.fromJson(Map<String, dynamic>.from(decoded));
        await upsertAlarm(alarm);
      }
    }

    await prefs.remove('alarms_list');
  }

  Future<List<Alarm>> getAllAlarms({bool includeDeleted = false}) async {
    final alarms = <Alarm>[];
    for (final entry in _alarmsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final alarm = Alarm.fromJson(Map<String, dynamic>.from(value));
        if (!includeDeleted && alarm.deletedAt != null) continue;
        alarms.add(alarm);
      }
    }
    alarms.sort((a, b) => a.time.compareTo(b.time));
    return alarms;
  }

  Future<Alarm?> getAlarm(int alarmId) async {
    final value = _alarmsBox.get(alarmId.toString());
    if (value is Map) {
      return Alarm.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<void> upsertAlarm(Alarm alarm) async {
    await _alarmsBox.put(alarm.id.toString(), alarm.toJson());
  }

  Future<void> markAlarmDeleted(int alarmId) async {
    final existing = await getAlarm(alarmId);
    if (existing == null) return;
    final updated = existing.copyWith(deletedAt: DateTime.now());
    await upsertAlarm(updated);
    await markDirtyFields(alarmId, {'deletedAt'});
  }

  DateTime? getLastPullTime() {
    final raw = _syncBox.get(_lastPullIsoKey);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> setLastPullTime(DateTime time) async {
    await _syncBox.put(_lastPullIsoKey, time.toIso8601String());
  }

  Future<Set<String>> getDirtyFields(int alarmId) async {
    final state = _getAlarmSyncState(alarmId);
    final raw = state['dirtyFields'];
    if (raw is List) {
      return raw.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<List<int>> getAlarmIdsWithDirtyFields() async {
    final ids = <int>[];
    for (final entry in _syncBox.toMap().entries) {
      final key = entry.key;
      if (key is! String) continue;
      if (key == _lastPullIsoKey) continue;
      final value = entry.value;
      if (value is Map) {
        final dirty = value['dirtyFields'];
        if (dirty is List && dirty.whereType<String>().isNotEmpty) {
          final id = int.tryParse(key);
          if (id != null) ids.add(id);
        }
      }
    }
    return ids;
  }

  Map<String, DateTime?> getBaseFieldUpdatedAt(int alarmId) {
    final state = _getAlarmSyncState(alarmId);
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

  Future<void> markDirtyFields(int alarmId, Set<String> dirtyFields) async {
    if (dirtyFields.isEmpty) return;

    final alarm = await getAlarm(alarmId);
    final baseFieldUpdatedAt = Map<String, DateTime?>.from(getBaseFieldUpdatedAt(alarmId));
    if (alarm?.fieldUpdatedAt != null) {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => alarm!.fieldUpdatedAt![field]);
      }
    } else {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => alarm?.updatedAt);
      }
    }

    final state = _getAlarmSyncState(alarmId);
    final existingDirty = (state['dirtyFields'] is List) ? (state['dirtyFields'] as List).whereType<String>().toSet() : <String>{};
    final mergedDirty = <String>{...existingDirty, ...dirtyFields};

    state['dirtyFields'] = mergedDirty.toList();
    state['baseFieldUpdatedAt'] = baseFieldUpdatedAt.map((k, v) => MapEntry(k, v?.toIso8601String()));
    await _syncBox.put(alarmId.toString(), state);
  }

  Future<void> clearDirty(int alarmId) async {
    final state = _getAlarmSyncState(alarmId);
    state.remove('dirtyFields');
    state.remove('baseFieldUpdatedAt');
    await _syncBox.put(alarmId.toString(), state);
  }

  Future<void> updateAlarmFromCloud(Alarm alarmFromCloud) async {
    final local = await getAlarm(alarmFromCloud.id);
    if (local == null) {
      await upsertAlarm(alarmFromCloud);
      return;
    }
    if (!local.syncToCloud) return;

    final dirty = await getDirtyFields(alarmFromCloud.id);
    if (dirty.isEmpty) {
      await upsertAlarm(alarmFromCloud);
      return;
    }

    final merged = _mergeKeepingDirtyLocal(local, alarmFromCloud, dirty);
    await upsertAlarm(merged);
  }

  Alarm _mergeKeepingDirtyLocal(Alarm local, Alarm remote, Set<String> dirty) {
    final localJson = local.toJson();
    final remoteJson = remote.toJson();

    for (final field in dirty) {
      if (localJson.containsKey(field)) {
        remoteJson[field] = localJson[field];
      }
    }

    return Alarm.fromJson(remoteJson);
  }

  Map<String, dynamic> _getAlarmSyncState(int alarmId) {
    final raw = _syncBox.get(alarmId.toString());
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
