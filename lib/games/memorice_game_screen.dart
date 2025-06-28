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
    _initializeGame();
  }

  void _initializeGame() {
    setState(() {
      remainingLives = widget.lives == 0 ? -1 : widget.lives; // -1 para infinitas
      totalErrors = 0;
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
          _gameOver(false);
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
              backgroundColor: Colors.purple,
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
              backgroundColor: Colors.purple,
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
    _flipController.dispose();
    _matchController.dispose();
    _errorController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Memorice - Ronda $currentRepetition/${widget.repetitions}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isAlarmMode,
      ),
      body: Column(
        children: [
          // Información del juego
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard('Vidas', remainingLives == -1 ? '∞' : remainingLives.toString(), Colors.red),
                _buildInfoCard('Errores', totalErrors.toString(), Colors.orange),
                _buildInfoCard('Pares', '$matchedPairs/${widget.pairs}', Colors.green),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: card.isMatched 
              ? Colors.green.withOpacity(0.3)
              : card.isFlipped 
                  ? Colors.purple.withOpacity(0.8)
                  : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Colors.yellow
                : card.isMatched 
                    ? Colors.green
                    : Colors.grey[600]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
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
              : const Icon(
                  Icons.help_outline,
                  color: Colors.white,
                  size: 32,
                ),
        ),
      ),
    );
  }
}