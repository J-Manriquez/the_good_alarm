import 'dart:async';
import 'package:flutter/services.dart';

class VolumeReductionService {
  static final VolumeReductionService _instance = VolumeReductionService._internal();
  factory VolumeReductionService() => _instance;
  VolumeReductionService._internal();

  // Estado global de la reducción de volumen
  bool _isActive = false;
  int _remainingSeconds = 0;
  int _totalDurationSeconds = 0;
  int _tempVolumePercent = 50;
  Timer? _globalTimer;
  
  // Stream controllers para notificar cambios
  final StreamController<VolumeReductionState> _stateController = 
      StreamController<VolumeReductionState>.broadcast();
  
  // Getters
  bool get isActive => _isActive;
  int get remainingSeconds => _remainingSeconds;
  int get totalDurationSeconds => _totalDurationSeconds;
  int get tempVolumePercent => _tempVolumePercent;
  Stream<VolumeReductionState> get stateStream => _stateController.stream;
  
  // Platform channel para comunicación con código nativo
  static const platform = MethodChannel('alarm_volume_control');
  
  /// Inicia la reducción temporal de volumen
  Future<void> startVolumeReduction({
    required int tempVolumePercent,
    required int durationSeconds,
  }) async {
    print('VolumeReductionService - Starting volume reduction: $tempVolumePercent% for ${durationSeconds}s (current active: $_isActive)');
    
    if (_isActive) {
      print('VolumeReductionService - Stopping existing reduction before starting new one');
      await stopVolumeReduction();
    }
    
    _isActive = true;
    _tempVolumePercent = tempVolumePercent;
    _totalDurationSeconds = durationSeconds;
    _remainingSeconds = durationSeconds;
    
    // Llamar al código nativo para aplicar la reducción
    try {
      await platform.invokeMethod('setTemporaryVolumeReduction', {
        'reductionPercent': tempVolumePercent,
        'durationSeconds': durationSeconds,
      });
      print('VolumeReductionService - Native call successful: $tempVolumePercent% for ${durationSeconds}s');
    } catch (e) {
      print('VolumeReductionService - Error starting volume reduction: $e');
      _resetState();
      return;
    }
    
    // Iniciar el timer global
    _startGlobalTimer();
    
    // Notificar el cambio de estado
    _notifyStateChange();
    print('VolumeReductionService - Volume reduction started successfully, state notified');
  }
  
  /// Detiene la reducción temporal de volumen
  Future<void> stopVolumeReduction() async {
    print('VolumeReductionService - Stop volume reduction called (current active: $_isActive)');
    
    if (!_isActive) {
      print('VolumeReductionService - No active reduction to stop');
      return;
    }
    
    _globalTimer?.cancel();
    _globalTimer = null;
    
    // Llamar al código nativo para cancelar la reducción
    try {
      await platform.invokeMethod('cancelTemporaryVolumeReduction');
      print('VolumeReductionService - Volume reduction stopped manually via native call');
    } catch (e) {
      print('VolumeReductionService - Error stopping volume reduction: $e');
    }
    
    _resetState();
    _notifyStateChange();
    print('VolumeReductionService - Volume reduction stopped, state reset and notified');
  }
  
  /// Inicia el timer global que cuenta hacia atrás
  void _startGlobalTimer() {
    _globalTimer?.cancel();
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;
      
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _onVolumeReductionExpired();
      } else {
        _notifyStateChange();
      }
    });
  }
  
  /// Maneja la expiración automática de la reducción
  Future<void> _onVolumeReductionExpired() async {
    print('Volume reduction expired automatically');
    
    // Llamar al código nativo para cancelar la reducción
    try {
      await platform.invokeMethod('cancelTemporaryVolumeReduction');
      print('Volume reduction cancelled automatically after expiration');
    } catch (e) {
      print('Error cancelling volume reduction after expiration: $e');
    }
    
    _resetState();
    _notifyStateChange();
  }
  
  /// Resetea el estado interno
  void _resetState() {
    _isActive = false;
    _remainingSeconds = 0;
    _totalDurationSeconds = 0;
    _globalTimer?.cancel();
    _globalTimer = null;
  }
  
  /// Notifica cambios de estado a todos los listeners
  void _notifyStateChange() {
    final state = VolumeReductionState(
      isActive: _isActive,
      remainingSeconds: _remainingSeconds,
      totalDurationSeconds: _totalDurationSeconds,
      tempVolumePercent: _tempVolumePercent,
    );
    print('VolumeReductionService - Notifying state change: active=$_isActive, remaining=${_remainingSeconds}s, total=${_totalDurationSeconds}s, volume=${_tempVolumePercent}%');
    _stateController.add(state);
  }
  
  /// Sincroniza el estado con una reducción ya activa
  /// Útil cuando se navega entre pantallas
  void syncWithActiveReduction({
    required int remainingSeconds,
    required int totalDurationSeconds,
    required int tempVolumePercent,
  }) {
    if (remainingSeconds <= 0) {
      _resetState();
    } else {
      _isActive = true;
      _remainingSeconds = remainingSeconds;
      _totalDurationSeconds = totalDurationSeconds;
      _tempVolumePercent = tempVolumePercent;
      
      // Reiniciar el timer con el tiempo restante
      _startGlobalTimer();
    }
    
    _notifyStateChange();
  }
  
  /// Obtiene el estado actual como un objeto
  VolumeReductionState getCurrentState() {
    return VolumeReductionState(
      isActive: _isActive,
      remainingSeconds: _remainingSeconds,
      totalDurationSeconds: _totalDurationSeconds,
      tempVolumePercent: _tempVolumePercent,
    );
  }
  
  /// Limpia recursos al cerrar la aplicación
  void dispose() {
    _globalTimer?.cancel();
    _stateController.close();
  }
}

/// Clase que representa el estado de la reducción de volumen
class VolumeReductionState {
  final bool isActive;
  final int remainingSeconds;
  final int totalDurationSeconds;
  final int tempVolumePercent;
  
  const VolumeReductionState({
    required this.isActive,
    required this.remainingSeconds,
    required this.totalDurationSeconds,
    required this.tempVolumePercent,
  });
  
  /// Calcula el progreso como un valor entre 0.0 y 1.0
  double get progress {
    if (totalDurationSeconds <= 0) return 0.0;
    return (totalDurationSeconds - remainingSeconds) / totalDurationSeconds;
  }
  
  @override
  String toString() {
    return 'VolumeReductionState(isActive: $isActive, remaining: ${remainingSeconds}s, total: ${totalDurationSeconds}s, volume: $tempVolumePercent%)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VolumeReductionState &&
        other.isActive == isActive &&
        other.remainingSeconds == remainingSeconds &&
        other.totalDurationSeconds == totalDurationSeconds &&
        other.tempVolumePercent == tempVolumePercent;
  }
  
  @override
  int get hashCode {
    return isActive.hashCode ^
        remainingSeconds.hashCode ^
        totalDurationSeconds.hashCode ^
        tempVolumePercent.hashCode;
  }
}