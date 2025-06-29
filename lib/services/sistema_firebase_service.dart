import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sistema_model.dart';

class SistemaFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Obtener el documento sistema para un usuario
  Future<SistemaModel?> getSistema(String userId) async {
    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('usuario-sistema')
          .doc('sistema')
          .get();

      if (doc.exists) {
        return SistemaModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error al obtener sistema: $e');
      return null;
    }
  }

  // Crear o actualizar el documento sistema
  Future<void> setSistema(String userId, SistemaModel sistema) async {
    try {
      await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('usuario-sistema')
          .doc('sistema')
          .set(sistema.toMap());
    } catch (e) {
      print('Error al guardar sistema: $e');
      throw e;
    }
  }

  // Añadir un dispositivo al sistema
  Future<void> addDevice(String userId, String deviceName, bool isActive) async {
    try {
      final sistema = await getSistema(userId);
      if (sistema != null) {
        sistema.addDevice(deviceName, isActive);
        await setSistema(userId, sistema);
      } else {
        // Crear nuevo documento sistema
        final newSistema = SistemaModel(usuarios: [
          {
            'usuario': deviceName,
            'isActive': isActive,
          }
        ]);
        await setSistema(userId, newSistema);
      }
    } catch (e) {
      print('Error al añadir dispositivo: $e');
      throw e;
    }
  }

  // Actualizar el estado de un dispositivo
  Future<void> updateDeviceStatus(String userId, String deviceName, bool isActive) async {
    try {
      final sistema = await getSistema(userId);
      if (sistema != null) {
        sistema.updateDeviceStatus(deviceName, isActive);
        await setSistema(userId, sistema);
      }
    } catch (e) {
      print('Error al actualizar estado del dispositivo: $e');
      throw e;
    }
  }

  // Actualizar el estado de un dispositivo por deviceId
  Future<void> updateDeviceActiveState(String userId, String deviceId, bool isActive) async {
    try {
      final sistema = await getSistema(userId);
      if (sistema != null) {
        final updatedUsuarios = sistema.usuarios.map((user) {
          if (user['deviceId'] == deviceId) {
            return {...user, 'isActive': isActive};
          }
          return user;
        }).toList();
        
        final updatedSistema = sistema.copyWith(usuarios: updatedUsuarios);
        await setSistema(userId, updatedSistema);
      }
    } catch (e) {
      print('Error al actualizar estado del dispositivo: $e');
      throw e;
    }
  }

  // Eliminar un dispositivo del sistema
  Future<void> removeDevice(String userId, String deviceName) async {
    try {
      final sistema = await getSistema(userId);
      if (sistema != null) {
        sistema.removeDevice(deviceName);
        await setSistema(userId, sistema);
      }
    } catch (e) {
      print('Error al eliminar dispositivo: $e');
      throw e;
    }
  }

  // Verificar si un dispositivo existe
  Future<bool> deviceExists(String userId, String deviceName) async {
    try {
      final sistema = await getSistema(userId);
      return sistema?.hasDevice(deviceName) ?? false;
    } catch (e) {
      print('Error al verificar dispositivo: $e');
      return false;
    }
  }
}