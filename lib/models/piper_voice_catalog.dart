// Modelo y catálogo de voces Piper TTS descargables.
// Los paquetes provienen de los releases de sherpa-onnx (variante int8).
// Cada paquete incluye el modelo .onnx, tokens.txt y espeak-ng-data.

class PiperVoice {
  final String id;          // e.g. 'es_MX-claude-high'
  final String displayName; // Nombre legible
  final String locale;      // BCP47, e.g. 'es-MX'
  final String gender;      // 'Femenina' | 'Masculina'
  final String quality;     // 'x_low' | 'low' | 'medium' | 'high'
  final double sizeMb;      // Tamaño aproximado del paquete int8 en MB

  const PiperVoice({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.gender,
    required this.quality,
    required this.sizeMb,
  });

  static const String _sherpaBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// URL del paquete tar.bz2 int8 de sherpa-onnx.
  /// Incluye el .onnx cuantizado, tokens.txt y espeak-ng-data.
  String get packageUrl => '$_sherpaBase/vits-piper-$id-int8.tar.bz2';

  String get qualityLabel {
    switch (quality) {
      case 'x_low':
        return 'Básica';
      case 'low':
        return 'Baja';
      case 'medium':
        return 'Media';
      case 'high':
        return 'Alta';
      default:
        return quality;
    }
  }
}

// Catálogo de voces disponibles para descarga.
const List<PiperVoice> piperVoiceCatalog = [
  // ── Español México ────────────────────────────────────────────────────────
  PiperVoice(
    id: 'es_MX-claude-high',
    displayName: 'Claude',
    locale: 'es-MX',
    gender: 'Femenina',
    quality: 'high',
    sizeMb: 20.2,
  ),
  PiperVoice(
    id: 'es_MX-ald-medium',
    displayName: 'Ald',
    locale: 'es-MX',
    gender: 'Masculina',
    quality: 'medium',
    sizeMb: 20.3,
  ),

  // ── Español España ────────────────────────────────────────────────────────
  PiperVoice(
    id: 'es_ES-carlfm-x_low',
    displayName: 'Carlfm',
    locale: 'es-ES',
    gender: 'Masculina',
    quality: 'x_low',
    sizeMb: 12.7,
  ),
  PiperVoice(
    id: 'es_ES-davefx-medium',
    displayName: 'Davefx',
    locale: 'es-ES',
    gender: 'Masculina',
    quality: 'medium',
    sizeMb: 20.2,
  ),
  PiperVoice(
    id: 'es_ES-sharvard-medium',
    displayName: 'Sharvard',
    locale: 'es-ES',
    gender: 'Femenina',
    quality: 'medium',
    sizeMb: 22.4,
  ),

  // ── English US ────────────────────────────────────────────────────────────
  PiperVoice(
    id: 'en_US-ryan-high',
    displayName: 'Ryan',
    locale: 'en-US',
    gender: 'Masculina',
    quality: 'high',
    sizeMb: 32.9,
  ),
  PiperVoice(
    id: 'en_US-amy-medium',
    displayName: 'Amy',
    locale: 'en-US',
    gender: 'Femenina',
    quality: 'medium',
    sizeMb: 20.1,
  ),
  PiperVoice(
    id: 'en_US-lessac-high',
    displayName: 'Lessac',
    locale: 'en-US',
    gender: 'Femenina',
    quality: 'high',
    sizeMb: 33.4,
  ),
];
