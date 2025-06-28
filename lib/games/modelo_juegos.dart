
class GameConfig {
  final GameType gameType;
  final int lives; // 0 = infinitas, 1, 3, 5
  final int parameter; // ecuaciones/pares/longitud secuencia
  final int repetitions;
  // Parámetros específicos para ecuaciones
  final EquationInputType inputType;
  final EquationOperationType operationType;
  final int subEquations;

  GameConfig({
    required this.gameType,
    required this.lives,
    required this.parameter,
    required this.repetitions,
    this.inputType = EquationInputType.manual,
    this.operationType = EquationOperationType.addSubtract,
    this.subEquations = 1,
  });

  Map<String, dynamic> toJson() => {
    'gameType': gameType.toString(),
    'lives': lives,
    'parameter': parameter,
    'repetitions': repetitions,
    'inputType': inputType.toString(),
    'operationType': operationType.toString(),
    'subEquations': subEquations,
  };

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig(
    gameType: GameType.values.firstWhere(
      (e) => e.toString() == json['gameType'],
      orElse: () => GameType.memorice,
    ),
    lives: json['lives'] as int? ?? json['difficulty'] as int? ?? 0,
    parameter: json['parameter'] as int,
    repetitions: json['repetitions'] as int,
    inputType: json['inputType'] != null 
        ? EquationInputType.values.firstWhere(
            (e) => e.toString() == json['inputType'],
            orElse: () => EquationInputType.manual,
          )
        : EquationInputType.manual,
    operationType: json['operationType'] != null
        ? EquationOperationType.values.firstWhere(
            (e) => e.toString() == json['operationType'],
            orElse: () => EquationOperationType.addSubtract,
          )
        : EquationOperationType.addSubtract,
    subEquations: json['subEquations'] as int? ?? 1,
  );

  String get gameTitle {
    switch (gameType) {
      case GameType.memorice:
        return 'Memorice';
      case GameType.equations:
        return 'Ecuaciones';
      case GameType.sequence:
        return 'Secuencia';
    }
  }

  String get parameterLabel {
    switch (gameType) {
      case GameType.memorice:
        return '$parameter pares';
      case GameType.equations:
        return '$parameter ecuaciones';
      case GameType.sequence:
        return 'Secuencia de $parameter';
    }
  }

  String get livesLabel {
    if (lives == 0) return 'Infinitas vidas';
    return '$lives ${lives == 1 ? 'vida' : 'vidas'}';
  }
}

enum GameType { memorice, equations, sequence }

enum EquationInputType { manual, multipleChoice }

enum EquationOperationType { 
  addSubtract, 
  addSubtractMultiplyDivide, 
  multiplyDivide 
}
