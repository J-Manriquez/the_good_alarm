import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_theme_model.dart';

class AppThemeFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _themesCollection(String userId) {
    return _firestore.collection('usuarios').doc(userId).collection('temas');
  }

  Stream<List<AppThemeModel>> watchThemes(String userId) {
    return _themesCollection(userId).snapshots().map((snap) {
      return snap.docs.map((d) {
        final data = d.data();
        return AppThemeModel.fromMap({...data, 'id': d.id});
      }).toList();
    });
  }

  Future<void> upsertTheme({
    required String userId,
    required AppThemeModel theme,
    required String deviceId,
  }) async {
    final ref = _themesCollection(userId).doc(theme.id);
    await ref.set({
      ...theme.toMap(),
      'updatedByDevice': deviceId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
    }, SetOptions(merge: true));
  }

  Future<void> deleteTheme({
    required String userId,
    required String themeId,
    required String deviceId,
  }) async {
    final ref = _themesCollection(userId).doc(themeId);
    await ref.delete();
  }
}
