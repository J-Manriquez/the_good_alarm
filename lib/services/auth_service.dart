import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Obtener usuario actual
  User? get currentUser => _auth.currentUser;

  // Stream de cambios de autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Registrar usuario
  Future<UserModel?> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      // Crear usuario en Firebase Auth
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Crear ID único usando nombre + fecha
        DateTime now = DateTime.now();
        // String userId = '${name.toLowerCase().replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}';

        // Crear modelo de usuario
        UserModel userModel = UserModel(
          id: userCredential.user!.uid,
          name: name,
          email: email,
          creationDate: now,
          isActive: false,
        );

        // Crear colección del usuario en Firestore
        await _createUserCollection(userCredential.user!.uid, userModel);

        return userModel;
      }
    } catch (e) {
      print('Error al registrar usuario: $e');
      rethrow;
    }
    return null;
  }

  // Iniciar sesión
  Future<User?> signInUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      print('Error al iniciar sesión: $e');
      rethrow;
    }
  }

  // Cerrar sesión
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('Error al cerrar sesión: $e');
      rethrow;
    }
  }

  // Crear colección del usuario en Firestore
  Future<void> _createUserCollection(String userId, UserModel userModel) async {
    try {
      // Crear la colección con el ID del usuario
      await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('usuario-sistema')
          .doc('datos-usuario')
          .set(userModel.toMap());
    } catch (e) {
      print('Error al crear colección del usuario: $e');
      rethrow;
    }
  }

  // Obtener datos del usuario desde Firestore
  Future<UserModel?> getUserData(String userId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('usuario-sistema')
          .doc('datos-usuario')
          .get();

      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      print('Error al obtener datos del usuario: $e');
    }
    return null;
  }

  // Actualizar estado de activación del usuario
  Future<void> updateUserActiveStatus(String userId, bool isActive) async {
    try {
      await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('usuario-sistema')
          .doc('datos-usuario')
          .update({'isActive': isActive});
    } catch (e) {
      print('Error al actualizar estado del usuario: $e');
      rethrow;
    }
  }

  // Obtener ID del usuario basado en email (para buscar su colección)
  Future<String?> getUserIdByEmail(String email) async {
    try {
      // Buscar en todas las colecciones que contengan datos_usuario
      QuerySnapshot collections = await _firestore.collectionGroup('datos_usuario').get();
      
      for (QueryDocumentSnapshot doc in collections.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data['email'] == email) {
          return data['id'];
        }
      }
    } catch (e) {
      print('Error al buscar usuario por email: $e');
    }
    return null;
  }
}