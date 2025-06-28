
import 'package:flutter/material.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';

class AlarmGameConfigScreen extends StatefulWidget {
  final GameType gameType;
  final bool isAlarmMode;

  const AlarmGameConfigScreen({
    super.key,
    required this.gameType,
    required this.isAlarmMode,
  });

  @override
  State<AlarmGameConfigScreen> createState() => _AlarmGameConfigScreenState();
}

class _AlarmGameConfigScreenState extends State<AlarmGameConfigScreen> {
  int lives = 0;
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
                _getEquationTypeDescription(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: _getGameColor(),
        foregroundColor: Colors.white,
        title: Text(
          'Configurar $gameTitle',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child:Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLivesSection(),
            const SizedBox(height: 16),
            _buildParameterSection(),
            const SizedBox(height: 16),
            _buildRepetitionsSection(),
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
            const SizedBox(height: 16),
            // const Spacer(),
            ElevatedButton(
              onPressed: () {
                final gameConfig = GameConfig(
                  gameType: widget.gameType,
                  parameter: parameter,
                  repetitions: repetitions,
                  lives: lives,
                  inputType: inputType,
                  operationType: operationType,
                  subEquations: subEquations,
                );
                Navigator.pop(context, gameConfig);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Confirmar Configuración',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    
    
    );
  }


}
