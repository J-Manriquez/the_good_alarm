import 'package:hive/hive.dart';

import '../models/medication_models.dart';

class MedicationLocalService {
  static const String medicationsBoxName = 'medications_box';
  static const String completionsBoxName = 'medication_completions_box';
  static const String syncBoxName = 'medication_sync_box';

  static const String _lastPullMedicationsIsoKey = '_last_pull_medications_iso';
  static const String _lastPullCompletionsIsoKey =
      '_last_pull_med_completions_iso';

  Box get _medicationsBox => Hive.box(medicationsBoxName);
  Box get _completionsBox => Hive.box(completionsBoxName);
  Box get _syncBox => Hive.box(syncBoxName);

  // ── Tiempos de pull ──────────────────────────────────────

  DateTime? getLastPullMedicationsTime() =>
      _getLastPull(_lastPullMedicationsIsoKey);
  DateTime? getLastPullCompletionsTime() =>
      _getLastPull(_lastPullCompletionsIsoKey);

  Future<void> setLastPullMedicationsTime(DateTime time) =>
      _setLastPull(_lastPullMedicationsIsoKey, time);
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

  // ── Dirty fields ─────────────────────────────────────────

  String _syncKey(String entityType, String entityId) =>
      '$entityType:$entityId';

  Future<Set<String>> getDirtyFields(
      String entityType, String entityId) async {
    final state = _getSyncState(entityType, entityId);
    final raw = state['dirtyFields'];
    if (raw is List) return raw.whereType<String>().toSet();
    return <String>{};
  }

  Map<String, DateTime?> getBaseFieldUpdatedAt(
      String entityType, String entityId) {
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

  Future<List<String>> getEntityIdsWithDirtyFields(
      String entityType) async {
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

  Map<String, dynamic> _getSyncState(
      String entityType, String entityId) {
    final raw = _syncBox.get(_syncKey(entityType, entityId));
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  // ── CRUD Medicamentos ────────────────────────────────────

  Future<void> upsertMedication(MedicationModel med) async {
    await _medicationsBox.put(med.id, med.toJson());
  }

  Future<MedicationModel?> getMedication(String id) async {
    final value = _medicationsBox.get(id);
    if (value is Map) {
      return MedicationModel.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<MedicationModel>> getAllMedications(
      {bool includeDeleted = false}) async {
    final list = <MedicationModel>[];
    for (final entry in _medicationsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final med =
            MedicationModel.fromJson(Map<String, dynamic>.from(value));
        if (!includeDeleted && med.deletedAt != null) continue;
        list.add(med);
      }
    }
    list.sort((a, b) => a.medicationName.compareTo(b.medicationName));
    return list;
  }

  Future<void> markMedicationDeleted(String id) async {
    final existing = await getMedication(id);
    if (existing == null) return;
    final updated = existing.copyWith(
        deletedAt: DateTime.now(), updatedAt: DateTime.now());
    await upsertMedication(updated);
    await markDirtyFields(
      entityType: 'medication',
      entityId: id,
      dirtyFields: {'deletedAt'},
      updatedAtFallback: updated.updatedAt,
      fieldUpdatedAt: updated.fieldUpdatedAt,
    );
  }

  // ── CRUD Completions ─────────────────────────────────────

  Future<void> upsertCompletion(
      MedicationCompletionModel completion) async {
    await _completionsBox.put(completion.id, completion.toJson());
  }

  Future<MedicationCompletionModel?> getCompletion(
      String completionId) async {
    final value = _completionsBox.get(completionId);
    if (value is Map) {
      return MedicationCompletionModel.fromJson(
          Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<List<MedicationCompletionModel>> getCompletionsForMedication(
    String medicationId, {
    bool includeDeleted = false,
    int? limit,
  }) async {
    final items = <MedicationCompletionModel>[];
    for (final entry in _completionsBox.toMap().entries) {
      final value = entry.value;
      if (value is Map) {
        final c = MedicationCompletionModel.fromJson(
            Map<String, dynamic>.from(value));
        if (c.medicationId != medicationId) continue;
        if (!includeDeleted && c.deletedAt != null) continue;
        items.add(c);
      }
    }
    items.sort(
        (a, b) => b.scheduledAtLocal.compareTo(a.scheduledAtLocal));
    if (limit != null && items.length > limit) {
      return items.take(limit).toList(growable: false);
    }
    return items;
  }

  Future<MedicationCompletionModel?> getCompletionForOccurrence(
      String occurrenceKey) async {
    return getCompletion(occurrenceKey);
  }
}
