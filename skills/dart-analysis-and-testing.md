---
skill: dart-analysis-and-testing
version: 1.0.0
domain: quality-gates
trigger_phrases:
  - "valida cambios con analyze"
  - "ejecuta control de calidad del cambio"
  - "revisa si rompi algo"
applies_to:
  - "*.dart"
  - "pull requests y cambios en archivos existentes"
---

# Skill: Dart Analysis and Testing

## Propósito
Aplicar una verificacion minima obligatoria de calidad despues de cambios en Dart/Flutter.
Se usa para confirmar que los archivos editados no introducen errores.

## Comportamiento Esperado

### Siempre hacer
- Ejecutar `dart analyze` apuntando al archivo modificado.
- Reportar errores bloqueantes con archivo y causa concreta.
- Ejecutar `flutter test` cuando el cambio toca logica de repositorios/modelos o scheduling.

### Nunca hacer
- No marcar como validado sin correr al menos `dart analyze` por archivo tocado.
- No ocultar errores bajo supuestos de "se arregla despues".

## Proceso Paso a Paso
1. Identificar lista de archivos `.dart` modificados.
2. Correr `dart analyze <ruta_archivo>` por cada uno.
3. Aplicar regla de alcance para tests:
  - Si hay cambios en `lib/services/`, `lib/models/` o schedulers, correr `flutter test`.
  - Si son cambios de UI acotados en `lib/screens/` o `lib/widgets/`, documentar que no se ejecuto `flutter test` por alcance.
4. Entregar resultado con estado: OK / Con errores y acciones recomendadas.

## Plantilla de Salida
```text
Validacion tecnica
- dart analyze lib/services/alarm_repository.dart -> OK
- dart analyze lib/models/medication_models.dart -> OK
- flutter test -> 0 fallos / o detallar fallos
```

## Criterios de Éxito
- [ ] Todos los archivos tocados fueron analizados.
- [ ] Errores bloqueantes quedaron identificados o corregidos.
- [ ] Se informa claramente si se ejecutaron o no tests.

## Referencias del Proyecto
- Archivos relacionados: `analysis_options.yaml`, `lib/`, `pubspec.yaml`
- Comandos relacionados: `dart analyze`, `flutter test`, `flutter run`
- Convenciones aplicadas: calidad minima basada en analisis estatico y pruebas
