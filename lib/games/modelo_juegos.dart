
class GameConfig {
  final GameType gameType;
  final int lives; // 0 = infinitas, 1, 3, 5
  final int parameter; // ecuaciones/pares/longitud secuencia
  final int repetitions;
  // Parámetros específicos para ecuaciones
  final EquationInputType inputType;
  final EquationOperationType operationType;
  final int subEquations;
  final Map<String, dynamic> extras;

  GameConfig({
    required this.gameType,
    required this.lives,
    required this.parameter,
    required this.repetitions,
    this.inputType = EquationInputType.manual,
    this.operationType = EquationOperationType.addSubtract,
    this.subEquations = 1,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
    'gameType': gameType.toString(),
    'lives': lives,
    'parameter': parameter,
    'repetitions': repetitions,
    'inputType': inputType.toString(),
    'operationType': operationType.toString(),
    'subEquations': subEquations,
    ...extras,
  };

  factory GameConfig.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json);
    for (final key in <String>{
      'gameType',
      'lives',
      'difficulty',
      'parameter',
      'repetitions',
      'inputType',
      'operationType',
      'subEquations',
    }) {
      extras.remove(key);
    }

    final parsedGameType = GameType.values.firstWhere(
      (e) => e.toString() == json['gameType'],
      orElse: () => GameType.memorice,
    );

    final parsedLives =
        (json['lives'] as num?)?.toInt() ?? (json['difficulty'] as num?)?.toInt() ?? 0;

    final maxParameter = switch (parsedGameType) {
      GameType.memorice => 10,
      GameType.equations => 20,
      GameType.sequence => 20,
    };

    final parsedParameter =
        ((json['parameter'] as num?)?.toInt() ?? 5).clamp(1, maxParameter);
    final parsedRepetitions =
        ((json['repetitions'] as num?)?.toInt() ?? 1).clamp(1, 5);
    final parsedSubEquations =
        ((json['subEquations'] as num?)?.toInt() ?? 1).clamp(1, 3);

    return GameConfig(
      gameType: parsedGameType,
      lives: parsedLives,
      parameter: parsedParameter,
      repetitions: parsedRepetitions,
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
      subEquations: parsedSubEquations,
      extras: extras,
    );
  }

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
