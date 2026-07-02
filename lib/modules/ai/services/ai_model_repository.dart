import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ai_model_catalog.dart';
import '../models/ai_model_config.dart';

/// Excepción lanzada cuando una descarga falla la verificación de integridad.
class AiModelIntegrityException implements Exception {
  final String message;
  const AiModelIntegrityException(this.message);

  @override
  String toString() => 'AiModelIntegrityException: $message';
}

/// Dónde se guardan los modelos descargados.
///
/// - [internal]: almacenamiento privado de la app (`getApplicationDocumentsDirectory()`).
///   Sin permisos, no visible en el gestor de archivos, se elimina al desinstalar.
/// - [externalApp]: almacenamiento externo específico de la app
///   (`getExternalStorageDirectory()`). Sin permisos, visible con un gestor
///   de archivos, se elimina al desinstalar. Recomendado para liberar espacio
///   interno o modelos de gran tamaño.
/// - [custom]: carpeta elegida por el usuario. Requiere permiso de
///   almacenamiento explícito. Persiste aunque se desinstale la app.
enum AiStorageLocation { internal, externalApp, custom }

extension AiStorageLocationX on AiStorageLocation {
  String get label {
    switch (this) {
      case AiStorageLocation.internal:
        return 'Almacenamiento interno';
      case AiStorageLocation.externalApp:
        return 'Almacenamiento externo de la app';
      case AiStorageLocation.custom:
        return 'Carpeta personalizada';
    }
  }

  String get description {
    switch (this) {
      case AiStorageLocation.internal:
        return 'Privado de la app. Sin permisos necesarios. '
            'Se elimina al desinstalar la app.';
      case AiStorageLocation.externalApp:
        return 'Visible en el gestor de archivos. Sin permisos necesarios. '
            'Se elimina al desinstalar la app. Recomendado para modelos grandes.';
      case AiStorageLocation.custom:
        return 'Tú eliges la carpeta. Requiere permiso de almacenamiento. '
            'Los archivos persisten aunque se desinstale la app.';
    }
  }
}

/// Resultado de la solicitud de permisos para la ubicación [AiStorageLocation.custom].
enum AiStoragePermissionResult {
  granted,
  deniedCanRetry,
  permanentlyDenied,
}

class AiModelRepository {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _keyActiveModelId = 'ai_active_model_id_v1';
  static const String _keyStorageLocation = 'ai_storage_location_v1';
  static const String _keyCustomPath = 'ai_custom_path_v1';
  // Token global de HuggingFace — aplica a todos los modelos que lo requieran.
  static const String _keyHfToken = 'ai_hf_token_v1';
  static const String _keyModelConfigPrefix = 'ai_model_cfg_v1_';

  static const double _maxSizeOverheadRatio = 1.5;

  // ── Ubicación de almacenamiento ─────────────────────────────────────────

