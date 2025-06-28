import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'package:the_good_alarm/games/modelo_por_juego.dart';
import 'package:the_good_alarm/games/equation_bank.dart';

class EquationsGameScreen extends StatefulWidget {
  final int lives;
  final int equations;
  final int repetitions;
  final EquationInputType inputType;
  final EquationOperationType operationType;
  final int subEquations;
  final bool isAlarmMode;
  final Function(bool)? onGameFinished;

  const EquationsGameScreen({
    super.key,
    required this.lives,
    required this.equations,
    required this.repetitions,
    required this.inputType,
    required this.operationType,
    required this.subEquations,
    required this.isAlarmMode,
    this.onGameFinished,
  });

  @override
  State<EquationsGameScreen> createState() => _EquationsGameScreenState();
}

class _EquationsGameScreenState extends State<EquationsGameScreen>
    with TickerProviderStateMixin {
  List<dynamic> currentEquations = [];
  int currentEquationIndex = 0;
  int currentRepetition = 1;
  int remainingLives = 0;
  int totalErrors = 0;
  int correctAnswers = 0;
  
  final TextEditingController _answerController = TextEditingController();
  List<int> multipleChoiceOptions = [];
  int? selectedOption;
  
  bool showFeedback = false;
  bool isCorrect = false;
  
  late AnimationController _feedbackController;

  @override
  void initState() {
    super.initState();
    _feedbackController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _initializeGame();
  }

  void _initializeGame() {
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives; // -1 para infinitas
      totalErrors = 0;
      correctAnswers = 0;
      currentEquationIndex = 0;
      showFeedback = false;
      _answerController.clear();
      selectedOption = null;
    });
    _generateEquations();
    _prepareCurrentEquation();
  }

  void _generateEquations() {
    currentEquations = EquationBank.getEquations(
      widget.operationType,
      widget.subEquations,
      widget.equations,
    );
  }



  void _prepareCurrentEquation() {
    if (widget.inputType == EquationInputType.multipleChoice) {
      _generateMultipleChoiceOptions();
    }
    setState(() {
      selectedOption = null;
      _answerController.clear();
    });
  }

  void _generateMultipleChoiceOptions() {
    final random = Random();
    final correctAnswer = currentEquations[currentEquationIndex].result;
    
    multipleChoiceOptions = [correctAnswer];
    
    while (multipleChoiceOptions.length < 4) {
      int wrongAnswer = correctAnswer + random.nextInt(20) - 10;
      if (wrongAnswer != correctAnswer && !multipleChoiceOptions.contains(wrongAnswer)) {
        multipleChoiceOptions.add(wrongAnswer);
      }
    }
    
    multipleChoiceOptions.shuffle(random);
  }

  void _checkAnswer() {
    if (!_canSubmitAnswer()) return;
    
    final currentEquation = currentEquations[currentEquationIndex];
    int userAnswer;
    
    // Obtener la respuesta del usuario según el tipo de entrada
    if (widget.inputType == EquationInputType.manual) {
      userAnswer = int.tryParse(_answerController.text.trim()) ?? 0;
    } else {
      userAnswer = selectedOption ?? 0;
    }
    
    // Verificar si la respuesta es correcta
    final correctAnswer = currentEquation.result;
    isCorrect = userAnswer == correctAnswer;
    
    setState(() {
      showFeedback = true;
    });
    
    // Iniciar animación de feedback
    _feedbackController.forward().then((_) {
      _feedbackController.reset();
      
      if (isCorrect) {
        correctAnswers++;
        _nextEquation();
      } else {
        totalErrors++;
        if (remainingLives > 0) {
          remainingLives--;
          if (remainingLives == 0) {
            _gameOver(false);
            return;
          }
        }
        // No avanzar a la siguiente ecuación si es incorrecta
        // Solo limpiar la respuesta para que el usuario intente de nuevo
        _clearAnswer();
      }
      
      setState(() {
        showFeedback = false;
      });
    });
  }

  
  void _nextEquation() {
    if (currentEquationIndex < widget.equations - 1) {
      setState(() {
        currentEquationIndex++;
        _answerController.clear();
        selectedOption = null;
      });
      _prepareCurrentEquation();
    } else {
      // Completó todas las ecuaciones de esta repetición
      if (currentRepetition < widget.repetitions) {
        setState(() {
          currentRepetition++;
          currentEquationIndex = 0;
          _answerController.clear();
          selectedOption = null;
        });
        _generateEquations();
        _prepareCurrentEquation();
      } else {
        // Completó todas las repeticiones
        _gameOver(true);
      }
    }
  }
  
  void _clearAnswer() {
    setState(() {
      _answerController.clear();
      selectedOption = null;
    });
  }

  void _completedRepetition() {
    if (currentRepetition >= widget.repetitions) {
      _gameOver(true);
    } else {
      if (widget.isAlarmMode) {
        _nextRepetition();
      } else {
        _showRepetitionDialog();
      }
    }
  }

  void _showRepetitionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '¡Ronda Completada!',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Has completado la ronda $currentRepetition de ${widget.repetitions}.\nRespuestas correctas: $correctAnswers/${widget.equations}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _nextRepetition();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Continuar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _nextRepetition() {
    setState(() {
      currentRepetition++;
    });
    _initializeGame();
  }

  void _gameOver(bool won) {
    if (widget.onGameFinished != null) {
      widget.onGameFinished!(true);
    }
    if (widget.isAlarmMode) {
      if (won && currentRepetition >= widget.repetitions) {
        widget.onGameFinished?.call(true);
      } else if (!won) {
        // En modo alarma, mostrar opción de reiniciar cuando se pierden las vidas
        _showRestartDialog();
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          won ? '¡Felicitaciones!' : '¡Juego Terminado!',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          won 
            ? 'Has completado todas las repeticiones del juego.\nRespuestas correctas: $correctAnswers/${widget.equations * widget.repetitions}'
            : 'Se acabaron las vidas. Errores totales: $totalErrors',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
            ),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _restartGame();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Jugar de nuevo'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '¡Se acabaron las vidas!',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Errores totales: $totalErrors\n\nDebes reiniciar el juego para continuar.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _restartGame();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
  }

  void _restartGame() {
    setState(() {
      currentRepetition = 1;
    });
    _initializeGame();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentEquations.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.green),
        ),
      );
    }

    final currentEquation = currentEquations[currentEquationIndex];
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Ecuaciones - Ronda $currentRepetition/${widget.repetitions}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard('Progreso', '${currentEquationIndex + 1}/${widget.equations}', Colors.green),
                _buildInfoCard(
                  'Vidas', 
                  remainingLives == -1 ? '∞' : remainingLives.toString(), 
                  remainingLives <= 1 && remainingLives != -1 ? Colors.red : Colors.blue
                ),
                _buildInfoCard('Errores', totalErrors.toString(), Colors.orange),
              ],
            ),
          ),
          // Ecuación actual
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mostrar ecuación
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: Text(
                    '${currentEquation.equation} = ?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Input de respuesta
                  if (widget.inputType == EquationInputType.manual)
                    _buildManualInput()
                  else
                    _buildMultipleChoiceInput(),
                  
                  const SizedBox(height: 24),
                  
                  // Botón de enviar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmitAnswer() ? _checkAnswer : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Enviar Respuesta',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Feedback visual
          if (showFeedback)
            AnimatedBuilder(
              animation: _feedbackController,
              builder: (context, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: (isCorrect ? Colors.green : Colors.red).withOpacity(
                    0.8 * (1.0 - _feedbackController.value),
                  ),
                  child: Text(
                    isCorrect ? '¡Correcto!' : 'Incorrecto',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildManualInput() {
    return TextField(
      controller: _answerController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white, fontSize: 24),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: 'Escribe tu respuesta',
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[800],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.green),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
      ),
    );
  }

  Widget _buildMultipleChoiceInput() {
    return Column(
      children: multipleChoiceOptions.map((option) {
        final isSelected = selectedOption == option;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                selectedOption = option;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? Colors.green : Colors.grey[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.green : Colors.grey[600]!,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              option.toString(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _canSubmitAnswer() {
    if (showFeedback) return false; // No permitir envío durante feedback
    
    if (widget.inputType == EquationInputType.manual) {
      final text = _answerController.text.trim();
      if (text.isEmpty) return false;
      // Verificar que sea un número válido
      return int.tryParse(text) != null;
    } else {
      return selectedOption != null;
    }
  }

  Widget _buildInfoCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}