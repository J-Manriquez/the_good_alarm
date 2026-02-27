import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../modelo_alarm.dart';
import '../services/auth_service.dart';

class AlarmFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Obtener el ID del usuario actual
  String? get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  // Obtener referencia a la colección de alarmas del usuario
  CollectionReference? _getAlarmsCollection(String userId) {
    return _firestore.collection('usuarios').doc(userId).collection('alarmas');
  }

  CollectionReference<Map<String, dynamic>> _alarmsCollection(String userId) {
    return _firestore.collection('usuarios').doc(userId).collection('alarmas');
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

  Map<String, dynamic> _initialFieldUpdatedAtForData(Map<String, dynamic> alarmData) {
    final result = <String, dynamic>{};
    for (final key in alarmData.keys) {
      result[key] = FieldValue.serverTimestamp();
    }
    return result;
  }

  // Guardar una alarma en Firebase
  Future<void> saveAlarmToCloud(Alarm alarm, String userId) async {
    try {
      if (!alarm.syncToCloud) return;

      final alarmsCollection = _alarmsCollection(userId);
      final alarmData = _stripCloudMetadata(alarm.toJson());
      await alarmsCollection.doc(alarm.id.toString()).set({
        ...alarmData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByDevice': _currentUserId,
        'revision': 1,
        'deletedAt': null,
        'fieldUpdatedAt': _initialFieldUpdatedAtForData(alarmData),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error al guardar alarma en Firebase: $e');
      rethrow;
    }
  }

  // Actualizar una alarma en Firebase
  Future<void> updateAlarmToCloud(Alarm alarm, String userId) async {
    try {
      if (!alarm.syncToCloud) {
        // Si la alarma ya no debe sincronizarse, eliminarla de Firebase
        await deleteAlarmToCloud(alarm.id, userId);
        return;
      }

      final alarmsCollection = _alarmsCollection(userId);
      final alarmData = _stripCloudMetadata(alarm.toJson());
      await alarmsCollection.doc(alarm.id.toString()).set({
        ...alarmData,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByDevice': _currentUserId,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error al actualizar alarma en Firebase: $e');
      rethrow;
    }
  }

  // Eliminar una alarma de Firebase
  Future<void> deleteAlarmToCloud(int alarmId, String userId) async {
    try {
      final alarmsCollection = _alarmsCollection(userId);
      await alarmsCollection.doc(alarmId.toString()).set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByDevice': _currentUserId,
        'deleted': true,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error al eliminar alarma de Firebase: $e');
      rethrow;
    }
  }

  // Cambiar estado activo/inactivo de una alarma
  Future<void> toggleAlarmStatus(
    int alarmId,
    bool isActive,
    String userId,
  ) async {
    try {
      final alarmsCollection = _alarmsCollection(userId);
      await alarmsCollection.doc(alarmId.toString()).set({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByDevice': _currentUserId,
        'fieldUpdatedAt': {'isActive': FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error al cambiar estado de alarma en Firebase: $e');
      rethrow;
    }
  }

  // Obtener todas las alarmas del usuario desde Firebase
  Future<List<Alarm>> getUserAlarms(String userId) async {
    try {
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      final querySnapshot = await alarmsCollection.get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Alarm.fromJson(data);
      }).toList();
    } catch (e) {
      print('Error al obtener alarmas de Firebase: $e');
      return [];
    }
  }

  // Stream para escuchar cambios en las alarmas
  Stream<List<Alarm>> getAlarmsStream(String userId) {
    try {
      final alarmsCollection = _alarmsCollection(userId);

      return alarmsCollection.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return Alarm.fromJson(data);
        }).toList();
      });
    } catch (e) {
      print('Error al crear stream de alarmas: $e');
      return Stream.value([]);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getAlarmsQueryStream(String userId) {
    return _alarmsCollection(userId).snapshots();
  }

  Future<void> applyAlarmPatch({
    required String userId,
    required int alarmId,
    required Map<String, dynamic> patch,
    required Map<String, DateTime?> baseFieldUpdatedAt,
    required String deviceId,
  }) async {
    final alarmsCollection = _alarmsCollection(userId);
    final docRef = alarmsCollection.doc(alarmId.toString());

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

        if (base != null && remoteUpdated != null && remoteUpdated.isAfter(base) && remoteValue != newValue) {
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

  // Sincronizar todas las alarmas locales con Firebase
  Future<void> syncAllAlarms(
    List<Alarm> localAlarms,
    String userId,
  ) async {
    try {
      final batch = _firestore.batch();
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      for (final alarm in localAlarms) {
        if (alarm.syncToCloud) {
          final docRef = alarmsCollection.doc(alarm.id.toString());
          final alarmData = _stripCloudMetadata(alarm.toJson());
          batch.set(docRef, {
            ...alarmData,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByDevice': _currentUserId,
            'deletedAt': null,
            'deleted': false,
          }, SetOptions(merge: true));
        }
      }

      await batch.commit();
    } catch (e) {
      print('Error al sincronizar alarmas: $e');
      rethrow;
    }
  }

  // Verificar si una alarma existe en Firebase
  Future<bool> alarmExists(int alarmId, String userId) async {
    try {
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      final doc = await alarmsCollection.doc(alarmId.toString()).get();
      return doc.exists;
    } catch (e) {
      print('Error al verificar existencia de alarma: $e');
      return false;
    }
  }

  // Limpiar todas las alarmas de Firebase (útil para testing)
  Future<void> clearAllAlarms(String userId) async {
    try {
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      final querySnapshot = await alarmsCollection.get();
      final batch = _firestore.batch();

      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('Error al limpiar alarmas de Firebase: $e');
      rethrow;
    }
  }
}
