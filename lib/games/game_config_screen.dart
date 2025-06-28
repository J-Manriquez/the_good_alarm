import 'package:flutter/material.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import '../modelo_alarm.dart';
import 'memorice_game_screen.dart';
import 'equations_game_screen.dart';
import 'sequence_game_screen.dart';

class GameConfigScreen extends StatefulWidget {
  final GameType gameType;
  final bool isAlarmMode;
  final Function(GameConfig)? onConfigComplete;

  const GameConfigScreen({
    super.key,
    required this.gameType,
    this.isAlarmMode = true,
    this.onConfigComplete,
  });

  @override
  State<GameConfigScreen> createState() => _GameConfigScreenState();
}

class _GameConfigScreenState extends State<GameConfigScreen> {
  int lives = 0; // 0: Infinitas, 1, 3, 5
  int parameter = 5;
  int repetitions = 1;

  // Parámetros específicos para ecuaciones
  EquationInputType inputType = EquationInputType.manual;
  EquationOperationType operationType = EquationOperationType.addSubtract;
  int subEquations = 1;

  final List<int> livesOptions = [0, 1, 3, 5];

  String get gameTitle {
    switch (widget.gameType) {
      case GameType.memorice:
        return 'Memorice';
      case GameType.equations:
        return 'Resolver Ecuaciones';
      case GameType.sequence:
        return 'Secuencia de Formas';
    }
  }

  String get parameterLabel {
    switch (widget.gameType) {
      case GameType.memorice:
        return 'Pares de cartas';
      case GameType.equations:
        return 'Número de ecuaciones';
      case GameType.sequence:
        return 'Longitud de secuencia';
    }
  }

  String _getLivesDescription(int livesValue) {
    switch (livesValue) {
      case 0:
        return 'Infinitas - Sin límite de errores';
      case 1:
        return '1 vida - Un error y reinicia';
      case 3:
        return '3 vidas - Tres errores y reinicia';
      case 5:
        return '5 vidas - Cinco errores y reinicia';
      default:
        return '';
    }
  }

