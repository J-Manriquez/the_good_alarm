---
skill: documentation-txt-maintenance
version: 1.0.0
domain: technical-documentation
trigger_phrases:
  - "actualiza la documentacion tecnica"
  - "modifica el txt de flujo"
  - "documenta estos cambios del feature"
applies_to:
  - "*.txt"
  - "archivos existentes de documentacion tecnica"
---

# Skill: Documentation TXT Maintenance

## Propósito
Actualizar documentos `.txt` del proyecto para reflejar cambios funcionales sin perder consistencia historica.
Se usa en archivos de flujo, estructura y planes tecnicos.

## Comportamiento Esperado

### Siempre hacer
- Editar descripciones existentes para alinearlas al cambio implementado.
- Usar lenguaje tecnico claro y terminos reales del proyecto.
- Mantener referencias consistentes a rutas, servicios y modelos reales.

### Nunca hacer
- No crear secciones artificiales de "cambios recientes" si no fueron solicitadas.
- No documentar funcionalidades no implementadas realmente.

## Proceso Paso a Paso
1. Identificar el `.txt` relevante al feature (flujo, estructura o plan).
2. Comparar implementacion real con texto actual y detectar desfases.
3. Actualizar o ampliar los apartados existentes, sin romper la estructura del documento.
4. Agregar trazabilidad: indicar que archivo funcional fue modificado y en que apartado del `.txt` se reflejo.
5. Verificar que nombres de clases/rutas/comandos coincidan con el codigo vigente.

## Plantilla de Salida
```text
## 2. COMUNICACION FLUTTER-ANDROID VIA PLATFORM CHANNELS
- Canal principal: com.andodevs.the_good_alarm/alarm
- Metodo actualizado: setAlarm ahora incluye tempVolumeReductionDurationSeconds
- Compatibilidad: payload Dart y Kotlin alineados
```

## Criterios de Éxito
- [ ] El documento refleja el comportamiento actual del codigo.
- [ ] No se agregan secciones no solicitadas.
- [ ] Existe trazabilidad explicita entre codigo cambiado y texto actualizado.
- [ ] Terminologia y rutas coinciden con el repositorio.

## Referencias del Proyecto
- Archivos relacionados: `flujo_configuracion_alarmas.txt`, `firebase-structure.txt`, `historial.txt`
- Comandos relacionados: `dart analyze`, `flutter run`
- Convenciones aplicadas: documentacion incremental y factual sobre implementacion real
