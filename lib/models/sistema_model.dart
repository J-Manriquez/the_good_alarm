class SistemaModel {
  final List<Map<String, dynamic>> usuarios;

  SistemaModel({
    required this.usuarios,
  });

  // Convertir a Map para Firestore
  Map<String, dynamic> toMap() {
    return {
      'usuarios': usuarios,
    };
  }

  // Crear desde Map de Firestore
  factory SistemaModel.fromMap(Map<String, dynamic> map) {
    return SistemaModel(
      usuarios: List<Map<String, dynamic>>.from(map['usuarios'] ?? []),
    );
  }

  // Crear copia con cambios
  SistemaModel copyWith({
    List<Map<String, dynamic>>? usuarios,
  }) {
    return SistemaModel(
      usuarios: usuarios ?? this.usuarios,
    );
  }

  // Métodos de utilidad para manejar dispositivos
  bool hasDevice(String deviceName) {
    return usuarios.any((device) => device['usuario'] == deviceName);
  }

  void addDevice(String deviceName, bool isActive, {bool cloudSyncEnabled = false}) {
    if (!hasDevice(deviceName)) {
      usuarios.add({
        'usuario': deviceName,
        'isActive': isActive,
        '_cloudSyncEnabled': cloudSyncEnabled,
      });
    }
  }

  void updateDeviceStatus(String deviceName, bool isActive) {
    final index = usuarios.indexWhere((device) => device['usuario'] == deviceName);
    if (index != -1) {
      usuarios[index]['isActive'] = isActive;
    }
  }

  void updateDeviceCloudSync(String deviceName, bool cloudSyncEnabled) {
    final index = usuarios.indexWhere((device) => device['usuario'] == deviceName);
    if (index != -1) {
      usuarios[index]['_cloudSyncEnabled'] = cloudSyncEnabled;
    }
  }

  void removeDevice(String deviceName) {
    usuarios.removeWhere((device) => device['usuario'] == deviceName);
  }
}