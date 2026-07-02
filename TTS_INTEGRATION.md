Guía de Reemplazo Total TTS a Piper (Flutter + Android)
1. Propósito
Esta guía define cómo reemplazar totalmente cualquier implementación TTS previa por una implementación Piper-only en una app Flutter/Android.
Está escrita para que una IA de otro proyecto pueda ejecutar la migración sin depender de detalles internos de este repositorio.

Resultado esperado:

No usar motores TTS del sistema para síntesis principal.
Síntesis y reproducción con Piper en todos los flujos de voz.
Configuración homogénea entre módulos (alarmas, recordatorios, etc.).
2. Principios de Diseño
Una sola ruta de ejecución: Piper-only.
Sin fallback silencioso a motores legacy.
Fallos explícitos, trazables y recuperables por UX.
Configuración por entidad + defaults globales.
Control de volumen de reproducción consistente en Android.
Comportamiento determinista offline (si modelo descargado).
3. Alcance de Migración
Incluye:

Modelo de datos TTS
Pantallas de configuración
Runtime de reproducción
Descarga y validación de modelos
Persistencia y migración de datos legacy
Testing y observabilidad
No incluye:

Nuevos proveedores TTS distintos de Piper
Cambios de dominio no relacionados con voz
4. Arquitectura Objetivo
4.1 Capa de Dominio (contrato único TTS)
Definir un contrato único TtsConfig y reutilizarlo en todas las entidades que hablen.

Campos mínimos:

enabled: bool
provider: string (valor fijo piper)
piperVoiceId: string
volumePercent: int (0-100)
pitch: double (si la implementación lo soporta)
repeatCount: int (1, 3, 5, -1 indefinido)
repeatDelaySeconds: int
speechRate: double (opcional, si se usa en síntesis)
usePrefix: bool (opcional, sólo si requisito funcional)
localeHint: string (opcional, para selección de voz)
Regla:

Eliminar campos exclusivos de proveedores legacy (por ejemplo voz específica de motor del sistema).
4.2 Capa de Aplicación (orquestación)
Servicios requeridos:

VoiceCatalogService: catálogo de voces disponibles y metadatos.
VoiceDownloadService: descarga, progreso, cancelación, validación y borrado.
TtsSynthesisService: text to wav.
TtsPlaybackService: reproducción, repetición, stop, cleanup.
TtsSessionCoordinator: orquesta síntesis + reproducción + control de volumen + callbacks.
4.3 Capa de Infraestructura
Persistencia de modelos en almacenamiento local de app.
Archivo temporal wav por sesión.
Limpieza de archivos temporales al finalizar/reintentar.
Reintento de descarga con política exponencial limitada.
5. Flujo Runtime Piper-only
Resolver TtsConfig efectivo (entidad > default global).
Validar enabled.
Validar modelo descargado de piperVoiceId.
Ajustar volumen de stream de reproducción en Android y guardar volumen previo.
Sintetizar texto a wav.
Reproducir wav.
Aplicar repetición según repeatCount y repeatDelaySeconds.
Al stop/finalizar: detener reproducción, limpiar recursos, restaurar volumen original.
Regla crítica:

Si falla síntesis o modelo no existe, NO ejecutar fallback legacy.
Mostrar error de UX y opción de descarga/reintento.
6. UX de Configuración Recomendada
Todos los módulos deben compartir los mismos controles TTS:

Switch activar/desactivar voz.
Selector de voz Piper.
Volumen.
Tono (si aplica).
Repeticiones y pausa.
Botón de preview.
Estado del modelo (descargado/no descargado/progreso/error).
Acciones gestionar voces (descargar, actualizar, eliminar).
Evitar:

Controles de proveedor legacy.
Diferencias de configuración entre módulos sin justificación funcional.
7. Migración de Datos Legacy
7.1 Objetivo
Convertir configuraciones existentes al nuevo contrato sin romper compatibilidad de usuario.

