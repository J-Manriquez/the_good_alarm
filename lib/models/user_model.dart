class UserModel {
  final String id;
  final String name;
  final String email;
  final DateTime creationDate;
  final bool isActive;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.creationDate,
    this.isActive = false,
  });

  // Convertir a Map para Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'creationDate': creationDate.toIso8601String(),
      'isActive': isActive,
    };
  }

  // Crear desde Map de Firestore
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      creationDate: DateTime.parse(map['creationDate']),
      isActive: map['isActive'] ?? false,
    );
  }

  // Crear copia con cambios
  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    DateTime? creationDate,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      creationDate: creationDate ?? this.creationDate,
      isActive: isActive ?? this.isActive,
    );
  }
}