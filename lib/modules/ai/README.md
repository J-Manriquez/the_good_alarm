# Módulo IA — `lib/modules/ai/`

Carpeta autocontenida diseñada para copiarse a otra app Flutter sin depender del resto del proyecto. Ejecuta modelos de lenguaje **100 % local** (sin nube, sin APIs) vía `flutter_gemma` (motor LiteRT-LM/MediaPipe). Compatible con cualquier dispositivo Android ARM64 o x86_64 — a diferencia de AICore/Gemini Nano, no depende de un allowlist de hardware.

---

## Estructura de archivos

```
lib/modules/ai/
├── ai_module.dart                    ← barrel export (importa todo con un solo import)
├── models/
│   ├── ai_model_catalog.dart         ← catálogo de modelos + tipos de archivo
│   └── ai_model_config.dart          ← config por modelo (template, temperatura, etc.)
├── services/
│   ├── ai_model_repository.dart      ← descarga, verificación SHA-256, almacenamiento
│   └── ai_service.dart               ← API pública única (usa esto desde la app)
└── screens/
    ├── ai_model_manager_screen.dart  ← pantalla de gestión (descargar/activar/eliminar)
    ├── ai_model_config_screen.dart   ← pantalla de configuración avanzada por modelo
    └── ai_chat_screen.dart           ← pantalla de chat de prueba
```

---

## Dependencias requeridas (`pubspec.yaml`)

```yaml
dependencies:
  flutter_gemma: ^0.16.1          # motor LiteRT-LM/MediaPipe
  flutter_secure_storage: ^9.2.2  # token HF + config por modelo
  path_provider: ^2.1.5           # directorio de almacenamiento
  crypto: ^3.0.6                  # verificación SHA-256
  file_picker: ^8.3.7             # selector de carpeta personalizada (modo custom)
  permission_handler: ^11.3.1     # permisos de almacenamiento externo
```

> **Nota Android:** añadir en `android/app/build.gradle.kts`:
> ```kotlin
> ndkVersion = "28.2.13676358"
> ```
> y en `android/settings.gradle.kts` AGP ≥ `8.9.1`.

---

## API pública — `AiService`

Único punto de entrada para la app anfitriona. Singleton accesible con `AiService.instance`.

### Ciclo de vida completo

```dart
import 'package:tu_app/modules/ai/ai_module.dart';

final ai = AiService.instance;

// 1. Verificar soporte del dispositivo (requiere ARM64 o x86_64)
final soportado = await ai.isDeviceSupported();
if (!soportado) return; // mostrar mensaje al usuario

// 2. Listar modelos disponibles en el catálogo
final modelos = ai.availableModels(); // List<AiModelCatalogEntry>

// 3. Descargar un modelo (puede tardar minutos dependiendo del tamaño)
await ai.downloadModel(
  'gemma3n-e2b',
  onProgress: (pct, receivedBytes, totalBytes) {
    print('Descargando: $pct% ($receivedBytes / ${totalBytes ?? "?"} bytes)');
  },
);

// 4. Establecer el modelo activo
await ai.setActiveModel('gemma3n-e2b');

// 5. Verificar que el modelo esté listo para generar
final listo = await ai.isModelReady(); // true si hay modelo activo descargado

// 6. Generar texto
final respuesta = await ai.generateText(
  prompt: 'Resume esto en una frase: ...',
  systemInstruction: 'Eres un asistente conciso.',
  temperature: 0.7,       // fallback; la config guardada tiene prioridad
  maxOutputTokens: 256,   // fallback; la config guardada tiene prioridad
);
print(respuesta);

// 7. Liberar modelo de la RAM sin borrar el archivo
ai.unload();
```

### Referencia completa de métodos