7.2 Reglas sugeridas
Si existe piperVoiceId válido: conservar.
Si no existe piperVoiceId:
asignar voz por defecto global basada en idioma
marcar estado modelo pendiente de descarga
Mapear campos comunes:
enableTts -> enabled
ttsVolume -> volumePercent
ttsPitch -> pitch
ttsRepeatCount -> repeatCount
ttsRepeatDelaySeconds -> repeatDelaySeconds
Eliminar o ignorar campos legacy no soportados.
Guardar revision de esquema para evitar migrar dos veces.
7.3 Estrategia de ejecución
Migración en arranque, idempotente.
Transacción por lote o por entidad con rollback por fallo.
Log de cantidad migrada, omitida y fallida.
8. Cutover Seguro (sin downtime funcional)
Fase 1: Preparación

Integrar servicios Piper-only sin activar en producción.
Añadir métricas y logs.
Fase 2: Dual-write opcional corto

Guardar nuevo contrato y mantener lectura legacy solo para migración.
Fase 3: Lectura Piper-only

Runtime usa solo nuevo contrato.
Legacy solo lectura para rescate puntual.
Fase 4: Limpieza

Eliminar fallback y campos legacy.
Congelar esquema final.
9. Requisitos No Funcionales
Latencia de primer audio aceptable por caso de uso.
Soporte offline total tras descarga de modelo.
Recuperación robusta ante descarga interrumpida.
Control de almacenamiento y limpieza de modelos obsoletos.
Trazabilidad completa de errores de síntesis/reproducción.
Evitar bloqueos de UI durante síntesis larga (aislar trabajo pesado).
10. Observabilidad y Telemetría
Eventos mínimos:

tts_play_requested
tts_model_missing
tts_model_download_started
tts_model_download_failed
tts_synthesis_started
tts_synthesis_failed
tts_play_started
tts_play_completed
tts_play_stopped
tts_volume_restored
Campos mínimos por evento:

module
entityId
voiceId
durationMs
errorType
offlineState
appVersion
11. Matriz de Pruebas Obligatorias
11.1 Unitarias
Resolución de configuración efectiva.
Reglas de migración legacy -> nuevo contrato.
Repetición finita e indefinida.
Limpieza de archivos temporales.
11.2 Integración
Síntesis exitosa con modelo válido.
Falla por modelo faltante.
Descarga y posterior reproducción.
Restauración de volumen tras stop/fallo.
11.3 Manuales (Android real)
Primer uso sin modelo descargado.
Uso offline con modelo descargado.
Interrupción de red durante descarga.
Cambio de voz Piper y preview.
Alarma/recordatorio simultáneo (concurrencia de audio).
Repetición indefinida y detención manual.
12. Criterios de Aceptación
Ningún flujo funcional usa síntesis legacy en runtime.
Todos los módulos usan la misma UX TTS.
Configuraciones previas migradas sin pérdida de preferencias clave.
Error handling visible para usuario y trazable para soporte.
Pruebas críticas aprobadas en CI y en dispositivo real.
13. Checklist de Implementación Para IA
Crear contrato TtsConfig unificado.
Reemplazar lecturas legacy por TtsConfig.
Implementar pipeline Piper-only de síntesis y reproducción.
Integrar control y restauración de volumen Android.
Unificar UI TTS en todas las pantallas.
Implementar migración idempotente de datos.
Eliminar fallback legacy.
Añadir telemetría de voz.
Ejecutar matriz de pruebas.
Hacer cleanup de código y campos deprecados.
14. Riesgos y Mitigaciones
Latencia alta de primer audio
Mitigación: precarga de modelo y warmup opcional.
Crecimiento de almacenamiento
Mitigación: política de retención y borrado de voces no usadas.
Fricción UX en primer uso
Mitigación: onboarding corto de descarga de voz y progreso claro.
Regresiones en flujos críticos
Mitigación: pruebas end-to-end por módulo y feature flag en rollout.
Si quieres, en el siguiente paso te lo dejo ya materializado como archivo real en la raíz con ese nombre exacto y con un bloque inicial de metadatos para consumo aún más robusto por otra IA.
