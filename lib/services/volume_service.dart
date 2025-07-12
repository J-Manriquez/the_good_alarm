import 'dart:async';
import 'package:flutter/services.dart';
import '../modelo_alarm.dart';

class VolumeService {
  static const MethodChannel _channel = MethodChannel('alarm_volume_control');
  
  Timer? _volumeRampTimer;
  Timer? _tempVolumeTimer;
  bool _isRampingUp = false;
  bool _isTempReduced = false;
  double _originalVolume = 1.0;
  double _currentVolume = 0.0;
  Alarm? _currentAlarm;

  /// Inicia el control de volumen para una alarma
  Future<void> startVolumeControl(int maxVolumePercent, int rampUpDurationSeconds) async {
    try {
      // Usar únicamente el método nativo que está implementado correctamente
      await _channel.invokeMethod('startVolumeControl', {
        'maxVolumePercent': maxVolumePercent,
        'rampUpDurationSeconds': rampUpDurationSeconds,
      });
      print('Volume control started: $maxVolumePercent% max, ${rampUpDurationSeconds}s ramp');
    } catch (e) {
      print('Error starting volume control: $e');
    }
  }

  /// Inicia el control de volumen para una alarma (método legacy)
  Future<void> startAlarmVolumeControl(Alarm alarm) async {
    _currentAlarm = alarm;
    _originalVolume = await _getSystemVolume();
    
    // Iniciar con volumen bajo y escalar gradualmente
    await _setSystemVolume(0.1); // Comenzar al 10%
    _currentVolume = 0.1;
    
    _startVolumeRampUp(alarm);
  }

  /// Detiene el control de volumen
  Future<void> stopVolumeControl() async {
    try {
      // Usar únicamente el método nativo que está implementado correctamente
      await _channel.invokeMethod('stopVolumeControl');
      print('Volume control stopped');
    } catch (e) {
      print('Error stopping volume control: $e');
    }
  }

  /// Detiene todo el control de volumen (método legacy)
  Future<void> stopAlarmVolumeControl() async {
    _volumeRampTimer?.cancel();
    _tempVolumeTimer?.cancel();
    _isRampingUp = false;
    _isTempReduced = false;
    _currentAlarm = null;
    
    // Restaurar volumen original del sistema
    await _setSystemVolume(_originalVolume);
  }

  /// Inicia el escalado gradual del volumen
  void _startVolumeRampUp(Alarm alarm) {
    if (alarm.volumeRampUpDurationSeconds <= 0) {
      // Si no hay escalado, ir directamente al volumen máximo
      _setSystemVolume(alarm.maxVolumePercent / 100.0);
      _currentVolume = alarm.maxVolumePercent / 100.0;
      return;
    }

    _isRampingUp = true;
    final targetVolume = alarm.maxVolumePercent / 100.0;
    final startVolume = 0.1;
    final volumeIncrement = (targetVolume - startVolume) / alarm.volumeRampUpDurationSeconds;
    
    _volumeRampTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRampingUp || _isTempReduced) {
        timer.cancel();
        return;
      }
      
      _currentVolume += volumeIncrement;
      
      if (_currentVolume >= targetVolume) {
        _currentVolume = targetVolume;
        _setSystemVolume(_currentVolume);
        timer.cancel();
        _isRampingUp = false;
      } else {
        _setSystemVolume(_currentVolume);
      }
    });
  }

  /// Aplica reducción temporal del volumen
  Future<void> setTemporaryVolumeReduction(int reductionPercent, int durationSeconds) async {
    try {
      // Usar únicamente el método nativo que está implementado correctamente
      await _channel.invokeMethod('setTemporaryVolumeReduction', {
        'reductionPercent': reductionPercent,
        'durationSeconds': durationSeconds,
      });
      print('Temporary volume reduction set: $reductionPercent% for ${durationSeconds}s');
    } catch (e) {
      print('Error setting temporary volume reduction: $e');
    }
  }

  /// Aplica reducción temporal del volumen (método legacy)
  Future<void> applyTemporaryVolumeReduction() async {
    if (_currentAlarm == null || _isTempReduced) return;
    
    _isTempReduced = true;
    final tempVolume = _currentAlarm!.tempVolumeReductionPercent / 100.0;
    
    // Pausar el escalado si está activo
    if (_isRampingUp) {
      _volumeRampTimer?.cancel();
      _isRampingUp = false;
    }
    
    await _setSystemVolume(tempVolume);
    
    // Programar la restauración del volumen
    _tempVolumeTimer = Timer(
      Duration(seconds: _currentAlarm!.tempVolumeReductionDurationSeconds),
      () async {
        _isTempReduced = false;
        
        // Restaurar al volumen máximo configurado
        final maxVolume = _currentAlarm!.maxVolumePercent / 100.0;
        await _setSystemVolume(maxVolume);
        _currentVolume = maxVolume;
      },
    );
  }

  /// Cancela la reducción temporal del volumen
  Future<void> cancelTemporaryVolumeReduction() async {
    try {
      // Cancelar la reducción temporal usando el método nativo
      await _channel.invokeMethod('cancelTemporaryVolumeReduction');
      print('Temporary volume reduction cancelled');
    } catch (e) {
      print('Error cancelling temporary volume reduction: $e');
    }
  }

  /// Cancela la reducción temporal del volumen (método legacy)
  Future<void> _cancelTemporaryVolumeReductionLegacy() async {
    if (!_isTempReduced || _currentAlarm == null) return;
    
    _tempVolumeTimer?.cancel();
    _isTempReduced = false;
    
    // Restaurar al volumen máximo configurado
    final maxVolume = _currentAlarm!.maxVolumePercent / 100.0;
    await _setSystemVolume(maxVolume);
    _currentVolume = maxVolume;
  }

  /// Obtiene el volumen actual del sistema
  Future<double> _getSystemVolume() async {
    try {
      final result = await _channel.invokeMethod('getVolume');
      return (result as double?) ?? 1.0;
    } catch (e) {
      print('Error obteniendo volumen del sistema: $e');
      return 1.0;
    }
  }

  /// Establece el volumen del sistema
  Future<void> _setSystemVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (e) {
      print('Error estableciendo volumen del sistema: $e');
    }
  }

  /// Getters para el estado actual
  bool get isRampingUp => _isRampingUp;
  bool get isTempReduced => _isTempReduced;
  double get currentVolume => _currentVolume;
  Alarm? get currentAlarm => _currentAlarm;
}