| Método | Descripción |
|---|---|
| `isDeviceSupported()` | `true` si el dispositivo tiene ABIs ARM64 o x86_64 |
| `availableModels()` | Lista completa del catálogo (`List<AiModelCatalogEntry>`) |
| `downloadedModelIds()` | IDs de los modelos ya descargados |
| `isModelDownloaded(id)` | `true` si el archivo del modelo existe en disco |
| `downloadModel(id, onProgress)` | Descarga con HTTPS, verifica SHA-256, reanuda si hay archivo parcial |
| `deleteModel(id)` | Borra el archivo de disco; limpia caché si era el activo |
| `activeModelId()` | ID del modelo activo guardado en `FlutterSecureStorage` |
| `setActiveModel(id)` | Cambia el modelo activo (limpia el InferenceModel en RAM) |
| `isModelReady()` | `true` si hay modelo activo Y está descargado |
| `generateText({prompt, systemInstruction, temperature, maxOutputTokens})` | Genera texto. Lee `AiModelConfig` guardada; los parámetros pasados son fallback |
| `modelConfig(id)` | Lee la `AiModelConfig` persistida para ese modelo |
| `saveModelConfig(config)` | Guarda la config del modelo (limpia caché si era el activo) |
| `modelsDirectoryPath()` | Ruta absoluta de la carpeta donde se guardan los modelos |
| `storageLocation()` | Ubicación configurada (`internal` / `externalApp` / `custom`) |
| `setStorageLocation(location, customPath)` | Cambia dónde se guardan los modelos |
| `unload()` | Libera el `InferenceModel` de la RAM (no borra el archivo) |

---

## Configuración avanzada por modelo — `AiModelConfig`

Cada modelo puede tener su propia configuración persistida en `FlutterSecureStorage`. Se aplica automáticamente en `generateText()`.

```dart
// Leer configuración actual
final cfg = await ai.modelConfig('smollm2-360m');

// Modificar y guardar
await ai.saveModelConfig(cfg.copyWith(
  template: AiChatTemplate.chatml,      // ver templates más abajo
  systemInstruction: 'Eres un asistente en español.',
  temperature: 0.5,
  maxOutputTokens: 512,
  topK: 40,
));
```

### Templates de chat — `AiChatTemplate`

| Valor | Cuándo usar |
|---|---|
| `auto` | Solo para Gemma (IT). flutter_gemma aplica su template interno |
| `chatml` | **SmolLM, SmolLM2, Qwen3, Phi-4** — usa tokens `<\|im_start\|>` |
| `llama` | Llama 3, Mistral — usa tokens `[INST]` |
| `raw` | Depuración o modelos base (sin wrapping) |
| `custom` | Template personalizado con `{system}`, `{user}`, `{assistant}` |

> **Regla práctica**: modelos con `engineModelType: ModelType.gemmaIt` usan `auto`; todos los demás (`ModelType.general`) generan mejores resultados con `chatml`.

---

## Catálogo de modelos incluido

Todos son archivos `.litertlm` / `.task` ejecutables con LiteRT-LM/MediaPipe. Ordenados por tamaño:

| ID | Nombre | Tamaño | RAM mín. | Rating | Token HF |
|---|---|---|---|---|---|
| `smollm-135m` | SmolLM 135M | ~167 MB | 1 GB | ★ | No |
| `gemma3-270m` | Gemma 3 270M | ~304 MB | 1.5 GB | ★★ | **Sí** |
| `smollm2-360m` | SmolLM2 360M | ~374 MB | 1.5 GB | ★★ | No |
| `qwen3-0.6b` | Qwen3 0.6B ⚠️ | ~497 MB | 2 GB | ★★ | No |
| `gemma3-1b-it` | Gemma 3 1B IT | ~584 MB | 3 GB | ★★★ | **Sí** |
| `gemma4-e2b` | Gemma 4 E2B | ~2.4 GB | 5 GB | ★★★★ | **Sí** |
| `gemma3n-e2b` | Gemma 3n E2B | ~3.4 GB | 6 GB | ★★★★ | **Sí** |
| `phi4-mini` | Phi-4 Mini | ~3.6 GB | 8 GB | ★★★★ | No |
| `gemma3n-e4b` | Gemma 3n E4B | ~4.6 GB | 8 GB | ★★★★★ | **Sí** |
| `gemma4-e4b` | Gemma 4 E4B | ~3.4 GB | 8 GB | ★★★★★ | **Sí** |

