---
skill: medication-habit-scheduling
version: 1.0.0
domain: scheduling-domain
trigger_phrases:
  - "implementa recordatorios de medicacion"
  - "ajusta scheduler de habitos"
  - "corrige programacion de ocurrencias"
applies_to:
  - "*.dart"
  - "archivos existentes en lib/services y lib/models de habitos/medicacion"
---

# Skill: Medication Habit Scheduling

## Propósito
Modificar reglas de programacion de habitos y medicamentos sin romper ocurrencias, confirmaciones y sincronizacion.
Se aplica unicamente a schedulers, repositorios y modelos del dominio.

## Comportamiento Esperado

### Siempre hacer
- Respetar `repeatMode`, `weekdays`, `times` y confirmaciones de toma.
- Mantener consistencia entre scheduler, repositorio y modelo del dominio.
- Añadir `print` de depuracion en puntos clave de flujo (calculo, persistencia y confirmacion).

### Nunca hacer
- No alterar semantica de horas/zonas sin validar impacto en ocurrencias.
- No desacoplar scheduler del repositorio existente.
- No implementar cambios de UI en `lib/screens/` dentro de esta skill.

## Proceso Paso a Paso
1. Revisar modelos en `lib/models/medication_models.dart` y `lib/models/habit_models.dart`.
2. Ajustar logica en `lib/services/medication_scheduler.dart` o `lib/services/habit_scheduler.dart`.
3. Verificar que el contrato de datos siga compatible con las pantallas, sin editar UI en esta skill.
4. Ejecutar `dart analyze <archivo_modificado.dart>` para cada archivo tocado.

## Plantilla de Salida
```dart
print('scheduler start: ${item.id}');
final next = _computeNextOccurrence(item);
print('next occurrence: $next');
await repository.saveNextOccurrence(item.id, next);
print('scheduler persisted: ${item.id}');
```

## Criterios de Éxito
- [ ] La recurrencia se calcula correctamente para los modos soportados.
- [ ] Se mantiene trazabilidad con prints en pasos criticos.
- [ ] `dart analyze` no reporta errores en los archivos modificados.

## Referencias del Proyecto
- Archivos relacionados: `lib/services/medication_scheduler.dart`, `lib/services/habit_scheduler.dart`, `lib/screens/medications_screen.dart`
- Comandos relacionados: `flutter run`, `dart analyze`, `flutter test`
- Convenciones aplicadas: flujo dominio -> servicio -> pantalla, logs de depuracion con print
