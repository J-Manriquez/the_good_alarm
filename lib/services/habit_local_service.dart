import 'package:hive/hive.dart';

import '../models/habit_models.dart';

class HabitLocalService {
  static const String habitsBoxName = 'habits_box';
  static const String completionsBoxName = 'habit_completions_box';
  static const String syncBoxName = 'habit_sync_box';

  static const String _lastPullHabitsIsoKey = '_last_pull_habits_iso';
  static const String _lastPullCompletionsIsoKey = '_last_pull_completions_iso';

  Box get _habitsBox => Hive.box(habitsBoxName);
  Box get _completionsBox => Hive.box(completionsBoxName);
  Box get _syncBox => Hive.box(syncBoxName);

  DateTime? getLastPullHabitsTime() => _getLastPull(_lastPullHabitsIsoKey);
  DateTime? getLastPullCompletionsTime() => _getLastPull(_lastPullCompletionsIsoKey);

  Future<void> setLastPullHabitsTime(DateTime time) => _setLastPull(_lastPullHabitsIsoKey, time);
  Future<void> setLastPullCompletionsTime(DateTime time) =>
      _setLastPull(_lastPullCompletionsIsoKey, time);

  DateTime? _getLastPull(String key) {
    final raw = _syncBox.get(key);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> _setLastPull(String key, DateTime time) async {
    await _syncBox.put(key, time.toIso8601String());
  }

  String _syncKey(String entityType, String entityId) => '$entityType:$entityId';

  Future<Set<String>> getDirtyFields(String entityType, String entityId) async {
    final state = _getSyncState(entityType, entityId);
    final raw = state['dirtyFields'];
    if (raw is List) return raw.whereType<String>().toSet();
    return <String>{};
  }

  Map<String, DateTime?> getBaseFieldUpdatedAt(String entityType, String entityId) {
    final state = _getSyncState(entityType, entityId);
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

  Future<void> markDirtyFields({
    required String entityType,
    required String entityId,
    required Set<String> dirtyFields,
    DateTime? updatedAtFallback,
    Map<String, DateTime>? fieldUpdatedAt,
  }) async {
    if (dirtyFields.isEmpty) return;

    final baseFieldUpdatedAt =
        Map<String, DateTime?>.from(getBaseFieldUpdatedAt(entityType, entityId));
    if (fieldUpdatedAt != null) {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => fieldUpdatedAt[field]);
      }
    } else {
      for (final field in dirtyFields) {
        baseFieldUpdatedAt.putIfAbsent(field, () => updatedAtFallback);
      }
    }

    final state = _getSyncState(entityType, entityId);
    final existingDirty = (state['dirtyFields'] is List)
        ? (state['dirtyFields'] as List).whereType<String>().toSet()
        : <String>{};
    final mergedDirty = <String>{...existingDirty, ...dirtyFields};

    state['dirtyFields'] = mergedDirty.toList();
    state['baseFieldUpdatedAt'] =
        baseFieldUpdatedAt.map((k, v) => MapEntry(k, v?.toIso8601String()));
    await _syncBox.put(_syncKey(entityType, entityId), state);
  }

  Future<void> clearDirty(String entityType, String entityId) async {
    final state = _getSyncState(entityType, entityId);
    state.remove('dirtyFields');
    state.remove('baseFieldUpdatedAt');
    await _syncBox.put(_syncKey(entityType, entityId), state);
  }

  Future<List<String>> getEntityIdsWithDirtyFields(String entityType) async {
    final ids = <String>[];
    for (final entry in _syncBox.toMap().entries) {
      final key = entry.key;
      if (key is! String) continue;
      if (!key.startsWith('$entityType:')) continue;
      final value = entry.value;
      if (value is Map) {
        final dirty = value['dirtyFields'];
        if (dirty is List && dirty.whereType<String>().isNotEmpty) {
          ids.add(key.substring(entityType.length + 1));
        }
      }
    }
    return ids;
  }

  Map<String, dynamic> _getSyncState(String entityType, String entityId) {
    final raw = _syncBox.get(_syncKey(entityType, entityId));
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<void> upsertHabit(HabitModel habit) async {
    await _habitsBox.put(habit.id, habit.toJson());
  }

  Future<HabitModel?> getHabit(String habitId) async {
    final value = _habitsBox.get(habitId);
    if (value is Map) {
      return HabitModel.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<HabitModel>> getAllHabits({bool includeDeleted = false}) async {
    final habits = <HabitModel>[];
    for (final entry in _habitsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final habit = HabitModel.fromJson(Map<String, dynamic>.from(value));
        if (!includeDeleted && habit.deletedAt != null) continue;
        habits.add(habit);
      }
    }
    habits.sort((a, b) => a.title.compareTo(b.title));
    return habits;
  }

  Future<void> markHabitDeleted(String habitId) async {
    final existing = await getHabit(habitId);
    if (existing == null) return;
    final updated = existing.copyWith(deletedAt: DateTime.now(), updatedAt: DateTime.now());
    await upsertHabit(updated);
    await markDirtyFields(
      entityType: 'habit',
      entityId: habitId,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );
  }

  Future<void> upsertCompletion(HabitCompletionModel completion) async {
    await _completionsBox.put(completion.id, completion.toJson());
  }

  Future<HabitCompletionModel?> getCompletion(String completionId) async {
    final value = _completionsBox.get(completionId);
    if (value is Map) {
      return HabitCompletionModel.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<HabitCompletionModel>> getCompletionsForHabit(
    String habitId, {
    bool includeDeleted = false,
    int? limit,
  }) async {
    final items = <HabitCompletionModel>[];
    for (final entry in _completionsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final c = HabitCompletionModel.fromJson(Map<String, dynamic>.from(value));
        if (c.habitId != habitId) continue;
        if (!includeDeleted && c.deletedAt != null) continue;
        items.add(c);
      }
    }
    items.sort((a, b) => b.scheduledAtLocal.compareTo(a.scheduledAtLocal));
    if (limit != null && items.length > limit) {
      return items.take(limit).toList(growable: false);
    }
    return items;
  }
}

