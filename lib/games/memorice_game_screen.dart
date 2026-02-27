import 'package:flutter/material.dart';
import 'package:the_good_alarm/games/modelo_por_juego.dart';
import 'dart:math';
import 'dart:async';

class MemoriceGameScreen extends StatefulWidget {
  final int lives;
  final int pairs;
  final int repetitions;
  final bool isAlarmMode;
  final Function(bool)? onGameFinished;

  const MemoriceGameScreen({
    super.key,
    required this.lives,
    required this.pairs,
    required this.repetitions,
    this.isAlarmMode = false,
    this.onGameFinished,
  });

  @override
  State<MemoriceGameScreen> createState() => _MemoriceGameScreenState();
}

class _MemoriceGameScreenState extends State<MemoriceGameScreen>
    with TickerProviderStateMixin {
  List<MemoryCard> cards = [];
  List<int> selectedCards = [];
  int matchedPairs = 0;
  int currentRepetition = 1;
  int remainingLives = 0;
  int totalErrors = 0;
  bool isProcessing = false;

  late AnimationController _flipController;
  late AnimationController _matchController;
  late AnimationController _errorController;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _matchController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _errorController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
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
      matchedPairs = 0;
      selectedCards.clear();
      isProcessing = false;
    });
    _createCards();
  }

  void _restartSessionDueToLives() {
    if (!mounted) return;
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives;
      totalErrors = 0;
      currentRepetition = 1;
      matchedPairs = 0;
      selectedCards.clear();
      isProcessing = false;
    });
    _createCards();
  }

  void _createCards() {
    cards.clear();
    List<String> symbols = ['🎯', '🎨', '🎪', '🎭', '🎸', '🎺', '🎻', '🎹', '🎲', '🎳'];
    
    for (int i = 0; i < widget.pairs; i++) {
      String symbol = symbols[i % symbols.length];
      cards.add(MemoryCard(id: i * 2, value: i, symbol: symbol));
      cards.add(MemoryCard(id: i * 2 + 1, value: i, symbol: symbol));
    }
    
    cards.shuffle(Random());
  }

  void _onCardTapped(int index) {
    if (isProcessing || 
        cards[index].isMatched || 
        cards[index].isFlipped || 
        selectedCards.length >= 2) {
      return;
    }

    setState(() {
      cards[index].isFlipped = true;
      selectedCards.add(index);
    });

    if (selectedCards.length == 2) {
      _checkMatch();
    }
  }
  
  void _checkMatch() {
    setState(() {
      isProcessing = true;
    });

    Timer(const Duration(milliseconds: 1000), () {
      int firstIndex = selectedCards[0];
      int secondIndex = selectedCards[1];
      
      if (cards[firstIndex].value == cards[secondIndex].value) {
        // Coincidencia encontrada
        setState(() {
          cards[firstIndex].isMatched = true;
          cards[secondIndex].isMatched = true;
          matchedPairs++;
        });
        _matchController.forward().then((_) => _matchController.reset());
        
        if (matchedPairs == widget.pairs) {
          _completedRepetition();
        }
      } else {
        // No hay coincidencia
        setState(() {
          cards[firstIndex].isFlipped = false;
          cards[secondIndex].isFlipped = false;
          totalErrors++;
          if (remainingLives > 0) {
            remainingLives--;
          }
        });
        _errorController.forward().then((_) => _errorController.reset());
        
        // Verificar si se acabaron las vidas
        if (remainingLives == 0) {
          if (widget.isAlarmMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _restartSessionDueToLives();
            });
          } else {
            _gameOver(false);
          }
          return;
        }
      }
      
      setState(() {
        selectedCards.clear();
        isProcessing = false;
      });
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
                backgroundColor: scheme.tertiary,
                foregroundColor: scheme.onTertiary,
              ),
              child: const Text('Jugar de nuevo'),
            ),
          ],
        );
      },
    );
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            '¡Se acabaron las vidas!',
            style: TextStyle(color: scheme.onSurface),
          ),
          content: Text(
            'Errores totales: $totalErrors\n\nDebes reiniciar el juego para continuar.',
            style: TextStyle(color: scheme.onSurface),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _restartGame();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.tertiary,
                foregroundColor: scheme.onTertiary,
              ),
              child: const Text('Reiniciar'),
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
    _flipController.dispose();
    _matchController.dispose();
    _errorController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Memorice - Ronda $currentRepetition/${widget.repetitions}',
          style: TextStyle(color: scheme.onTertiary),
        ),
        backgroundColor: scheme.tertiary,
        foregroundColor: scheme.onTertiary,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: scheme.tertiary.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  'Vidas',
                  remainingLives == -1 ? '∞' : remainingLives.toString(),
                  scheme.error,
                ),
                _buildInfoCard(
                  'Errores',
                  totalErrors.toString(),
                  scheme.secondary,
                ),
                _buildInfoCard(
                  'Pares',
                  '$matchedPairs/${widget.pairs}',
                  scheme.primary,
                ),
              ],
            ),
          ),
          // Grid de cartas
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _calculateCrossAxisCount(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  return _CardWidget(
                    card: cards[index],
                    onTap: () => _onCardTapped(index),
                    flipController: _flipController,
                    matchController: _matchController,
                    errorController: _errorController,
                    isSelected: selectedCards.contains(index),
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

  int _calculateCrossAxisCount() {
    int totalCards = widget.pairs * 2;
    if (totalCards <= 8) return 2;
    if (totalCards <= 18) return 3;
    return 4;
  }
}

class _CardWidget extends StatelessWidget {
  final MemoryCard card;
  final VoidCallback onTap;
  final AnimationController flipController;
  final AnimationController matchController;
  final AnimationController errorController;
  final bool isSelected;

  const _CardWidget({
    required this.card,
    required this.onTap,
    required this.flipController,
    required this.matchController,
    required this.errorController,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: card.isMatched 
              ? scheme.primary.withOpacity(0.3)
              : card.isFlipped 
                  ? scheme.tertiary.withOpacity(0.8)
                  : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? scheme.secondary
                : card.isMatched 
                    ? scheme.primary
                    : scheme.outlineVariant,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: card.isFlipped || card.isMatched
              ? Text(
                  card.symbol,
                  style: const TextStyle(
                    fontSize: 32,
                  ),
                )
              : Icon(
                  Icons.help_outline,
                  color: scheme.onSurface,
                  size: 32,
                ),
        ),
      ),
    );
  }
}
