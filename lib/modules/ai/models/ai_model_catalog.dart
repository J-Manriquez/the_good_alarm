import 'package:flutter_gemma/flutter_gemma.dart';

/// Tipo de archivo de modelo soportado por el motor de inferencia.
enum AiModelFileKind { litertlm, task, binary }

extension AiModelFileKindX on AiModelFileKind {
  ModelFileType get toEngineFileType {
    switch (this) {
      case AiModelFileKind.litertlm:
        return ModelFileType.litertlm;
      case AiModelFileKind.task:
        return ModelFileType.task;
      case AiModelFileKind.binary:
        return ModelFileType.binary;
    }
  }

  String get extension {
    switch (this) {
      case AiModelFileKind.litertlm:
        return 'litertlm';
      case AiModelFileKind.task:
        return 'task';
      case AiModelFileKind.binary:
        return 'bin';
    }
  }
}

/// Una entrada del catálogo de modelos compatibles con este módulo.
///
/// `qualityRating` es un criterio relativo entre los modelos de este
/// catálogo (1 = más simple/rápido, 5 = más capaz/pesado), no un benchmark
/// formal — sirve solo para que el usuario sepa a grandes rasgos qué esperar.
class AiModelCatalogEntry {
  final String id;
  final String displayName;
  final String description;
  final int qualityRating;
  final int approxSizeBytes;
  final int minRecommendedRamMb;
  final AiModelFileKind fileKind;
  final ModelType engineModelType;
  final String downloadUrl;
  final String sha256;
  final bool requiresToken;

  const AiModelCatalogEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.qualityRating,
    required this.approxSizeBytes,
    required this.minRecommendedRamMb,
    required this.fileKind,
    required this.engineModelType,
    required this.downloadUrl,
    required this.sha256,
    this.requiresToken = false,
  }) : assert(qualityRating >= 1 && qualityRating <= 5);

  String get fileName => '$id.${fileKind.extension}';
}