⚠️ `qwen3-0.6b` es experimental: puede crashear en algunos dispositivos por incompatibilidad del backend GPU con LiteRT para arquitecturas no-Gemma.

**Modelo recomendado por defecto:** `gemma3n-e2b` (mejor relación calidad/RAM del catálogo).

---

## Modelos que requieren token HuggingFace

Los modelos Gemma (de Google) requieren:
1. Aceptar la licencia en `huggingface.co/google/gemma` o en el repo específico del modelo.
2. Crear un token de acceso en `huggingface.co/settings/tokens`.
3. Guardarlo en la app (pantalla `AiModelManagerScreen` → ícono de llave).

El token se guarda en `FlutterSecureStorage` con la clave `ai_hf_token_v1` y se añade automáticamente como cabecera `Authorization: Bearer <token>` en cada descarga. Si la descarga devuelve HTTP 401 o 403, la pantalla muestra un modal con instrucciones paso a paso y botones para abrir el navegador en la página del modelo y en la página de tokens de HF.

---

## Almacenamiento de modelos

Tres ubicaciones disponibles, configurables desde la pantalla de gestión:

| Valor | Ruta | Permisos | Se borra al desinstalar |
|---|---|---|---|
| `internal` (default) | `getApplicationDocumentsDirectory()/ai_models/` | Ninguno | Sí |
| `externalApp` | `getExternalStorageDirectory()/ai_models/` | Ninguno | Sí |
| `custom` | Carpeta elegida por el usuario | `READ/WRITE_EXTERNAL_STORAGE` | No |

Se pueden tener varios modelos descargados al mismo tiempo. Cada archivo se nombra `<modelId>.<ext>` (p. ej. `gemma3n-e2b.litertlm`).

---

## Seguridad de descarga

El repositorio (`AiModelRepository`) aplica estas garantías en cada descarga:
- **HTTPS forzado**: URLs sin `https://` son rechazadas.
- **Verificación de tamaño**: aborta si el archivo excede el tamaño esperado por más de un 20 %.
- **SHA-256**: al finalizar la descarga se verifica el hash. Si no coincide, el archivo se borra y se lanza `AiModelIntegrityException`.
- **Reanudación**: si ya existe un archivo parcial, la descarga se reanuda con el header `Range: bytes=<offset>-` en lugar de empezar desde cero.

> Los hashes `sha256` del catálogo están completados con los valores oficiales de HuggingFace LFS (junio 2026). Si añades un modelo nuevo, completa el hash antes de publicar en producción; si lo dejas vacío (`''`), la descarga no se verifica (útil en desarrollo, no recomendado en producción).

---

## Integración en otra app Flutter — paso a paso

### 1. Copiar los archivos

Copia la carpeta `lib/modules/ai/` completa a tu proyecto. También necesitas copiar `lib/services/device_capability_service.dart` (verifica las ABIs del dispositivo).

### 2. Dependencias en `pubspec.yaml`

```yaml
dependencies:
  flutter_gemma: ^0.16.1
  flutter_secure_storage: ^9.2.2
  path_provider: ^2.1.5
  crypto: ^3.0.6
  file_picker: ^8.3.7
  permission_handler: ^11.3.1
```

### 3. Configuración Android

**`android/app/build.gradle.kts`:**
```kotlin
android {
  ndkVersion = "28.2.13676358"
  
  compileOptions {
    isCoreLibraryDesugaringEnabled = true
  }
}

dependencies {
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**`android/settings.gradle.kts`:**
```kotlin
plugins {
  id("com.android.application") version "8.9.1" apply false
}
```

**`android/app/src/main/AndroidManifest.xml`:**
```xml
<uses-permission android:name="android.permission.INTERNET" />
<!-- Solo si usas almacenamiento externo personalizado -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

### 4. Inicialización en `main()`

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:tu_app/services/device_capability_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar flutter_gemma SOLO en dispositivos ARM64/x86_64.
  // En ARM32 las librerías nativas no están y initialize() crashea.
  if (await DeviceCapabilityService.instance.supportsLocalAi()) {
    await FlutterGemma.initialize();
  }
  
  runApp(const MyApp());
}
```

### 5. Añadir la pantalla de gestión a tu app

```dart
// En tu router (MaterialApp.routes o GoRouter):
'/ai': (context) => const AiModelManagerScreen(),

