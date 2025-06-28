import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

class SequenceGameScreen extends StatefulWidget {
  final int lives;
  final int sequenceLength;
  final int repetitions;
  final bool isAlarmMode;
  final Function(bool)? onGameFinished;

  const SequenceGameScreen({
    super.key,
    required this.lives,
    required this.sequenceLength,
    required this.repetitions,
    this.isAlarmMode = false,
    this.onGameFinished,
  });

  @override
  State<SequenceGameScreen> createState() => _SequenceGameScreenState();
}

class _SequenceGameScreenState extends State<SequenceGameScreen>
    with TickerProviderStateMixin {
  List<int> sequence = [];
  List<int> userSequence = [];
  int currentStep = 0;
  int currentRepetition = 1;
  int remainingLives = 0;
  int totalErrors = 0;
  bool isShowingSequence = false;
  bool isUserTurn = false;
  bool showError = false;

  late AnimationController _glowController;
  late AnimationController _errorController;
  late Animation<double> _glowAnimation;

  final List<Color> cardColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.cyan,
    Colors.lime,
  ];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _errorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _initializeGame();
  }

  void _initializeGame() {
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives; // -1 para infinitas
      totalErrors = 0;
      currentStep = 0;
      userSequence.clear();
      isShowingSequence = false;
      isUserTurn = false;
      showError = false;
    });
    _generateSequence();
    _showSequence();
  }

  void _generateSequence() {
    final random = Random();
    sequence = List.generate(
      widget.sequenceLength,
      (index) => random.nextInt(cardColors.length),
    );
  }

  void _showSequence() {
    setState(() {
      isShowingSequence = true;
      isUserTurn = false;
      currentStep = 0;
    });

    Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (currentStep >= sequence.length) {
        timer.cancel();
        setState(() {
          isShowingSequence = false;
          isUserTurn = true;
          currentStep = 0;
        });
        return;
      }

      _glowController.forward().then((_) {
        _glowController.reverse();
      });

      setState(() {
        currentStep++;
      });
    });
  }

  void _onCardTapped(int cardIndex) {
    if (!isUserTurn || isShowingSequence) return;

    userSequence.add(cardIndex);
    int currentIndex = userSequence.length - 1;

    if (userSequence[currentIndex] != sequence[currentIndex]) {
      // Error en la secuencia
      setState(() {
        showError = true;
        totalErrors++;
        if (remainingLives > 0) {
          remainingLives--;
        }
      });

      _errorController.forward().then((_) {
        _errorController.reset();
        setState(() {
          showError = false;
        });

        if (remainingLives == 0) {
          _gameOver(false);
        } else {
          // Reiniciar secuencia
          setState(() {
            userSequence.clear();
          });
          _showSequence();
        }
      });
    } else if (userSequence.length == sequence.length) {
      // Secuencia completada correctamente
      _completedRepetition();
    }
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
          'Has completado la ronda $currentRepetition de ${widget.repetitions}.',
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
            ? 'Has completado todas las repeticiones del juego.'
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
              backgroundColor: Colors.orange,
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
              backgroundColor: Colors.orange,
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
    _glowController.dispose();
    _errorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Secuencia - Ronda $currentRepetition/${widget.repetitions}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard('Vidas', remainingLives == -1 ? '∞' : remainingLives.toString(), Colors.red),
                _buildInfoCard('Errores', totalErrors.toString(), Colors.orange),
                _buildInfoCard('Progreso', '${userSequence.length}/${sequence.length}', Colors.green),
              ],
            ),
          ),
          // Estado del juego
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              isShowingSequence 
                  ? 'Observa la secuencia...'
                  : isUserTurn 
                      ? 'Tu turno - Repite la secuencia'
                      : 'Preparando...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Grid de cartas
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: cardColors.length,
                itemBuilder: (context, index) {
                  return _SequenceCard(
                    color: cardColors[index],
                    isGlowing: isShowingSequence && 
                               currentStep > 0 && 
                               currentStep <= sequence.length && 
                               sequence[currentStep - 1] == index,
                    isError: showError,
                    onTap: () => _onCardTapped(index),
                    glowAnimation: _glowAnimation,
                    errorController: _errorController,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
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

class _SequenceCard extends StatelessWidget {
  final Color color;
  final bool isGlowing;
  final bool isError;
  final VoidCallback onTap;
  final Animation<double> glowAnimation;
  final AnimationController errorController;

  const _SequenceCard({
    required this.color,
    required this.isGlowing,
    required this.isError,
    required this.onTap,
    required this.glowAnimation,
    required this.errorController,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([glowAnimation, errorController]),
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: color.withOpacity(isGlowing ? 0.9 : 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGlowing 
                    ? Colors.white
                    : isError 
                        ? Colors.red
                        : color,
                width: isGlowing ? 3 : 2,
              ),
              boxShadow: [
                if (isGlowing)
                  BoxShadow(
                    color: Colors.white.withOpacity(glowAnimation.value * 0.8),
                    blurRadius: 20 * glowAnimation.value,
                    spreadRadius: 5 * glowAnimation.value,
                  ),
                if (isError)
                  BoxShadow(
                    color: Colors.red.withOpacity(0.8),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}