/// Catálogo de modelos compatibles con `flutter_gemma` (LiteRT-LM/MediaPipe),
/// todos ejecutables 100% local sin depender de hardware específico.
///
/// URLs, nombres de archivo, tamaños y hashes SHA-256 verificados contra los
/// metadatos LFS de los repositorios de Hugging Face en junio de 2026.
class AiModelCatalog {
  static const List<AiModelCatalogEntry> entries = <AiModelCatalogEntry>[
    // ── SmolLM 135M (q8, 167 MB) ─────────────────────────────────────────
    AiModelCatalogEntry(
      id: 'smollm-135m',
      displayName: 'SmolLM 135M',
      description:
          'El modelo más liviano del catálogo. Respuestas muy simples y '
          'rápidas; pensado para equipos con muy poca RAM disponible.',
      qualityRating: 1,
      approxSizeBytes: 166754726,
      minRecommendedRamMb: 1024,
      fileKind: AiModelFileKind.task,
      engineModelType: ModelType.general,
      downloadUrl: 'https://huggingface.co/litert-community/SmolLM-135M-Instruct'
          '/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
      sha256: '6987dce5ac4f71032b070cf13412a5de0e49c04d271a053fc7d9d59a0dc104e9',
    ),
    // ── Gemma 3 270M (q8, 304 MB) ────────────────────────────────────────
    // Requiere aceptar la licencia de Gemma en HuggingFace y un token HF.
    AiModelCatalogEntry(
      id: 'gemma3-270m',
      displayName: 'Gemma 3 270M',
      description:
          'Ultra liviano, viable hasta en gama baja. Calidad de respuesta '
          'limitada, útil para tareas cortas y muy puntuales. '
          'Requiere aceptar la licencia Gemma en huggingface.co y un token HF.',
      qualityRating: 2,
      approxSizeBytes: 304005120,
      minRecommendedRamMb: 1536,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/litert-community/gemma-3-270m-it'
          '/resolve/main/gemma3-270m-it-q8.litertlm',
      sha256: '757e9119fa5bd667a2774fb470ac4afcd3190a21c677f8e69a5d6bc908abdd63',
      requiresToken: true,
    ),
    // ── SmolLM2 360M (litertlm, 374 MB) ──────────────────────────────────
    AiModelCatalogEntry(
      id: 'smollm2-360m',
      displayName: 'SmolLM2 360M',
      description:
          'Sucesor de SmolLM con mejor coherencia y razonamiento. '
          'Sin token requerido. Buena opción liviana sin licencias.',
      qualityRating: 2,
      approxSizeBytes: 392265728,
      minRecommendedRamMb: 1536,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.general,
      downloadUrl: 'https://huggingface.co/litert-community/SmolLM2-360M-Instruct'
          '/resolve/main/SmolLM2_360M_instruct.litertlm',
      sha256: '8e2834da211b439751af968ed650febdde5a8cb8d88bc6c1a3059f049caa5c2e',
    ),
    // ── Qwen3 0.6B (int4 mix, 497 MB) ────────────────────────────────────
    // ADVERTENCIA: puede cerrar la app en algunos dispositivos Android (crash
    // nativo del motor LiteRT con backend GPU para arquitecturas no-Gemma).
    AiModelCatalogEntry(
      id: 'qwen3-0.6b',
      displayName: 'Qwen3 0.6B (experimental)',
      description:
          'Alternativa liviana de Alibaba. EXPERIMENTAL: puede cerrar la '
          'app en algunos dispositivos por incompatibilidad GPU con LiteRT.',
      qualityRating: 2,
      approxSizeBytes: 497664000,
      minRecommendedRamMb: 2048,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.general,
      downloadUrl: 'https://huggingface.co/litert-community/Qwen3-0.6B'
          '/resolve/main/qwen3_0_6b_mixed_int4.litertlm',
      sha256: 'b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9',
    ),
    // ── Gemma 3 1B IT (int4, 584 MB) ─────────────────────────────────────
    // Requiere token HF + aceptar licencia Gemma en huggingface.co.
    AiModelCatalogEntry(
      id: 'gemma3-1b-it',
      displayName: 'Gemma 3 1B IT',
      description:
          'Buen balance liviano/calidad para gama media. Recomendado si '
          'Gemma 3n E2B resulta demasiado pesado para el dispositivo. '
          'Requiere token HF y aceptar la licencia Gemma.',
      qualityRating: 3,
      approxSizeBytes: 584417280,
      minRecommendedRamMb: 3072,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT'
          '/resolve/main/gemma3-1b-it-int4.litertlm',
      sha256: '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
      requiresToken: true,
    ),
    // ── Gemma 3n E2B (int4, 3.4 GB) ──────────────────────────────────────
    // Requiere token HF + aceptar licencia Gemma en huggingface.co.
    AiModelCatalogEntry(
      id: 'gemma3n-e2b',
      displayName: 'Gemma 3n E2B',
      description:
          'Modelo recomendado por defecto. Multimodal (texto/imagen/audio) '
          'con la mejor relación calidad/RAM del catálogo. '
          'Requiere token HF y aceptar la licencia Gemma.',
      qualityRating: 4,
      approxSizeBytes: 3655827456,
      minRecommendedRamMb: 6144,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm'
          '/resolve/main/gemma-3n-E2B-it-int4.litertlm',
      sha256: '2ed7bc3a0026c93d5b8a4544b352d9d00cd66ff0bac3ef6a20ac3d2cba4010d6',
      requiresToken: true,
    ),
    // ── Gemma 4 E2B (int4, 2.4 GB) ───────────────────────────────────────
    // Requiere token HF + aceptar licencia Gemma en huggingface.co.
    AiModelCatalogEntry(
      id: 'gemma4-e2b',
      displayName: 'Gemma 4 E2B',
      description:
          'Sucesor de Gemma 3n con menor tamaño de descarga y mejor '
          'eficiencia. Última generación de Google para móviles. '
          'Requiere token HF y aceptar la licencia Gemma.',
      qualityRating: 4,
      approxSizeBytes: 2588147712,
      minRecommendedRamMb: 5120,
      fileKind: AiModelFileKind.litertlm,
      // flutter_gemma 0.16.1 no tiene ModelType.gemma4; gemmaIt es compatible.
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
          '/resolve/main/gemma-4-E2B-it.litertlm',
      sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
      requiresToken: true,
    ),
    // ── Phi-4 Mini (q8, 3.6 GB) ──────────────────────────────────────────
    AiModelCatalogEntry(
      id: 'phi4-mini',
      displayName: 'Phi-4 Mini',
      description:
          'Alternativa de Microsoft con buen desempeño en razonamiento '
          'corto. Requiere bastante RAM por ser cuantización q8.',
      qualityRating: 4,
      approxSizeBytes: 3910090752,
      minRecommendedRamMb: 8192,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.general,
      downloadUrl: 'https://huggingface.co/litert-community/Phi-4-mini-instruct'
          '/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      sha256: '7764d4deb53800578307be33039476b38a6c370fff71bedb3c0552563e23ab02',
    ),
    // ── Gemma 3n E4B (int4, 4.6 GB) ──────────────────────────────────────
    // Requiere token HF + aceptar licencia Gemma en huggingface.co.
    AiModelCatalogEntry(
      id: 'gemma3n-e4b',
      displayName: 'Gemma 3n E4B',
      description:
          'Más capaz que E2B pero requiere bastante más RAM. Recomendado '
          'solo en equipos de gama alta. '
          'Requiere token HF y aceptar la licencia Gemma.',
      qualityRating: 5,
      approxSizeBytes: 4919541760,
      minRecommendedRamMb: 8192,
      fileKind: AiModelFileKind.litertlm,
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm'
          '/resolve/main/gemma-3n-E4B-it-int4.litertlm',
      sha256: '2e67a6cd51dfe0f793431e6bd4ed8d029c88e10f52ca0469ad38445e3cd3c1f4',
      requiresToken: true,
    ),
    // ── Gemma 4 E4B (int4, 3.4 GB) ───────────────────────────────────────
    // Requiere token HF + aceptar licencia Gemma en huggingface.co.
    AiModelCatalogEntry(
      id: 'gemma4-e4b',
      displayName: 'Gemma 4 E4B',
      description:
          'El modelo más capaz del catálogo. Mejor calidad de respuesta, '
          'mayor tamaño de descarga y mayor consumo de RAM/batería. '
          'Requiere token HF y aceptar la licencia Gemma.',
      qualityRating: 5,
      approxSizeBytes: 3659530240,
      minRecommendedRamMb: 8192,
      fileKind: AiModelFileKind.litertlm,
      // flutter_gemma 0.16.1 no tiene ModelType.gemma4; gemmaIt es compatible.
      engineModelType: ModelType.gemmaIt,
      downloadUrl: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm'
          '/resolve/main/gemma-4-E4B-it.litertlm',
      sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
      requiresToken: true,
    ),
  ];

  static AiModelCatalogEntry? byId(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
