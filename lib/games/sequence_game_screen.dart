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
  Timer? _sequenceTimer;

  late AnimationController _glowController;
  late AnimationController _errorController;
  late Animation<double> _glowAnimation;

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
    _initializeSession();
  }

  void _initializeSession() {
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives; // -1 para infinitas
      totalErrors = 0;
      currentRepetition = 1;
    });
    _startRepetition();
  }

  void _startRepetition() {
    setState(() {
      currentStep = 0;
      userSequence.clear();
      isShowingSequence = false;
      isUserTurn = false;
      showError = false;
    });
    _generateSequence();
    _showSequence();
  }

  void _restartSessionDueToLives() {
    if (!mounted) return;
    _sequenceTimer?.cancel();
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives;
      totalErrors = 0;
      currentRepetition = 1;
      currentStep = 0;
      userSequence.clear();
      isShowingSequence = false;
      isUserTurn = false;
      showError = false;
    });
    _generateSequence();
    _showSequence();
  }

  List<Color> _getCardColors(ColorScheme scheme) {
    return <Color>[
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.primary.withOpacity(0.7),
      scheme.secondary.withOpacity(0.7),
      scheme.tertiary.withOpacity(0.7),
      scheme.error.withOpacity(0.7),
      scheme.onSurface.withOpacity(0.7),
    ];
  }

  void _generateSequence() {
    final scheme = Theme.of(context).colorScheme;
    final cardColors = _getCardColors(scheme);
    final random = Random();
    sequence = List.generate(
      widget.sequenceLength,
      (index) => random.nextInt(cardColors.length),
    );
  }

  void _showSequence() {
    _sequenceTimer?.cancel();
    setState(() {
      isShowingSequence = true;
      isUserTurn = false;
      currentStep = 0;
    });

    _sequenceTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (currentStep >= sequence.length) {
        timer.cancel();
        if (_sequenceTimer == timer) _sequenceTimer = null;
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

    setState(() {
      userSequence.add(cardIndex);
    });
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
          if (widget.isAlarmMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _restartSessionDueToLives();
            });
          } else {
            _gameOver(false);
          }
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
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            '¡Ronda Completada!',
            style: TextStyle(color: scheme.onSurface),
          ),
          content: Text(
            'Has completado la ronda $currentRepetition de ${widget.repetitions}.',
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
    });
    _startRepetition();
  }

  void _gameOver(bool won) {
    if (widget.isAlarmMode) {
      if (won && currentRepetition >= widget.repetitions) {
        widget.onGameFinished?.call(true);
      } else if (!won) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restartSessionDueToLives();
        });
      }
      return;
    }

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
                ? 'Has completado todas las repeticiones del juego.'
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
                backgroundColor: scheme.secondary,
                foregroundColor: scheme.onSecondary,
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
    _sequenceTimer?.cancel();
    _glowController.dispose();
    _errorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColors = _getCardColors(scheme);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Secuencia - Ronda $currentRepetition/${widget.repetitions}',
          style: TextStyle(color: scheme.onSecondary),
        ),
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: scheme.secondary.withAlpha(26),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  'Vidas',
                  remainingLives == -1 ? '∞' : remainingLives.toString(),
                  scheme.error,
                ),
                _buildInfoCard('Errores', totalErrors.toString(), scheme.secondary),
                _buildInfoCard(
                  'Progreso',
                  '${userSequence.length}/${sequence.length}',
                  scheme.primary,
                ),
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
              style: TextStyle(
                color: scheme.onSurface,
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
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(77)),
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
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([glowAnimation, errorController]),
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: color.withAlpha(((isGlowing ? 0.9 : 0.6) * 255).round()),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGlowing 
                    ? scheme.onSurface
                    : isError 
                        ? scheme.error
                        : color,
                width: isGlowing ? 3 : 2,
              ),
              boxShadow: [
                if (isGlowing)
                  BoxShadow(
                    color: scheme.onSurface.withAlpha(
                      ((glowAnimation.value * 0.8) * 255).round(),
                    ),
                    blurRadius: 20 * glowAnimation.value,
                    spreadRadius: 5 * glowAnimation.value,
                  ),
                if (isError)
                  BoxShadow(
                    color: scheme.error.withAlpha(204),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                BoxShadow(
                  color: scheme.shadow.withAlpha(77),
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
                  color: scheme.onSurface.withAlpha(77),
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
