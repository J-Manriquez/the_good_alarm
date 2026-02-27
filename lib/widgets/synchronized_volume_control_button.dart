import 'package:flutter/material.dart';
import 'dart:async';
import '../services/volume_reduction_service.dart';

class SynchronizedVolumeControlButton extends StatefulWidget {
  final int tempVolumePercent;
  final int durationSeconds;
  final VoidCallback? onPressed;
  final Function(bool)? onToggle;
  final VoidCallback? onExpired;

  const SynchronizedVolumeControlButton({
    Key? key,
    int? tempVolumePercent,
    int? reductionPercent,
    required this.durationSeconds,
    this.onPressed,
    this.onToggle,
    this.onExpired,
  }) : tempVolumePercent = tempVolumePercent ?? reductionPercent ?? 50,
       super(key: key);

  @override
  State<SynchronizedVolumeControlButton> createState() => _SynchronizedVolumeControlButtonState();
}

class _SynchronizedVolumeControlButtonState extends State<SynchronizedVolumeControlButton>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  late VolumeReductionService _volumeReductionService;
  StreamSubscription<VolumeReductionState>? _stateSubscription;
  
  bool _isCountingDown = false;
  int _remainingSeconds = 0;
  int _totalDurationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _volumeReductionService = VolumeReductionService();
    
    _animationController = AnimationController(
      duration: Duration(seconds: widget.durationSeconds),
      vsync: this,
    );
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));
    
    // Sincronizar con el estado actual del servicio
    _syncWithGlobalState();
    
    // Escuchar cambios en el estado global
    _stateSubscription = _volumeReductionService.stateStream.listen(_onGlobalStateChanged);
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _stateSubscription?.cancel();
    super.dispose();
  }
  
  /// Sincroniza el estado local con el estado global del servicio
  void _syncWithGlobalState() {
    final globalState = _volumeReductionService.getCurrentState();
    _updateLocalState(globalState);
  }
  
  /// Maneja cambios en el estado global
  void _onGlobalStateChanged(VolumeReductionState state) {
    _updateLocalState(state);
  }
  
  /// Actualiza el estado local basado en el estado global
  void _updateLocalState(VolumeReductionState state) {
    if (!mounted) return;
    
    final wasCountingDown = _isCountingDown;
    
    setState(() {
      _isCountingDown = state.isActive;
      _remainingSeconds = state.remainingSeconds;
      _totalDurationSeconds = state.totalDurationSeconds;
    });
    
    // Debug: Imprimir estado para diagnóstico
    print('SynchronizedVolumeControlButton - State updated: active=${state.isActive}, remaining=${state.remainingSeconds}s, total=${state.totalDurationSeconds}s');
    
    // Actualizar animación
    if (state.isActive && state.totalDurationSeconds > 0) {
      final progress = state.progress;
      _animationController.duration = Duration(seconds: state.totalDurationSeconds);
      _animationController.value = progress;
      
      if (progress < 1.0) {
        _animationController.forward();
      }
    } else {
      _animationController.reset();
    }
    
    // Llamar onExpired si la reducción terminó
    if (!state.isActive && wasCountingDown) {
      widget.onExpired?.call();
    }
  }

  /// Maneja el press del botón
  void _onButtonPressed() async {
    print('SynchronizedVolumeControlButton - Button pressed, current state: counting=$_isCountingDown');
    
    if (_isCountingDown) {
      // Detener la reducción global
      print('SynchronizedVolumeControlButton - Stopping volume reduction');
      await _volumeReductionService.stopVolumeReduction();
      widget.onToggle?.call(false);
    } else {
      // Iniciar la reducción global
      print('SynchronizedVolumeControlButton - Starting volume reduction: ${widget.tempVolumePercent}% for ${widget.durationSeconds}s');
      await _volumeReductionService.startVolumeReduction(
        tempVolumePercent: widget.tempVolumePercent,
        durationSeconds: widget.durationSeconds,
      );
      widget.onToggle?.call(true);
    }
    
    // Llamar onPressed si no hay onToggle
    if (widget.onToggle == null && widget.onPressed != null) {
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Círculo de progreso animado
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return CircularProgressIndicator(
                value: _isCountingDown ? _progressAnimation.value : 0.0,
                strokeWidth: 4,
                backgroundColor: Colors.grey.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _isCountingDown ? Colors.orange : Colors.blue,
                ),
              );
            },
          ),
          // Botón principal
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onButtonPressed,
              borderRadius: BorderRadius.circular(40),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _isCountingDown ? Colors.orange : Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isCountingDown ? Icons.volume_down : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                    Text(
                      '${widget.tempVolumePercent}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Contador de tiempo restante
          if (_isCountingDown)
            Positioned(
              bottom: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_remainingSeconds}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}