  static Future<AiStorageLocation> loadStorageLocation() async {
    debugPrint('[AI][repo][loadStorageLocation] leyendo preferencia...');
    final raw = await _secureStorage.read(key: _keyStorageLocation);
    final location = AiStorageLocation.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AiStorageLocation.internal,
    );
    debugPrint('[AI][repo][loadStorageLocation] raw="$raw"  resultado=${location.name}');
    return location;
  }

  static Future<void> saveStorageLocation(AiStorageLocation location) async {
    debugPrint('[AI][repo][saveStorageLocation] guardando ${location.name}');
    await _secureStorage.write(key: _keyStorageLocation, value: location.name);
    debugPrint('[AI][repo][saveStorageLocation] OK');
  }

  static Future<String?> loadCustomPath() async {
    final path = await _secureStorage.read(key: _keyCustomPath);
    debugPrint('[AI][repo][loadCustomPath] path=$path');
    return path;
  }

  static Future<void> saveCustomPath(String? path) async {
    debugPrint('[AI][repo][saveCustomPath] path=$path');
    if (path == null || path.trim().isEmpty) {
      await _secureStorage.delete(key: _keyCustomPath);
      debugPrint('[AI][repo][saveCustomPath] path vacío — borrado');
      return;
    }
    await _secureStorage.write(key: _keyCustomPath, value: path.trim());
    debugPrint('[AI][repo][saveCustomPath] OK');
  }

  /// Solicita el permiso necesario para usar [AiStorageLocation.custom].
  ///
  /// Android 10+ (API 29+): file_picker usa SAF que NO requiere permiso de
  /// almacenamiento. Se concede automáticamente y el picker abre directamente.
  /// Android 9 y anteriores: se solicita [Permission.storage] (READ + WRITE).
  static Future<AiStoragePermissionResult> requestStoragePermission() async {
    debugPrint('[AI][repo][requestStoragePermission] START  isAndroid=${Platform.isAndroid}');
    if (!Platform.isAndroid) {
      debugPrint('[AI][repo][requestStoragePermission] no-Android → granted automáticamente');
      return AiStoragePermissionResult.granted;
    }

    final sdkInt = await _androidSdkVersion();
    debugPrint('[AI][repo][requestStoragePermission] Android SDK=$sdkInt');

    // Android 10+ (API 29+): SAF no requiere permiso explícito para elegir carpeta.
    if (sdkInt >= 29) {
      debugPrint('[AI][repo][requestStoragePermission] SDK>=29 → SAF sin permiso → granted');
      return AiStoragePermissionResult.granted;
    }

    // Android 9 y anteriores: permiso clásico de almacenamiento.
    debugPrint('[AI][repo][requestStoragePermission] SDK<29 → solicitando Permission.storage');
    var status = await Permission.storage.status;
    debugPrint('[AI][repo][requestStoragePermission] status inicial: $status');
    if (status.isGranted) return AiStoragePermissionResult.granted;
    if (status.isPermanentlyDenied) return AiStoragePermissionResult.permanentlyDenied;

    status = await Permission.storage.request();
    debugPrint('[AI][repo][requestStoragePermission] status tras solicitud: $status');
    if (status.isGranted) return AiStoragePermissionResult.granted;
    if (status.isPermanentlyDenied) return AiStoragePermissionResult.permanentlyDenied;
    return AiStoragePermissionResult.deniedCanRetry;
  }

  /// Abre el selector de carpeta del sistema. Debe llamarse solo después de
  /// que [requestStoragePermission] retorne [AiStoragePermissionResult.granted].
  static Future<String?> pickCustomDirectory() async {
    debugPrint('[AI][repo][pickCustomDirectory] abriendo selector de carpeta...');
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Elegir carpeta para guardar modelos IA',
    );
    debugPrint('[AI][repo][pickCustomDirectory] resultado: $path');
    return path;
  }

  /// Directorio donde se guardan los modelos según la ubicación configurada.
  static Future<Directory> modelsDirectory() async {
    debugPrint('[AI][repo][modelsDirectory] resolviendo directorio...');
    final location = await loadStorageLocation();
    debugPrint('[AI][repo][modelsDirectory] location=${location.name}');
    final String base;

    switch (location) {
      case AiStorageLocation.internal:
        final docs = await getApplicationDocumentsDirectory();
        base = docs.path;
        debugPrint('[AI][repo][modelsDirectory] internal basePath=$base');
        break;
      case AiStorageLocation.externalApp:
        final ext = await getExternalStorageDirectory();
        if (ext == null) {
          debugPrint('[AI][repo][modelsDirectory] WARN: getExternalStorageDirectory() retornó null — usando internal como fallback');
        }
        base = ext?.path ?? (await getApplicationDocumentsDirectory()).path;
        debugPrint('[AI][repo][modelsDirectory] externalApp basePath=$base');
        break;
      case AiStorageLocation.custom:
        final custom = await loadCustomPath();
        debugPrint('[AI][repo][modelsDirectory] custom path guardado: $custom');
        if (custom == null || custom.isEmpty) {
          debugPrint('[AI][repo][modelsDirectory] WARN: customPath vacío — usando internal como fallback');
        }
        base = (custom != null && custom.isNotEmpty)
            ? custom
            : (await getApplicationDocumentsDirectory()).path;
        debugPrint('[AI][repo][modelsDirectory] custom basePath=$base');
        break;
    }

    final dir = Directory('$base${Platform.pathSeparator}ai_models');
    debugPrint('[AI][repo][modelsDirectory] directorio final: ${dir.path}');
    final exists = await dir.exists();
    debugPrint('[AI][repo][modelsDirectory] existe: $exists');
    if (!exists) {
      debugPrint('[AI][repo][modelsDirectory] creando directorio...');
      await dir.create(recursive: true);
      debugPrint('[AI][repo][modelsDirectory] directorio creado');
    }
    return dir;
  }

  // ── Rutas y estado de modelos ───────────────────────────────────────────

  static Future<String> pathForModel(AiModelCatalogEntry entry) async {
    final dir = await modelsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}${entry.fileName}';
    debugPrint('[AI][repo][pathForModel] id=${entry.id}  path=$path');
    return path;
  }

  static Future<bool> isModelDownloaded(AiModelCatalogEntry entry) async {
    final path = await pathForModel(entry);
    final exists = await File(path).exists();
    debugPrint('[AI][repo][isModelDownloaded] id=${entry.id}  exists=$exists  path=$path');
    if (exists) {
      final size = await File(path).length();
      debugPrint('[AI][repo][isModelDownloaded] tamaño en disco: $size bytes  esperado~${entry.approxSizeBytes}');
    }
    return exists;
  }

  static Future<List<String>> downloadedModelIds() async {
    debugPrint('[AI][repo][downloadedModelIds] escaneando modelos descargados...');
    final result = <String>[];
    for (final entry in AiModelCatalog.entries) {
      if (await isModelDownloaded(entry)) result.add(entry.id);
    }
    debugPrint('[AI][repo][downloadedModelIds] resultado: $result');
    return result;
  }

  static Future<void> deleteModel(AiModelCatalogEntry entry) async {
    debugPrint('[AI][repo][deleteModel] START id=${entry.id}');
    final path = await pathForModel(entry);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      debugPrint('[AI][repo][deleteModel] archivo eliminado: $path');
    } else {
      debugPrint('[AI][repo][deleteModel] WARN: archivo no existía: $path');
    }
    final partial = File('$path.part');
    if (await partial.exists()) {
      await partial.delete();
      debugPrint('[AI][repo][deleteModel] parcial eliminado: $path.part');
    }
    debugPrint('[AI][repo][deleteModel] OK id=${entry.id}');
  }

  // ── Modelo activo ───────────────────────────────────────────────────────

  static Future<String?> activeModelId() async {
    final id = await _secureStorage.read(key: _keyActiveModelId);
    debugPrint('[AI][repo][activeModelId] id=$id');
    return id;
  }

  static Future<void> setActiveModelId(String? modelId) async {
    debugPrint('[AI][repo][setActiveModelId] modelId=$modelId');
    if (modelId == null) {
      await _secureStorage.delete(key: _keyActiveModelId);
      debugPrint('[AI][repo][setActiveModelId] borrado (null)');
      return;
    }
    await _secureStorage.write(key: _keyActiveModelId, value: modelId);
    debugPrint('[AI][repo][setActiveModelId] OK');
  }

  // ── Token global de HuggingFace ────────────────────────────────────────
  // Un único token sirve para todos los modelos que requieran autenticación
  // (siempre que el usuario haya aceptado la licencia de cada uno en HF).

  static Future<String?> hfToken() async {
    final token = await _secureStorage.read(key: _keyHfToken);
    debugPrint('[AI][repo][hfToken] tieneToken=${token != null && token.isNotEmpty}');
    return token;
  }

  static Future<void> saveHfToken(String? token) async {
    final clean = token?.trim();
    debugPrint('[AI][repo][saveHfToken] token=${clean != null && clean.isNotEmpty ? "****" : "null/vacío"}');
    if (clean == null || clean.isEmpty) {
      await _secureStorage.delete(key: _keyHfToken);
      debugPrint('[AI][repo][saveHfToken] token eliminado');
      return;
    }
    await _secureStorage.write(key: _keyHfToken, value: clean);
    debugPrint('[AI][repo][saveHfToken] OK');
  }

  // Alias para retrocompatibilidad con el código que pasa modelId — se ignora.
  static Future<String?> tokenForModel(String modelId) => hfToken();
  static Future<void> saveTokenForModel(String modelId, String? token) =>
      saveHfToken(token);

  // ── Configuración por modelo ────────────────────────────────────────────

  static Future<AiModelConfig> loadModelConfig(String modelId) async {
    debugPrint('[AI][repo][loadModelConfig] modelId=$modelId');
    final raw = await _secureStorage.read(
      key: '$_keyModelConfigPrefix$modelId',
    );
    if (raw == null || raw.isEmpty) {
      debugPrint('[AI][repo][loadModelConfig] sin config guardada — usando defaults');
      return AiModelConfig(modelId: modelId);
    }
    final cfg = AiModelConfig.fromJsonString(modelId, raw);
    debugPrint('[AI][repo][loadModelConfig] OK template=${cfg.template.name}  temp=${cfg.temperature}  maxTokens=${cfg.maxOutputTokens}');
    return cfg;
  }

  static Future<void> saveModelConfig(AiModelConfig config) async {
    debugPrint('[AI][repo][saveModelConfig] modelId=${config.modelId}  template=${config.template.name}  temp=${config.temperature}  maxTokens=${config.maxOutputTokens}');
    await _secureStorage.write(
      key: '$_keyModelConfigPrefix${config.modelId}',
      value: config.toJsonString(),
    );
    debugPrint('[AI][repo][saveModelConfig] OK');
  }

  static Future<void> deleteModelConfig(String modelId) async {
    debugPrint('[AI][repo][deleteModelConfig] modelId=$modelId');
    await _secureStorage.delete(key: '$_keyModelConfigPrefix$modelId');
  }

  // ── Descarga ────────────────────────────────────────────────────────────

  /// Descarga [entry] verificando HTTPS, tamaño máximo y SHA-256.
  /// Reanuda descargas parciales si el servidor soporta `Range`.
  static Future<String> downloadModel(
    AiModelCatalogEntry entry, {
    void Function(int progressPercent, int receivedBytes, int? totalBytes)?
    onProgress,
  }) async {
    debugPrint('[AI][repo][downloadModel] START id=${entry.id}  url=${entry.downloadUrl}');
    final uri = Uri.parse(entry.downloadUrl);
    if (uri.scheme != 'https') {
      debugPrint('[AI][repo][downloadModel] ERROR: URL no HTTPS: ${entry.downloadUrl}');
      throw const AiModelIntegrityException(
        'Solo se permiten URLs HTTPS para descargar modelos.',
      );
    }

    final finalPath = await pathForModel(entry);
    final partialFile = File('$finalPath.part');
    final maxAllowedBytes = (entry.approxSizeBytes * _maxSizeOverheadRatio).round();
    debugPrint('[AI][repo][downloadModel] finalPath=$finalPath  maxAllowedBytes=$maxAllowedBytes');

    final client = HttpClient();
    try {
      debugPrint('[AI][repo][downloadModel] abriendo conexión HTTP...');
      final request = await client.getUrl(uri);
      final token = entry.requiresToken ? await tokenForModel(entry.id) : null;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        debugPrint('[AI][repo][downloadModel] token de autorización agregado');
      }

      var resumeOffset = 0;
      if (await partialFile.exists()) {
        resumeOffset = await partialFile.length();
        debugPrint('[AI][repo][downloadModel] archivo parcial encontrado  offset=$resumeOffset bytes');
        if (resumeOffset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeOffset-');
          debugPrint('[AI][repo][downloadModel] Range header: bytes=$resumeOffset-');
        }
      } else {
        debugPrint('[AI][repo][downloadModel] sin archivo parcial — descarga desde cero');
      }

      debugPrint('[AI][repo][downloadModel] enviando request...');
      final response = await request.close();
      debugPrint('[AI][repo][downloadModel] respuesta HTTP: statusCode=${response.statusCode}  contentLength=${response.contentLength}');

      final isPartial = response.statusCode == 206;
      debugPrint('[AI][repo][downloadModel] isPartial=$isPartial');
      if (!isPartial && resumeOffset > 0) {
        debugPrint('[AI][repo][downloadModel] servidor no acepta Range — reiniciando desde cero');
        await partialFile.delete();
        resumeOffset = 0;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[AI][repo][downloadModel] ERROR HTTP ${response.statusCode}');
        throw HttpException(
          'La descarga falló con código ${response.statusCode}',
          uri: uri,
        );
      }

      final contentLength =
          response.contentLength > 0 ? response.contentLength : null;
      final totalBytes = contentLength == null
          ? null
          : (isPartial ? contentLength + resumeOffset : contentLength);
      debugPrint('[AI][repo][downloadModel] totalBytes estimado=$totalBytes  (contentLength=$contentLength  resumeOffset=$resumeOffset)');

      if (totalBytes != null && totalBytes > maxAllowedBytes) {
        debugPrint('[AI][repo][downloadModel] ERROR: archivo remoto demasiado grande ($totalBytes > $maxAllowedBytes)');
        throw AiModelIntegrityException(
          'El archivo remoto ($totalBytes bytes) excede el tamaño máximo '
          'esperado para "${entry.displayName}" ($maxAllowedBytes bytes).',
        );
      }

      final sink = partialFile.openWrite(
        mode: isPartial ? FileMode.append : FileMode.writeOnly,
      );
      debugPrint('[AI][repo][downloadModel] escribiendo en ${partialFile.path}  modo=${isPartial ? "append" : "write"}');
      var receivedBytes = resumeOffset;

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes != null && receivedBytes > maxAllowedBytes) {
            debugPrint('[AI][repo][downloadModel] ERROR: tamaño máximo superado durante descarga');
            throw AiModelIntegrityException(
              'La descarga de "${entry.displayName}" superó el tamaño máximo esperado.',
            );
          }
          if (totalBytes != null) {
            final percent = (receivedBytes * 100) ~/ totalBytes;
            onProgress?.call(
              receivedBytes < totalBytes ? percent.clamp(0, 99) : 100,
              receivedBytes,
              totalBytes,
            );
          } else {
            onProgress?.call(0, receivedBytes, null);
          }
        }
        await sink.flush();
        debugPrint('[AI][repo][downloadModel] stream completado  receivedBytes=$receivedBytes');
      } finally {
        await sink.close();
        debugPrint('[AI][repo][downloadModel] sink cerrado');
      }

      debugPrint('[AI][repo][downloadModel] verificando integridad SHA-256...');
      await _verifyIntegrity(entry, partialFile);
      debugPrint('[AI][repo][downloadModel] integridad OK');

      if (await File(finalPath).exists()) {
        debugPrint('[AI][repo][downloadModel] borrando archivo final previo');
        await File(finalPath).delete();
      }
      await partialFile.rename(finalPath);
      debugPrint('[AI][repo][downloadModel] archivo renombrado a $finalPath');

      onProgress?.call(100, receivedBytes, totalBytes ?? receivedBytes);
      debugPrint('[AI][repo][downloadModel] COMPLETE  path=$finalPath');
      return finalPath;
    } catch (e, st) {
      debugPrint('[AI][repo][downloadModel] ERROR: $e\n$st');
      rethrow;
    } finally {
      client.close(force: true);
      debugPrint('[AI][repo][downloadModel] cliente HTTP cerrado');
    }
  }

  static Future<void> _verifyIntegrity(
    AiModelCatalogEntry entry,
    File downloadedFile,
  ) async {
    debugPrint('[AI][repo][_verifyIntegrity] START id=${entry.id}  expectedSha256=${entry.sha256.isEmpty ? "(vacío-skip)" : entry.sha256.substring(0, 16)}...');
    if (entry.sha256.isEmpty) {
      debugPrint('[AI][repo][_verifyIntegrity] sha256 vacío — verificación omitida');
      return;
    }
    debugPrint('[AI][repo][_verifyIntegrity] calculando SHA-256 del archivo...');
    final digest = await sha256.bind(downloadedFile.openRead()).first;
    final actual = digest.toString();
    debugPrint('[AI][repo][_verifyIntegrity] sha256 calculado: ${actual.substring(0, 16)}...');
    if (actual.toLowerCase() != entry.sha256.toLowerCase()) {
      debugPrint('[AI][repo][_verifyIntegrity] ERROR: hash no coincide\n  esperado: ${entry.sha256}\n  obtenido: $actual');
      await downloadedFile.delete();
      throw AiModelIntegrityException(
        'El hash SHA-256 de "${entry.displayName}" no coincide '
        '(esperado ${entry.sha256}, obtenido $actual). Archivo descartado.',
      );
    }
    debugPrint('[AI][repo][_verifyIntegrity] OK — hash coincide');
  }

  // ── Utilidades ──────────────────────────────────────────────────────────

  static Future<int> _androidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      final sdk = int.tryParse(result.stdout.toString().trim()) ?? 0;
      debugPrint('[AI][repo][_androidSdkVersion] SDK=$sdk');
      return sdk;
    } catch (e) {
      debugPrint('[AI][repo][_androidSdkVersion] ERROR leyendo SDK version: $e — retornando 0');
      return 0;
    }
  }
}