// Navegar desde cualquier pantalla:
Navigator.pushNamed(context, '/ai');
```

### 6. Usar `AiService` desde cualquier parte de la app

```dart
import 'package:tu_app/modules/ai/ai_module.dart';

// Verificar soporte antes de mostrar botones de IA
final soportado = await AiService.instance.isDeviceSupported();

// Generar texto (requiere modelo activo y descargado)
if (await AiService.instance.isModelReady()) {
  final respuesta = await AiService.instance.generateText(
    prompt: 'Clasifica este texto: "$textoDelUsuario"',
    systemInstruction: 'Responde SOLO con una palabra: positivo, negativo o neutro.',
    maxOutputTokens: 10,
  );
}
```

---

## Agregar un modelo nuevo al catálogo

Añadir una entrada en `AiModelCatalog.entries` (`models/ai_model_catalog.dart`):

```dart
AiModelCatalogEntry(
  id: 'mi-modelo-id',           // único, sin espacios, solo [a-z0-9-.]
  displayName: 'Mi Modelo 1B',
  description: 'Descripción corta de 1-2 líneas para el usuario.',
  qualityRating: 3,             // 1-5★ relativo a los otros modelos del catálogo
  approxSizeBytes: 600000000,   // tamaño del archivo en bytes
  minRecommendedRamMb: 3072,    // RAM mínima recomendada en MB
  fileKind: AiModelFileKind.litertlm,         // o .task / .binary
  engineModelType: ModelType.general,          // o ModelType.gemmaIt
  downloadUrl: 'https://huggingface.co/repo/resolve/main/archivo.litertlm',
  sha256: 'abc123...',          // hash SHA-256 del archivo (obligatorio en producción)
  requiresToken: false,         // true si el repo de HF es gated
),
```

**Cómo obtener el SHA-256 correcto:**
```bash
# En Linux/Mac después de descargar el modelo:
sha256sum archivo.litertlm

# En Windows (PowerShell):
Get-FileHash archivo.litertlm -Algorithm SHA256
```

También puedes leerlo de los metadatos LFS del repositorio de HuggingFace:
`https://huggingface.co/<org>/<repo>/resolve/main/<archivo>?download=true` → cabecera `ETag` o página de metadatos LFS.

---

## Comportamiento con modelos no-Gemma (`ModelType.general`)

`flutter_gemma 0.16.1` solo tiene template interno correcto para `ModelType.gemmaIt`. Los modelos con `ModelType.general` (SmolLM, SmolLM2, Qwen3, Phi-4) generan basura con el template `auto`. **Solución**: configurar manualmente `AiChatTemplate.chatml` desde la pantalla `AiModelConfigScreen` o programáticamente:

```dart
await AiService.instance.saveModelConfig(
  AiModelConfig(
    modelId: 'smollm2-360m',
    template: AiChatTemplate.chatml,
    systemInstruction: 'Eres un asistente en español.',
  ),
);
```

---

## Limitaciones conocidas

| Limitación | Detalle |
|---|---|
| Solo Android ARM64/x86_64 | Las librerías nativas de flutter_gemma no incluyen ARM32. Dispositivos armeabi-v7a (algunos relojes) no pueden cargar IA local. Verificar con `DeviceCapabilityService.instance.supportsLocalAi()` |
| Sin multi-turno real | Cada llamada a `generateText()` crea un `InferenceChat` con contexto limpio para evitar desbordamiento en modelos con ventana pequeña. No se mantiene historia de conversación entre llamadas |
| Qwen3 experimental | Puede cerrar la app en algunos dispositivos por incompatibilidad GPU del backend LiteRT con arquitecturas no-Gemma |
| Sin streaming | `flutter_gemma 0.16.1` devuelve la respuesta completa, no token a token |
| Un modelo activo a la vez | No es posible cargar dos `InferenceModel` simultáneamente |
