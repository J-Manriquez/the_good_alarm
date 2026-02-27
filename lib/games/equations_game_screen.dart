import 'package:flutter/material.dart';
import 'dart:math';
import 'package:the_good_alarm/games/modelo_juegos.dart';
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
    _initializeSession();
  }

  void _initializeSession() {
    if (!mounted) return;
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives; // -1 para infinitas
      totalErrors = 0;
      correctAnswers = 0;
      currentEquationIndex = 0;
      currentRepetition = 1;
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
      if (wrongAnswer < 0) wrongAnswer = 0;
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
            if (widget.isAlarmMode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _initializeSession();
              });
            } else {
              _gameOver(false);
            }
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
      _completedRepetition();
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
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            '¡Ronda Completada!',
            style: TextStyle(color: scheme.onSurface),
          ),
          content: Text(
            'Has completado la ronda $currentRepetition de ${widget.repetitions}.\nRespuestas correctas: $correctAnswers/${widget.equations}',
            style: TextStyle(color: scheme.onSurface),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _nextRepetition();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
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
        );
      },
    );
  }

  void _nextRepetition() {
    setState(() {
      currentRepetition++;
      currentEquationIndex = 0;
      showFeedback = false;
      _answerController.clear();
      selectedOption = null;
    });
    _generateEquations();
    _prepareCurrentEquation();
  }

  void _gameOver(bool won) {
    if (widget.isAlarmMode) {
      if (won && currentRepetition >= widget.repetitions) {
        widget.onGameFinished?.call(true);
      } else if (!won) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeSession();
        });
      }
      return;
    }

    widget.onGameFinished?.call(won);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            won ? '¡Felicitaciones!' : '¡Juego Terminado!',
            style: TextStyle(color: scheme.onSurface),
          ),
          content: Text(
            won
                ? 'Has completado todas las repeticiones del juego.\nRespuestas correctas: $correctAnswers/${widget.equations * widget.repetitions}'
                : 'Se acabaron las vidas. Errores totales: $totalErrors',
            style: TextStyle(color: scheme.onSurface),
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.onSurface),
              ),
              child: const Text('Volver'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _restartGame();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
              child: const Text('Jugar de nuevo'),
            ),
          ],
        );
      },
    );
  }

  void _restartGame() {
    _initializeSession();
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
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: scheme.primary),
        ),
      );
    }

    final currentEquation = currentEquations[currentEquationIndex];
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ecuaciones - Ronda $currentRepetition/${widget.repetitions}',
          style: TextStyle(color: scheme.onPrimary),
        ),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: scheme.primary.withAlpha(26),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  'Progreso',
                  '${currentEquationIndex + 1}/${widget.equations}',
                  scheme.primary,
                ),
                _buildInfoCard(
                  'Vidas', 
                  remainingLives == -1 ? '∞' : remainingLives.toString(), 
                  remainingLives <= 1 && remainingLives != -1
                      ? scheme.error
                      : scheme.tertiary
                ),
                _buildInfoCard('Errores', totalErrors.toString(), scheme.secondary),
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
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    child: Text(
                    '${currentEquation.equation} = ?',
                    style: TextStyle(
                      color: scheme.onSurface,
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
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
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
                  color: (isCorrect ? scheme.primary : scheme.error).withAlpha(
                    (0.8 * (1.0 - _feedbackController.value) * 255).round(),
                  ),
                  child: Text(
                    isCorrect ? '¡Correcto!' : 'Incorrecto',
                    style: TextStyle(
                      color: scheme.onPrimary,
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
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _answerController,
      keyboardType: TextInputType.number,
      style: TextStyle(color: scheme.onSurface, fontSize: 24),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: 'Escribe tu respuesta',
        hintStyle: TextStyle(color: scheme.onSurface.withOpacity(0.7)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildMultipleChoiceInput() {
    final scheme = Theme.of(context).colorScheme;
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
              backgroundColor:
                  isSelected ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor: isSelected ? scheme.onPrimary : scheme.onSurface,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? scheme.primary : scheme.outlineVariant,
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
        color: color.withAlpha(26),
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
