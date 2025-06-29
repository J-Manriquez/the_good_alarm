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

  // Guardar una alarma en Firebase
  Future<void> saveAlarmToCloud(Alarm alarm, String userId) async {
    try {
      if (!alarm.syncToCloud) return;

      final alarmsCollection = _firestore
.collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      await alarmsCollection.doc(alarm.id.toString()).set(alarm.toJson());
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

      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      await alarmsCollection.doc(alarm.id.toString()).update(alarm.toJson());
    } catch (e) {
      print('Error al actualizar alarma en Firebase: $e');
      rethrow;
    }
  }

  // Eliminar una alarma de Firebase
  Future<void> deleteAlarmToCloud(int alarmId, String userId) async {
    try {
      final alarmsCollection = _firestore
.collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      await alarmsCollection.doc(alarmId.toString()).delete();
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
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      await alarmsCollection.doc(alarmId.toString()).update({
        'isActive': isActive,
      });
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
      final alarmsCollection = _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('alarmas');

      return alarmsCollection.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Alarm.fromJson(data);
        }).toList();
      });
    } catch (e) {
      print('Error al crear stream de alarmas: $e');
      return Stream.value([]);
    }
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
          batch.set(docRef, alarm.toJson());
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
