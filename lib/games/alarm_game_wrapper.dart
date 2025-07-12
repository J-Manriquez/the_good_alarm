import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import '../modelo_alarm.dart';
import 'memorice_game_screen.dart';
import 'equations_game_screen.dart';
import 'sequence_game_screen.dart';
import '../services/volume_service.dart';
import '../widgets/volume_control_button.dart';

class AlarmGameWrapper extends StatelessWidget {
  final GameConfig gameConfig;
  final VoidCallback onGameCompleted;
  final VoidCallback onGameFailed;
  final int alarmId;
  final int tempVolumeReductionPercent;
  final int tempVolumeReductionDurationSeconds;

  const AlarmGameWrapper({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
    this.tempVolumeReductionPercent = 50,
    this.tempVolumeReductionDurationSeconds = 30,
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
          tempVolumeReductionPercent: tempVolumeReductionPercent,
          tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        );
      case GameType.equations:
        return AlarmEquationsGameScreen(
          gameConfig: gameConfig,
          onGameCompleted: onGameCompleted,
          onGameFailed: onGameFailed,
          alarmId: alarmId,
          tempVolumeReductionPercent: tempVolumeReductionPercent,
          tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        );
      case GameType.sequence:
        return AlarmSequenceGameScreen(
          gameConfig: gameConfig,
          onGameCompleted: onGameCompleted,
          onGameFailed: onGameFailed,
          alarmId: alarmId,
          tempVolumeReductionPercent: tempVolumeReductionPercent,
          tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
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
  final int tempVolumeReductionPercent;
  final int tempVolumeReductionDurationSeconds;

  const AlarmMemoriceGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
    this.tempVolumeReductionPercent = 50,
    this.tempVolumeReductionDurationSeconds = 30,
  });

  @override
  State<AlarmMemoriceGameScreen> createState() => _AlarmMemoriceGameScreenState();
}

class _AlarmMemoriceGameScreenState extends State<AlarmMemoriceGameScreen> {
  late VolumeService _volumeService;

  @override
  void initState() {
    super.initState();
    _volumeService = VolumeService();
  }

  @override
  void dispose() {
    _volumeService.stopVolumeControl().catchError((e) {
      print('Error stopping volume control in game dispose: $e');
    });
    super.dispose();
  }

  void _onVolumeReductionToggle(bool isActive) {
    if (isActive) {
      _volumeService.setTemporaryVolumeReduction(
        widget.tempVolumeReductionPercent,
        widget.tempVolumeReductionDurationSeconds,
      );
    } else {
      _volumeService.cancelTemporaryVolumeReduction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MemoriceGameScreen(
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
          Positioned(
            top: 50,
            right: 20,
            child: VolumeControlButton(
              tempVolumePercent: widget.tempVolumeReductionPercent,
              durationSeconds: widget.tempVolumeReductionDurationSeconds,
              onToggle: _onVolumeReductionToggle,
            ),
          ),
        ],
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
  final int tempVolumeReductionPercent;
  final int tempVolumeReductionDurationSeconds;

  const AlarmEquationsGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
    this.tempVolumeReductionPercent = 50,
    this.tempVolumeReductionDurationSeconds = 30,
  });

  @override
  State<AlarmEquationsGameScreen> createState() => _AlarmEquationsGameScreenState();
}

class _AlarmEquationsGameScreenState extends State<AlarmEquationsGameScreen> {
  late VolumeService _volumeService;

  @override
  void initState() {
    super.initState();
    _volumeService = VolumeService();
  }

  @override
  void dispose() {
    _volumeService.stopVolumeControl().catchError((e) {
      print('Error stopping volume control in game dispose: $e');
    });
    super.dispose();
  }

  void _onVolumeReductionToggle(bool isActive) {
    if (isActive) {
      _volumeService.setTemporaryVolumeReduction(
        widget.tempVolumeReductionPercent,
        widget.tempVolumeReductionDurationSeconds,
      );
    } else {
      _volumeService.cancelTemporaryVolumeReduction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          EquationsGameScreen(
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
          Positioned(
            top: 50,
            right: 20,
            child: VolumeControlButton(
              tempVolumePercent: widget.tempVolumeReductionPercent,
              durationSeconds: widget.tempVolumeReductionDurationSeconds,
              onToggle: _onVolumeReductionToggle,
            ),
          ),
        ],
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
  final int tempVolumeReductionPercent;
  final int tempVolumeReductionDurationSeconds;

  const AlarmSequenceGameScreen({
    super.key,
    required this.gameConfig,
    required this.onGameCompleted,
    required this.onGameFailed,
    required this.alarmId,
    this.tempVolumeReductionPercent = 50,
    this.tempVolumeReductionDurationSeconds = 30,
  });

  @override
  State<AlarmSequenceGameScreen> createState() => _AlarmSequenceGameScreenState();
}

class _AlarmSequenceGameScreenState extends State<AlarmSequenceGameScreen> {
  late VolumeService _volumeService;

  @override
  void initState() {
    super.initState();
    _volumeService = VolumeService();
  }

  @override
  void dispose() {
    _volumeService.stopVolumeControl().catchError((e) {
      print('Error stopping volume control in game dispose: $e');
    });
    super.dispose();
  }

  void _onVolumeReductionToggle(bool isActive) {
    if (isActive) {
      _volumeService.setTemporaryVolumeReduction(
        widget.tempVolumeReductionPercent,
        widget.tempVolumeReductionDurationSeconds,
      );
    } else {
      _volumeService.cancelTemporaryVolumeReduction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SequenceGameScreen(
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
          Positioned(
            top: 50,
            right: 20,
            child: VolumeControlButton(
              tempVolumePercent: widget.tempVolumeReductionPercent,
              durationSeconds: widget.tempVolumeReductionDurationSeconds,
              onToggle: _onVolumeReductionToggle,
            ),
          ),
        ],
      ),
    );
  }
}