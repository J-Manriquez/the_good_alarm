import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../models/piper_voice_catalog.dart';

/// Servicio singleton para voces Piper TTS descargables.
/// Gestiona descarga, almacenamiento y síntesis de audio.
/// Los paquetes descargados (tar.bz2 de sherpa-onnx int8) incluyen:
///   - modelo .onnx cuantizado
///   - tokens.txt  (mapa fonema→ID, obligatorio para espeak-ng)
///   - espeak-ng-data/ (datos de fonematización, obligatorio en Android)
class PiperTtsService {
  PiperTtsService._();
  static final PiperTtsService instance = PiperTtsService._();

  bool _initialized = false;

  /// Inicializa los bindings nativos de sherpa-onnx.
  /// Es idempotente: solo carga la librería la primera vez.
  void _ensureInitialized() {
    if (!_initialized) {
      initBindings();
      _initialized = true;
      print('[PiperTtsService] sherpa-onnx initBindings() completado');
    }
  }

  /// Directorio raíz donde se almacenan todos los modelos.
  Future<String> _voicesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/piper_voices');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Subdirectorio dedicado para una voz específica.
  Future<String> _voiceSubDir(String voiceId) async {
    final voicesDir = await _voicesDir();
    return '$voicesDir/$voiceId';
  }

  /// Busca el archivo .onnx dentro del subdirectorio de la voz.
  Future<File?> _findModelFile(String voiceId) async {
    final subDir = Directory(await _voiceSubDir(voiceId));
    if (!subDir.existsSync()) return null;
    try {
      final onnxFiles = subDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.onnx'))
          .toList();
      return onnxFiles.isNotEmpty ? onnxFiles.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Devuelve true si la voz está completamente descargada y lista para usar.
  Future<bool> isDownloaded(String voiceId) async {
    // Limpiar descarga antigua (solo .onnx suelto) si existe
    final voicesDir = await _voicesDir();
    final oldFile = File('$voicesDir/$voiceId.onnx');
    if (oldFile.existsSync()) {
      print(
          '[PiperTtsService] Detectado modelo antiguo sin config, eliminando: ${oldFile.path}');
      oldFile.deleteSync();
    }

    final subDir = await _voiceSubDir(voiceId);
    final modelFile = await _findModelFile(voiceId);
    final tokensFile = File('$subDir/tokens.txt');
    final dataDir = Directory('$subDir/espeak-ng-data');

    return modelFile != null &&
        tokensFile.existsSync() &&
        dataDir.existsSync();
  }

  /// Descarga el paquete tar.bz2 de la voz y extrae su contenido.
  /// El paquete incluye .onnx, tokens.txt y espeak-ng-data.
  Future<void> downloadVoice(
    String voiceId, {
    void Function(double progress)? onProgress,
  }) async {
    final voice = piperVoiceCatalog.firstWhere((v) => v.id == voiceId);
    final subDir = await _voiceSubDir(voiceId);
    final subDirObj = Directory(subDir);

    // Limpiar directorio previo incompleto si existe
    if (subDirObj.existsSync()) subDirObj.deleteSync(recursive: true);

    // Limpiar formato antiguo (.onnx suelto) si existe
    final voicesDir = await _voicesDir();
    final oldFile = File('$voicesDir/$voiceId.onnx');
    if (oldFile.existsSync()) oldFile.deleteSync();

    try {
      print(
          '[PiperTtsService] Descargando paquete $voiceId: ${voice.packageUrl}');

      final request = http.Request('GET', Uri.parse(voice.packageUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception(
            'Error descargando voz $voiceId: HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final builder = BytesBuilder(copy: false);

      await for (final chunk in response.stream) {
        builder.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }

      final allBytes = builder.toBytes();
      print(
          '[PiperTtsService] Descarga completa (${allBytes.length} bytes), extrayendo...');
      onProgress?.call(1.0);

      // Descomprimir bzip2 y parsear tar
      final tarBytes = BZip2Decoder().decodeBytes(allBytes);
      final archive = TarDecoder().decodeBytes(tarBytes);

      // Determinar el directorio raíz dentro del tarball
      // (ej: 'vits-piper-es_MX-claude-high-int8/')
      String? topDir;
      for (final entry in archive) {
        if (entry.name.contains('/')) {
          topDir = entry.name.split('/').first;
          break;
        }
      }

      // Extraer archivos quitando el prefijo del directorio raíz
      for (final entry in archive) {
        String relative = entry.name;
        if (topDir != null && relative.startsWith('$topDir/')) {
          relative = relative.substring(topDir.length + 1);
        }
        if (relative.isEmpty) continue;

        final destPath = '$subDir/$relative';

        if (entry.isFile) {
          final destFile = File(destPath);
          destFile.parent.createSync(recursive: true);
          destFile.writeAsBytesSync(entry.content as List<int>);
        } else {
          Directory(destPath).createSync(recursive: true);
        }
      }

      // Verificar que los archivos necesarios existen tras la extracción
      final tokensFile = File('$subDir/tokens.txt');
      final dataDir = Directory('$subDir/espeak-ng-data');
      if (!tokensFile.existsSync()) {
        throw Exception(
            'tokens.txt no encontrado después de extraer el paquete $voiceId');
      }
      if (!dataDir.existsSync()) {
        throw Exception(
            'espeak-ng-data no encontrado después de extraer el paquete $voiceId');
      }

      print('[PiperTtsService] Extracción completa para $voiceId en: $subDir');
    } catch (e) {
      if (subDirObj.existsSync()) subDirObj.deleteSync(recursive: true);
      print('[PiperTtsService] Error en downloadVoice($voiceId): $e');
      rethrow;
    }
  }

  /// Elimina el directorio del modelo de una voz descargada.
  Future<void> deleteVoice(String voiceId) async {
    final subDir = Directory(await _voiceSubDir(voiceId));
    if (subDir.existsSync()) subDir.deleteSync(recursive: true);
    // Limpiar formato antiguo también
    final voicesDir = await _voicesDir();
    final oldFile = File('$voicesDir/$voiceId.onnx');
    if (oldFile.existsSync()) oldFile.deleteSync();
  }

  /// Sintetiza texto con la voz indicada y devuelve la ruta a un archivo WAV
  /// temporal. Devuelve null si el modelo no está descargado o la síntesis falla.
  Future<String?> synthesizeToWav(
    String text,
    String voiceId, {
    double speed = 1.0,
  }) async {
    try {
      _ensureInitialized();

      final subDir = await _voiceSubDir(voiceId);
      final modelFile = await _findModelFile(voiceId);

      if (modelFile == null || !modelFile.existsSync()) {
        print('[PiperTtsService] modelo no encontrado para: $voiceId');
        return null;
      }

      final tokensPath = '$subDir/tokens.txt';
      final dataDirPath = '$subDir/espeak-ng-data';

      if (!File(tokensPath).existsSync()) {
        print('[PiperTtsService] tokens.txt no encontrado: $tokensPath');
        return null;
      }
      if (!Directory(dataDirPath).existsSync()) {
        print('[PiperTtsService] espeak-ng-data no encontrado: $dataDirPath');
        return null;
      }

      print('[PiperTtsService] Sintetizando: model=${modelFile.path}');
      print('[PiperTtsService]   tokens=$tokensPath');
      print('[PiperTtsService]   dataDir=$dataDirPath');

      final modelConfig = OfflineTtsVitsModelConfig(
        model: modelFile.path,
        lexicon: '',
        tokens: tokensPath,
        dataDir: dataDirPath,
        dictDir: '',
        noiseScale: 0.667,
        noiseScaleW: 0.8,
        lengthScale: 1.0,
      );

      final config = OfflineTtsConfig(
        model: OfflineTtsModelConfig(
          vits: modelConfig,
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
        maxNumSenetences: 1,
      );

      final tts = OfflineTts(config);
      final audio = tts.generate(text: text, sid: 0, speed: speed);
      tts.free();

      if (audio.samples.isEmpty) return null;

      final tmpDir = await getTemporaryDirectory();
      final wavPath =
          '${tmpDir.path}/piper_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wavBytes = _pcmToWav(audio.samples, audio.sampleRate);
      await File(wavPath).writeAsBytes(wavBytes);
      return wavPath;
    } catch (e) {
      print('[PiperTtsService] synthesizeToWav error: $e');
      return null;
    }
  }

  /// Convierte muestras PCM Float32 a un archivo WAV (16-bit, mono).
  Uint8List _pcmToWav(Float32List samples, int sampleRate) {
    // Convertir float32 → int16
    final pcm16 = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      pcm16[i] = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    }
    final pcmBytes = pcm16.buffer.asUint8List();
    final dataSize = pcmBytes.length;

    final header = ByteData(44);
    // RIFF
    header
      ..setUint8(0, 0x52) ..setUint8(1, 0x49)
      ..setUint8(2, 0x46) ..setUint8(3, 0x46)
      ..setUint32(4, 36 + dataSize, Endian.little)
      ..setUint8(8, 0x57) ..setUint8(9, 0x41)
      ..setUint8(10, 0x56) ..setUint8(11, 0x45)
      // fmt
      ..setUint8(12, 0x66) ..setUint8(13, 0x6D)
      ..setUint8(14, 0x74) ..setUint8(15, 0x20)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)           // PCM
      ..setUint16(22, 1, Endian.little)           // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      // data
      ..setUint8(36, 0x64) ..setUint8(37, 0x61)
      ..setUint8(38, 0x74) ..setUint8(39, 0x61)
      ..setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, pcmBytes);
    return result;
  }
}
