import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../../services/device_capability_service.dart';
import '../models/ai_model_catalog.dart';
import '../models/ai_model_config.dart';
import 'ai_model_repository.dart';

/// API pública y única que una app anfitriona necesita usar para
/// "pasarle información al modelo y que tome decisiones".
class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  // El InferenceModel se cachea entre llamadas (costoso de crear).
  // El InferenceChat se recrea en cada generateText() para evitar que el
  // context window se desborde en modelos con ventana pequeña (ej. SmolLM).
  InferenceModel? _model;
  String? _loadedModelId;

  static const String unsupportedMessage =
      'La IA local no está disponible en este dispositivo (requiere procesador ARM64).';

  Future<bool> isDeviceSupported() =>
      DeviceCapabilityService.instance.supportsLocalAi();

  Future<void> _assertSupported() async {
    if (!await DeviceCapabilityService.instance.supportsLocalAi()) {
      throw UnsupportedError(unsupportedMessage);
    }
  }

  List<AiModelCatalogEntry> availableModels() => AiModelCatalog.entries;

  // ── Ubicación de almacenamiento ───────────────────────────────────────

  Future<AiStorageLocation> storageLocation() =>
      AiModelRepository.loadStorageLocation();

  Future<String?> customStoragePath() => AiModelRepository.loadCustomPath();

  Future<void> setStorageLocation(
    AiStorageLocation location, {
    String? customPath,
  }) async {
    debugPrint('[AI][setStorageLocation] nueva ubicación: ${location.name}  customPath=$customPath');
    await AiModelRepository.saveStorageLocation(location);
    if (location == AiStorageLocation.custom && customPath != null) {
      await AiModelRepository.saveCustomPath(customPath);
    }
    _model = null;
    _loadedModelId = null;
    debugPrint('[AI][setStorageLocation] OK. Modelo en memoria limpiado.');
  }

  Future<AiStoragePermissionResult> requestStoragePermission() =>
      AiModelRepository.requestStoragePermission();

  Future<String?> pickCustomDirectory() =>
      AiModelRepository.pickCustomDirectory();

  Future<String> modelsDirectoryPath() async {
    final dir = await AiModelRepository.modelsDirectory();
    debugPrint('[AI][modelsDirectoryPath] directorio de modelos: ${dir.path}');
    return dir.path;
  }

  // ── Modelos ───────────────────────────────────────────────────────────

  Future<List<String>> downloadedModelIds() async {
    debugPrint('[AI][downloadedModelIds] consultando modelos descargados...');
    final ids = await AiModelRepository.downloadedModelIds();
    debugPrint('[AI][downloadedModelIds] encontrados: $ids');
    return ids;
  }

  Future<bool> isModelDownloaded(String modelId) async {
    debugPrint('[AI][isModelDownloaded] consultando modelId=$modelId');
    final entry = AiModelCatalog.byId(modelId);
    if (entry == null) {
      debugPrint('[AI][isModelDownloaded] WARN: modelId=$modelId no existe en el catálogo');
      return false;
    }
    final result = await AiModelRepository.isModelDownloaded(entry);
    debugPrint('[AI][isModelDownloaded] modelId=$modelId descargado=$result');
    return result;
  }

  Future<String> downloadModel(
    String modelId, {
    void Function(int progressPercent, int receivedBytes, int? totalBytes)?
    onProgress,
  }) async {
    await _assertSupported();
    debugPrint('[AI][downloadModel] START modelId=$modelId');
    final entry = AiModelCatalog.byId(modelId);
    if (entry == null) {
      debugPrint('[AI][downloadModel] ERROR: modelId=$modelId no existe en el catálogo');
      throw ArgumentError('Modelo desconocido: $modelId');
    }
    debugPrint('[AI][downloadModel] descargando "${entry.displayName}"  url=${entry.downloadUrl}  requiresToken=${entry.requiresToken}');
    try {
      final path = await AiModelRepository.downloadModel(
        entry,
        onProgress: (pct, received, total) {
          if (pct % 10 == 0) {
            debugPrint('[AI][downloadModel] progreso $pct%  ${received}B / ${total ?? "?"}B');
          }
          onProgress?.call(pct, received, total);
        },
      );
      debugPrint('[AI][downloadModel] OK path=$path');
      return path;
    } catch (e, st) {
      debugPrint('[AI][downloadModel] ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteModel(String modelId) async {
    debugPrint('[AI][deleteModel] START modelId=$modelId');
    final entry = AiModelCatalog.byId(modelId);
    if (entry == null) {
      debugPrint('[AI][deleteModel] WARN: modelId=$modelId no existe en el catálogo (noop)');
      return;
    }
    await AiModelRepository.deleteModel(entry);
    if (_loadedModelId == modelId) {
      _model = null;
      _loadedModelId = null;
      debugPrint('[AI][deleteModel] modelo activo eliminado — InferenceModel limpiado');
    }
    debugPrint('[AI][deleteModel] OK modelId=$modelId');
  }

  Future<String?> activeModelId() async {
    final id = await AiModelRepository.activeModelId();
    debugPrint('[AI][activeModelId] activeModelId=$id');
    return id;
  }

  Future<void> setActiveModel(String modelId) async {
    debugPrint('[AI][setActiveModel] START modelId=$modelId');
    if (AiModelCatalog.byId(modelId) == null) {
      debugPrint('[AI][setActiveModel] ERROR: modelId=$modelId no existe en el catálogo');
      throw ArgumentError('Modelo desconocido: $modelId');
    }
    await AiModelRepository.setActiveModelId(modelId);
    if (_loadedModelId != modelId) {
      _model = null;
      _loadedModelId = null;
      debugPrint('[AI][setActiveModel] InferenceModel limpiado — se recargará al próximo uso');
    }
    debugPrint('[AI][setActiveModel] OK modelId=$modelId');
  }

  // ── Configuración por modelo ─────────────────────────────────────────

  Future<AiModelConfig> modelConfig(String modelId) =>
      AiModelRepository.loadModelConfig(modelId);

  Future<void> saveModelConfig(AiModelConfig config) async {
    debugPrint('[AI][saveModelConfig] modelId=${config.modelId}  template=${config.template.name}');
    await AiModelRepository.saveModelConfig(config);
    // Si es el modelo activo en memoria, la próxima llamada lo recargará.
    if (_loadedModelId == config.modelId) {
      _model = null;
      _loadedModelId = null;
      debugPrint('[AI][saveModelConfig] modelo recargado para aplicar nueva config');
    }
  }

  Future<bool> isModelReady() async {
    debugPrint('[AI][isModelReady] consultando estado...');
    final id = await activeModelId();
    if (id == null) {
      debugPrint('[AI][isModelReady] false — no hay modelo activo');
      return false;
    }
    final ready = await isModelDownloaded(id);
    debugPrint('[AI][isModelReady] modelId=$id ready=$ready');
    return ready;
  }

  /// Carga el [InferenceModel] en memoria si no está ya cacheado.
  /// Solo instala / carga el modelo una vez y lo reutiliza entre llamadas.
  /// El InferenceChat se crea fresco en cada [generateText] para evitar
  /// desbordamiento del context window.
  Future<InferenceModel> _ensureModel({int maxTokens = 1024}) async {
    await _assertSupported();
    debugPrint('[AI][_ensureModel] START  maxTokens=$maxTokens');

    final modelId = await AiModelRepository.activeModelId();
    if (modelId == null) {
      debugPrint('[AI][_ensureModel] ERROR: no hay modelo activo');
      throw StateError('No hay un modelo activo. Llama setActiveModel() primero.');
    }
    debugPrint('[AI][_ensureModel] modelId=$modelId  loadedModelId=$_loadedModelId');

    final entry = AiModelCatalog.byId(modelId);
    if (entry == null) {
      debugPrint('[AI][_ensureModel] ERROR: modelId=$modelId no está en el catálogo');
      throw StateError('El modelo activo "$modelId" no existe en el catálogo.');
    }

    final downloaded = await AiModelRepository.isModelDownloaded(entry);
    if (!downloaded) {
      debugPrint('[AI][_ensureModel] ERROR: modelo "${entry.displayName}" no descargado');
      throw StateError(
        'El modelo "${entry.displayName}" no está descargado. '
        'Llama downloadModel() primero.',
      );
    }

    if (_model != null && _loadedModelId == modelId) {
      debugPrint('[AI][_ensureModel] reutilizando InferenceModel en caché para modelId=$modelId');
      return _model!;
    }

    final path = await AiModelRepository.pathForModel(entry);
    debugPrint('[AI][_ensureModel] ruta del modelo: $path');
    debugPrint('[AI][_ensureModel] engineModelType=${entry.engineModelType}  fileKind=${entry.fileKind}  fileType=${entry.fileKind.toEngineFileType}');

    try {
      debugPrint('[AI][_ensureModel] llamando FlutterGemma.installModel().fromFile().install() ...');
      await FlutterGemma.installModel(
        modelType: entry.engineModelType,
        fileType: entry.fileKind.toEngineFileType,
      ).fromFile(path).install();
      debugPrint('[AI][_ensureModel] installModel OK');
    } catch (e, st) {
      debugPrint('[AI][_ensureModel] ERROR en installModel: $e\n$st');
      rethrow;
    }

    debugPrint('[AI][_ensureModel] llamando FlutterGemma.getActiveModel(maxTokens=$maxTokens) ...');
    try {
      _model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
      _loadedModelId = modelId;
      debugPrint('[AI][_ensureModel] getActiveModel OK  model=${_model.runtimeType}');
    } catch (e, st) {
      debugPrint('[AI][_ensureModel] ERROR en getActiveModel: $e\n$st');
      rethrow;
    }

    return _model!;
  }

  /// Genera texto a partir de [prompt] usando el modelo activo.
  ///
  /// Cada llamada crea un nuevo [InferenceChat] con contexto limpio para
  /// evitar que modelos de ventana pequeña (SmolLM 135M, etc.) produzcan
  /// respuestas vacías por desbordamiento de contexto.
  /// Genera texto usando el modelo activo.
  ///
  /// Lee la [AiModelConfig] del modelo activo para aplicar el template,
  /// temperatura, topK y maxOutputTokens configurados por el usuario.
  /// Los parámetros [systemInstruction], [temperature] y [maxOutputTokens]
  /// pasados aquí actúan como fallback si la config no tiene valores propios.
  Future<String> generateText({
    required String prompt,
    String? systemInstruction,
    double temperature = 0.7,
    int maxOutputTokens = 256,
  }) async {
    debugPrint('[AI][generateText] START  prompt="${prompt.length > 80 ? prompt.substring(0, 80) : prompt}..."  temp=$temperature  maxTokens=$maxOutputTokens');

    try {
      // Carga config del modelo activo para aplicar template y parámetros.
      final activeId = await AiModelRepository.activeModelId();
      final cfg = activeId != null
          ? await AiModelRepository.loadModelConfig(activeId)
          : null;

      final double effectiveTemp = cfg != null && cfg.systemInstruction.isNotEmpty
          ? cfg.temperature
          : temperature;
      final int effectiveMaxTokens = cfg?.maxOutputTokens ?? maxOutputTokens;
      final int effectiveTopK = cfg?.topK ?? 40;
      final String effectiveSystem =
          (cfg != null && cfg.systemInstruction.isNotEmpty)
              ? cfg.systemInstruction
              : (systemInstruction ?? '');

      debugPrint('[AI][generateText] config  template=${cfg?.template.name ?? "auto"}  temp=$effectiveTemp  maxTokens=$effectiveMaxTokens  topK=$effectiveTopK  system="${effectiveSystem.length > 60 ? effectiveSystem.substring(0, 60) : effectiveSystem}"');

      final int tokenBudget =
          effectiveMaxTokens > 1024 ? effectiveMaxTokens : 1024;
      final model = await _ensureModel(maxTokens: tokenBudget);
      final entry = AiModelCatalog.byId(_loadedModelId!)!;

      // Aplica template: si no es auto, formatea el prompt manualmente y usa
      // systemInstruction vacío (el template ya lo embebe).
      final AiChatTemplate template = cfg?.template ?? AiChatTemplate.auto;
      final String? formattedPrompt = template.format(
        userMessage: prompt,
        systemInstruction: effectiveSystem,
        customTemplate: cfg?.customTemplate,
      );
      final bool useManualTemplate = formattedPrompt != null;

      debugPrint('[AI][generateText] useManualTemplate=$useManualTemplate  formattedLen=${formattedPrompt?.length}');

      debugPrint('[AI][generateText] creando InferenceChat fresco...');
      final InferenceChat chat;
      try {
        chat = await model.createChat(
          modelType: entry.engineModelType,
          temperature: effectiveTemp,
          topK: effectiveTopK,
          randomSeed: 1,
          // Si el template es manual ya embebe el system; si es auto lo pasa aquí.
          systemInstruction: useManualTemplate ? '' : effectiveSystem,
        );
        debugPrint('[AI][generateText] createChat OK');
      } catch (e, st) {
        debugPrint('[AI][generateText] ERROR en createChat: $e\n$st');
        rethrow;
      }

      final String messageToSend = formattedPrompt ?? prompt;
      debugPrint('[AI][generateText] enviando mensaje (len=${messageToSend.length})...');
      await chat.addQueryChunk(
        Message.text(text: messageToSend, isUser: true),
      );
      debugPrint('[AI][generateText] addQueryChunk OK — esperando respuesta...');

      final response = await chat.generateChatResponse();
      debugPrint('[AI][generateText] respuesta recibida  type=${response.runtimeType}');

      final raw = response is TextResponse ? response.token : response.toString();
      final answer = raw.trim();
      debugPrint('[AI][generateText] OK  longitud=${answer.length}  respuesta="${answer.length > 200 ? answer.substring(0, 200) : answer}"');
      return answer;
    } catch (e, st) {
      debugPrint('[AI][generateText] ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Libera el modelo cargado en memoria (no borra el archivo descargado).
  void unload() {
    debugPrint('[AI][unload] liberando InferenceModel. loadedModelId=$_loadedModelId');
    _model = null;
    _loadedModelId = null;
    debugPrint('[AI][unload] OK');
  }
}