  Color _getGameColor() {
    switch (widget.gameType) {
      case GameType.memorice:
        return Colors.purple;
      case GameType.equations:
        return Colors.green;
      case GameType.sequence:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isAlarmMode ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text('Configurar $gameTitle'),
        backgroundColor: _getGameColor(),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuración de vidas
            _buildLivesSection(),
            const SizedBox(height: 16),
            // Configuración del parámetro principal
            _buildParameterSection(),
            const SizedBox(height: 16),

            // Configuración de repeticiones
            _buildRepetitionsSection(),
            const SizedBox(height: 16),

            // Configuraciones específicas para ecuaciones
            if (widget.gameType == GameType.equations) ...[
              // Tipo de entrada
              Card(
                color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tipo de respuesta',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: widget.isAlarmMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                      ),
                      const SizedBox(height: 16),
                      RadioListTile<EquationInputType>(
                        title: Text(
                          'Manual - Escribir respuesta',
                          style: TextStyle(
                            color: widget.isAlarmMode
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        value: EquationInputType.manual,
                        groupValue: inputType,
                        activeColor: _getGameColor(),
                        onChanged: (value) {
                          setState(() {
                            inputType = value!;
                          });
                        },
                      ),
                      RadioListTile<EquationInputType>(
                        title: Text(
                          'Opción múltiple - 4 alternativas',
                          style: TextStyle(
                            color: widget.isAlarmMode
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        value: EquationInputType.multipleChoice,
                        groupValue: inputType,
                        activeColor: _getGameColor(),
                        onChanged: (value) {
                          setState(() {
                            inputType = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Tipo de operaciones
              Card(
                color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operaciones matemáticas',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: widget.isAlarmMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                      ),
                      const SizedBox(height: 16),
                      RadioListTile<EquationOperationType>(
                        title: Text(
                          'Solo suma y resta',
                          style: TextStyle(
                            color: widget.isAlarmMode
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        value: EquationOperationType.addSubtract,
                        groupValue: operationType,
                        activeColor: _getGameColor(),
                        onChanged: (value) {
                          setState(() {
                            operationType = value!;
                          });
                        },
                      ),
                      RadioListTile<EquationOperationType>(
                        title: Text(
                          'Suma, resta, multiplicación y división',
                          style: TextStyle(
                            color: widget.isAlarmMode
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        value: EquationOperationType.addSubtractMultiplyDivide,
                        groupValue: operationType,
                        activeColor: _getGameColor(),
                        onChanged: (value) {
                          setState(() {
                            operationType = value!;
                          });
                        },
                      ),
                      RadioListTile<EquationOperationType>(
                        title: Text(
                          'Solo multiplicación y división',
                          style: TextStyle(
                            color: widget.isAlarmMode
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        value: EquationOperationType.multiplyDivide,
                        groupValue: operationType,
                        activeColor: _getGameColor(),
                        onChanged: (value) {
                          setState(() {
                            operationType = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Complejidad de ecuaciones
              // En la función _buildEquationSpecificSections(), modificar la sección de complejidad:
              Card(
                color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complejidad de ecuaciones',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: widget.isAlarmMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            '1',
                            style: TextStyle(
                              color: widget.isAlarmMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: subEquations.toDouble(),
                              min: 1,
                              max: 3,
                              divisions: 2,
                              label: _getEquationComplexityLabel(),
                              activeColor: _getGameColor(),
                              onChanged: (value) {
                                setState(() {
                                  subEquations = value.round();
                                });
                              },
                            ),
                          ),
                          Text(
                            '3',
                            style: TextStyle(
                              color: widget.isAlarmMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                      Center(
                        child: Text(
                          'Operaciones por ecuación: $subEquations',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: widget.isAlarmMode
                                    ? Colors.white
                                    : Colors.black,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // _buildEquationSpecificSections(),
            const SizedBox(height: 32),

            // Botones de acción
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildLivesSection() {
    return Card(
      color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vidas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: widget.isAlarmMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            ...livesOptions.map((livesValue) {
              return RadioListTile<int>(
                title: Text(
                  livesValue == 0
                      ? 'Infinitas'
                      : '$livesValue ${livesValue == 1 ? 'vida' : 'vidas'}',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                subtitle: Text(
                  _getLivesDescription(livesValue),
                  style: TextStyle(
                    color: widget.isAlarmMode
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
                value: livesValue,
                groupValue: lives,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    lives = value!;
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildParameterSection() {
    return Card(
      color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parameterLabel,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: widget.isAlarmMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '1',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: parameter.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: parameter.toString(),
                    activeColor: _getGameColor(),
                    onChanged: (value) {
                      setState(() {
                        parameter = value.round();
                      });
                    },
                  ),
                ),
                Text(
                  '10',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            Center(
              child: Text(
                'Valor seleccionado: $parameter',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: widget.isAlarmMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepetitionsSection() {
    return Card(
      color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Repeticiones',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: widget.isAlarmMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '1',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: repetitions.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: repetitions.toString(),
                    activeColor: _getGameColor(),
                    onChanged: (value) {
                      setState(() {
                        repetitions = value.round();
                      });
                    },
                  ),
                ),
                Text(
                  '5',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            Center(
              child: Text(
                'Repeticiones: $repetitions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: widget.isAlarmMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEquationTypeDescription() {
    switch (subEquations) {
      case 1:
        return 'Ecuaciones simples: una sola operación (ej: 5 + 3 = ?)';
      case 2:
        return 'Ecuaciones intermedias: dos operaciones (ej: 5 + 3 - 2 = ?)';
      case 3:
        return 'Ecuaciones complejas: tres operaciones (ej: 5 + 3 - 2 × 4 = ?)';
      default:
        return '';
    }
  }

  String _getEquationComplexityLabel() {
    switch (subEquations) {
      case 1:
        return 'Ecuaciones Simples (1 operación)';
      case 2:
        return 'Ecuaciones Intermedias (2 operaciones)';
      case 3:
        return 'Ecuaciones Complejas (3 operaciones)';
      default:
        return 'Ecuaciones Simples';
    }
  }

  List<Widget> _buildEquationSpecificSections() {
    return [
      // Tipo de entrada
      Card(
        color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tipo de respuesta',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: widget.isAlarmMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              RadioListTile<EquationInputType>(
                title: Text(
                  'Manual - Escribir respuesta',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                value: EquationInputType.manual,
                groupValue: inputType,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    inputType = value!;
                  });
                },
              ),
              RadioListTile<EquationInputType>(
                title: Text(
                  'Opción múltiple - 4 alternativas',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                value: EquationInputType.multipleChoice,
                groupValue: inputType,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    inputType = value!;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Tipo de operaciones
      Card(
        color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Operaciones matemáticas',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: widget.isAlarmMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              RadioListTile<EquationOperationType>(
                title: Text(
                  'Solo suma y resta',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                value: EquationOperationType.addSubtract,
                groupValue: operationType,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    operationType = value!;
                  });
                },
              ),
              RadioListTile<EquationOperationType>(
                title: Text(
                  'Suma, resta, multiplicación y división',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                value: EquationOperationType.addSubtractMultiplyDivide,
                groupValue: operationType,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    operationType = value!;
                  });
                },
              ),
              RadioListTile<EquationOperationType>(
                title: Text(
                  'Solo multiplicación y división',
                  style: TextStyle(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
                value: EquationOperationType.multiplyDivide,
                groupValue: operationType,
                activeColor: _getGameColor(),
                onChanged: (value) {
                  setState(() {
                    operationType = value!;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Complejidad de ecuaciones
      // En la función _buildEquationSpecificSections(), modificar la sección de complejidad:
      Card(
        color: widget.isAlarmMode ? Colors.grey[900] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complejidad de ecuaciones',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: widget.isAlarmMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '1',
                    style: TextStyle(
                      color: widget.isAlarmMode ? Colors.white : Colors.black,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: subEquations.toDouble(),
                      min: 1,
                      max: 3,
                      divisions: 2,
                      label: _getEquationComplexityLabel(),
                      activeColor: _getGameColor(),
                      onChanged: (value) {
                        setState(() {
                          subEquations = value.round();
                        });
                      },
                    ),
                  ),
                  Text(
                    '3',
                    style: TextStyle(
                      color: widget.isAlarmMode ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              Center(
                child: Text(
                  'Operaciones por ecuación: $subEquations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: widget.isAlarmMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _getGameColor(),
              side: BorderSide(color: _getGameColor()),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _startGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: _getGameColor(),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(widget.isAlarmMode ? 'Iniciar Juego' : 'Jugar'),
          ),
        ),
      ],
    );
  }

  void _startGame() {
    final config = GameConfig(
      gameType: widget.gameType,
      lives: lives,
      parameter: parameter,
      repetitions: repetitions,
      inputType: inputType,
      operationType: operationType,
      subEquations: subEquations,
    );

    if (widget.onConfigComplete != null) {
      widget.onConfigComplete!(config);
      return;
    }

    Widget gameScreen;
    switch (widget.gameType) {
      case GameType.memorice:
        gameScreen = MemoriceGameScreen(
          lives: lives,
          pairs: parameter,
          repetitions: repetitions,
          isAlarmMode: widget.isAlarmMode,
        );
        break;
      case GameType.equations:
        gameScreen = EquationsGameScreen(
          lives: lives,
          equations: parameter,
          repetitions: repetitions,
          inputType: inputType,
          operationType: operationType,
          subEquations: subEquations,
          isAlarmMode: widget.isAlarmMode,
        );
        break;
      case GameType.sequence:
        gameScreen = SequenceGameScreen(
          lives: lives,
          sequenceLength: parameter,
          repetitions: repetitions,
          isAlarmMode: widget.isAlarmMode,
        );
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => gameScreen),
    );
  }
}
