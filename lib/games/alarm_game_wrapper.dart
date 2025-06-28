import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import '../modelo_alarm.dart';
import 'memorice_game_screen.dart';
import 'equations_game_screen.dart';
import 'sequence_game_screen.dart';

class AlarmGameWrapper extends StatelessWidget {
  final GameConfig gameConfig;
  final VoidCallback onGameCompleted;
  final VoidCallback onGameFailed;
  final int alarmId;

  const AlarmGameWrapper({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevenir que el usuario salga del juego sin completarlo
        _showExitWarning(context);
        return false;
      },
      child: _buildGameScreen(),
    );
  }

  Widget _buildGameScreen() {
    switch (gameConfig.gameType) {
      case GameType.memorice:
        return AlarmMemoriceGameScreen(
          gameConfig: gameConfig,
          onGameCompleted: onGameCompleted,
          onGameFailed: onGameFailed,
          alarmId: alarmId,
        );
      case GameType.equations:
        return AlarmEquationsGameScreen(
          gameConfig: gameConfig,
          onGameCompleted: onGameCompleted,
          onGameFailed: onGameFailed,
          alarmId: alarmId,
        );
      case GameType.sequence:
        return AlarmSequenceGameScreen(
          gameConfig: gameConfig,
          onGameCompleted: onGameCompleted,
          onGameFailed: onGameFailed,
          alarmId: alarmId,
        );
    }
  }

  void _showExitWarning(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '¡Alarma Activa!',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Debes completar el juego para apagar la alarma.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Continuar Jugando',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}

// Versión específica para alarmas del juego Memorice
class AlarmMemoriceGameScreen extends StatefulWidget {
  final GameConfig gameConfig;
  final VoidCallback onGameCompleted;
  final VoidCallback onGameFailed;
  final int alarmId;

  const AlarmMemoriceGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
  });

  @override
  State<AlarmMemoriceGameScreen> createState() => _AlarmMemoriceGameScreenState();
}

class _AlarmMemoriceGameScreenState extends State<AlarmMemoriceGameScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MemoriceGameScreen(
        lives: widget.gameConfig.lives,
        pairs: widget.gameConfig.parameter,
        repetitions: widget.gameConfig.repetitions,
        isAlarmMode: true,
        onGameFinished: (bool success) {
          if (success) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onGameCompleted();
          } else {
            widget.onGameFailed();
          }
        },
      ),
    );
  }
}

// Versión para Equations
class AlarmEquationsGameScreen extends StatefulWidget {
  final GameConfig gameConfig;
  final VoidCallback onGameCompleted;
  final VoidCallback onGameFailed;
  final int alarmId;

  const AlarmEquationsGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
  });

  @override
  State<AlarmEquationsGameScreen> createState() => _AlarmEquationsGameScreenState();
}

class _AlarmEquationsGameScreenState extends State<AlarmEquationsGameScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: EquationsGameScreen(
        lives: widget.gameConfig.lives,
        equations: widget.gameConfig.parameter,
        repetitions: widget.gameConfig.repetitions,
        inputType: widget.gameConfig.inputType,
        operationType: widget.gameConfig.operationType,
        subEquations: widget.gameConfig.subEquations,
        isAlarmMode: true,
        onGameFinished: (bool success) {
          if (success) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onGameCompleted();
          } else {
            widget.onGameFailed();
          }
        },
      ),
    );
  }
}

// Versión para Sequence
class AlarmSequenceGameScreen extends StatefulWidget {
  final GameConfig gameConfig;
  final VoidCallback onGameCompleted;
  final VoidCallback onGameFailed;
  final int alarmId;

  const AlarmSequenceGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
  });

  @override
  State<AlarmSequenceGameScreen> createState() => _AlarmSequenceGameScreenState();
}

class _AlarmSequenceGameScreenState extends State<AlarmSequenceGameScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SequenceGameScreen(
        lives: widget.gameConfig.lives,
        sequenceLength: widget.gameConfig.parameter,
        repetitions: widget.gameConfig.repetitions,
        isAlarmMode: true,
        onGameFinished: (bool success) {
          if (success) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onGameCompleted();
          } else {
            widget.onGameFailed();
          }
        },
      ),
    );
  }
}