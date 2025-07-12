import 'package:flutter/material.dart';
import 'dart:async';

class VolumeControlButton extends StatefulWidget {
  final int tempVolumePercent;
  final int durationSeconds;
  final VoidCallback? onPressed;
  final Function(bool)? onToggle;
  final bool isActive;
  final VoidCallback? onExpired;

  const VolumeControlButton({
    Key? key,
    int? tempVolumePercent,
    int? reductionPercent,
    required this.durationSeconds,
    this.onPressed,
    this.onToggle,
    this.isActive = false,
    this.onExpired,
  }) : tempVolumePercent = tempVolumePercent ?? reductionPercent ?? 50,
       super(key: key);

  // Constructor alternativo para compatibilidad
  const VolumeControlButton.withToggle({
    Key? key,
    int? tempVolumePercent,
    int? reductionPercent,
    required this.durationSeconds,
    required this.onToggle,
    this.isActive = false,
    this.onExpired,
  }) : tempVolumePercent = tempVolumePercent ?? reductionPercent ?? 50,
       onPressed = null,
       super(key: key);

  @override
  State<VolumeControlButton> createState() => _VolumeControlButtonState();
}

class _VolumeControlButtonState extends State<VolumeControlButton>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _isCountingDown = false;

  @override
  void initState() {
    super.initState();
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
    
    // Sincronizar con el estado inicial
    _isCountingDown = widget.isActive;
    if (_isCountingDown) {
      _remainingSeconds = widget.durationSeconds;
      _animationController.forward();
      _startCountdownTimer();
    }
  }
  
  @override
  void didUpdateWidget(VolumeControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Sincronizar cuando cambia el estado externo
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive && !_isCountingDown) {
        _startCountdown();
      } else if (!widget.isActive && _isCountingDown) {
        _stopCountdown();
      }
    }
    
    // Actualizar duración si cambió
    if (widget.durationSeconds != oldWidget.durationSeconds) {
      _animationController.duration = Duration(seconds: widget.durationSeconds);
      if (_isCountingDown) {
        _remainingSeconds = widget.durationSeconds;
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _remainingSeconds = widget.durationSeconds;
    });

    _animationController.reset();
    _animationController.forward();
    _startCountdownTimer();
  }
  
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _stopCountdown();
        widget.onExpired?.call();
      }
    });
  }

  void _stopCountdown() {
    setState(() {
      _isCountingDown = false;
      _remainingSeconds = 0;
    });
    _animationController.reset();
    _countdownTimer?.cancel();
  }

  void _onButtonPressed() {
    if (_isCountingDown) {
      _stopCountdown();
      // Llamar onToggle con false cuando se detiene
      if (widget.onToggle != null) {
        widget.onToggle!(false);
      }
    } else {
      _startCountdown();
      // Llamar onToggle con true cuando se inicia
      if (widget.onToggle != null) {
        widget.onToggle!(true);
      }
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
                      _isCountingDown 
                          ? '${widget.tempVolumePercent}%'
                          : '${widget.tempVolumePercent}%',
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