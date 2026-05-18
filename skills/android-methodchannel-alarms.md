---
skill: android-methodchannel-alarms
version: 1.0.0
domain: android-native-bridge
trigger_phrases:
  - "ajusta el methodchannel de alarmas"
  - "modifica la parte nativa android de alarmas"
  - "sincroniza payload flutter y kotlin"
applies_to:
  - "*.dart"
  - "*.kt en android/app/src/main/kotlin"
---

# Skill: Android MethodChannel Alarms

## Propósito
Modificar integraciones Flutter-Android para alarmas y volumen manteniendo compatibilidad de llaves, rutas y permisos.
Se usa cuando hay cambios en payloads de `setAlarm`, `snoozeAlarm`, `stopAlarm` o control de volumen.

## Comportamiento Esperado

### Siempre hacer
- Mantener nombres de canal existentes: `com.andodevs.the_good_alarm/alarm` y `alarm_volume_control`.
- Validar que los argumentos enviados desde Flutter coincidan 1:1 con Kotlin.
- Conservar manejo de permisos exactos (alarmas exactas, DND, overlay, bateria).

### Nunca hacer
- No renombrar llaves de payload sin actualizar ambos lados y documentarlo.
- No eliminar rutas/acciones Android ya usadas por receivers activos.

## Proceso Paso a Paso
1. Ubicar punto Dart que invoca el canal (`lib/alarm_edit_screen.dart`, `lib/alarm_screen.dart`).
2. Ubicar handler Kotlin en `MainActivity.kt` y receivers relacionados.
3. Aplicar cambio espejo en ambos lados (tipo, nombre y default values).
4. Ejecutar `dart analyze <archivo_dart_modificado.dart>` y validar flujo real con `flutter run` en Android.

## Plantilla de Salida
```dart
await _channel.invokeMethod('setAlarm', {
  'id': alarm.id,
  'hour': alarm.time.hour,
  'minute': alarm.time.minute,
  'maxSnoozes': alarm.maxSnoozes,
});
```

```kotlin
val id = call.argument<Int>("id") ?: return@setMethodCallHandler
val hour = call.argument<Int>("hour") ?: return@setMethodCallHandler
val minute = call.argument<Int>("minute") ?: return@setMethodCallHandler
```

## Criterios de Éxito
- [ ] Canal y metodos mantienen compatibilidad entre Dart y Kotlin.
- [ ] No hay regresion en permisos ni alarmas exactas.
- [ ] `dart analyze` no muestra errores en Dart modificado.

## Referencias del Proyecto
- Archivos relacionados: `lib/alarm_edit_screen.dart`, `lib/alarm_screen.dart`, `android/app/src/main/kotlin/com/example/the_good_alarm/MainActivity.kt`
- Comandos relacionados: `flutter run`, `dart analyze`, `flutter build apk`
- Convenciones aplicadas: bridge Flutter-Android con MethodChannel y receivers
