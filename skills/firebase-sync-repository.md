---
skill: firebase-sync-repository
version: 1.0.0
domain: sync-cloud-local
trigger_phrases:
  - "sincroniza este modelo con firebase"
  - "ajusta el repositorio para cloud sync"
  - "corrige conflictos entre local y firestore"
applies_to:
  - "*.dart"
  - "archivos existentes en lib/services y lib/models"
---

# Skill: Firebase Sync Repository

## Propósito
Aplicar cambios en sincronizacion local-nube sin romper consistencia de datos ni conflictos de versionado.
Se usa para alarmas, habitos, medicamentos y calendarios.

## Comportamiento Esperado

### Siempre hacer
- Preservar campos de sincronizacion: `syncToCloud`, `revision`, `fieldUpdatedAt`, `deletedAt`.
- Mantener patrones de merge/patch de repositorios existentes (`*_repository.dart`).
- Usar `try/catch` en operaciones async de Firebase y persistencia local.

### Nunca hacer
- No borrar campos de sincronizacion para “simplificar” modelos.
- No escribir directo en UI logica de reconciliacion cloud-local.

## Proceso Paso a Paso
1. Identificar modelo y repositorio objetivo en `lib/models/` y `lib/services/`.
2. Ajustar serializacion/parches conservando `revision` y marcas de borrado logico.
3. Validar integridad de campos sucios (`dirty fields`) y push/pull en repositorio.
4. Ejecutar `dart analyze <archivo_modificado.dart>` por cada archivo tocado.

## Plantilla de Salida
```dart
try {
  final updated = entity.copyWith(
    updatedAt: DateTime.now(),
    revision: entity.revision + 1,
  );
  await local.upsert(updated);
  if (updated.syncToCloud) {
    await cloud.applyPatch(updated.id, updated.toJson());
  }
} catch (e) {
  print('sync error: $e');
  rethrow;
}
```

## Criterios de Éxito
- [ ] Se conservan campos de sincronizacion del modelo.
- [ ] El flujo local-cloud sigue funcionando en el repositorio.
- [ ] `dart analyze` no reporta errores en archivos modificados.

## Referencias del Proyecto
- Archivos relacionados: `lib/services/alarm_repository.dart`, `lib/services/*_firebase_service.dart`, `lib/models/`
- Comandos relacionados: `flutter run`, `dart analyze`, `flutter test`
- Convenciones aplicadas: repositorio por feature, persistencia local + Firestore
