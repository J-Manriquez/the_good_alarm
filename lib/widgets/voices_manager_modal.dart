import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/piper_voice_catalog.dart';
import '../services/piper_tts_service.dart';

/// Modal para gestionar voces Piper TTS descargables.
/// Retorna el voiceId seleccionado o null al cerrar.
class VoicesManagerModal extends StatefulWidget {
  final String? selectedVoiceId;

  const VoicesManagerModal({super.key, this.selectedVoiceId});

  @override
  State<VoicesManagerModal> createState() => _VoicesManagerModalState();
}

class _VoicesManagerModalState extends State<VoicesManagerModal> {
  final _service = PiperTtsService.instance;
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {}; // voiceId → 0.0–1.0
  final Set<String> _downloading = {};
  String? _selected;

  AudioPlayer? _previewPlayer;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedVoiceId;
    _refreshDownloaded();
  }

  Future<void> _refreshDownloaded() async {
    final results = <String>{};
    for (final v in piperVoiceCatalog) {
      if (await _service.isDownloaded(v.id)) results.add(v.id);
    }
    if (mounted) setState(() => _downloaded.addAll(results));
  }

  Future<void> _download(PiperVoice voice) async {
    setState(() {
      _downloading.add(voice.id);
      _progress[voice.id] = 0.0;
    });
    try {
      await _service.downloadVoice(voice.id, onProgress: (p) {
        if (mounted) setState(() => _progress[voice.id] = p);
      });
      if (mounted) {
        setState(() {
          _downloaded.add(voice.id);
          _downloading.remove(voice.id);
          _progress.remove(voice.id);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading.remove(voice.id);
          _progress.remove(voice.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error descargando ${voice.displayName}: $e')),
        );
      }
    }
  }

  Future<void> _delete(PiperVoice voice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar voz'),
        content: Text('¿Eliminar "${voice.displayName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteVoice(voice.id);
    if (mounted) {
      setState(() {
        _downloaded.remove(voice.id);
        if (_selected == voice.id) _selected = null;
      });
    }
  }

  Future<void> _preview(PiperVoice voice) async {
    await _previewPlayer?.stop();
    await _previewPlayer?.dispose();
    _previewPlayer = null;

    const sampleText = 'Hola, esta es una prueba de voz. Son las ocho de la mañana.';
    final wavPath = await _service.synthesizeToWav(sampleText, voice.id);
    if (wavPath == null || !mounted) return;

    _previewPlayer = AudioPlayer();
    await _previewPlayer!.play(DeviceFileSource(wavPath));
  }

  @override
  void dispose() {
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Agrupar por locale
    final locales = piperVoiceCatalog.map((v) => v.locale).toSet().toList()
      ..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.record_voice_over),
                const SizedBox(width: 8),
                Text(
                  'Voces Piper TTS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_selected != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Usar seleccionada'),
                  ),
                if (_selected == null && widget.selectedVoiceId != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Quitar voz Piper'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final locale in locales) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 12, bottom: 4),
                    child: Text(
                      _localeLabel(locale),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (final voice in piperVoiceCatalog
                      .where((v) => v.locale == locale))
                    _voiceTile(voice, scheme),
                ],
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Las voces se descargan una sola vez y funcionan sin conexión.',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceTile(PiperVoice voice, ColorScheme scheme) {
    final isDownloaded = _downloaded.contains(voice.id);
    final isDownloading = _downloading.contains(voice.id);
    final isSelected = _selected == voice.id;
    final progress = _progress[voice.id] ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSelected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  voice.gender == 'Masculina' ? Icons.man : Icons.woman,
                  color: scheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  voice.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                _chip(voice.gender, scheme),
                const SizedBox(width: 4),
                _chip(voice.qualityLabel, scheme),
                const Spacer(),
                Text(
                  '${voice.sizeMb.toStringAsFixed(0)} MB',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: scheme.surface,
              ),
              const SizedBox(height: 4),
              Text(
                progress > 0
                    ? 'Descargando… ${(progress * 100).toStringAsFixed(0)}%'
                    : 'Iniciando descarga…',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (isDownloaded) ...[
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 20),
                      tooltip: 'Probar voz',
                      onPressed: () => _preview(voice),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: isSelected
                          ? null
                          : () => setState(() => _selected = voice.id),
                      icon: Icon(
                        isSelected ? Icons.check : Icons.check_circle_outline,
                        size: 16,
                      ),
                      label: Text(isSelected ? 'Seleccionada' : 'Seleccionar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: scheme.error),
                      tooltip: 'Eliminar',
                      onPressed: () => _delete(voice),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: () => _download(voice),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Descargar'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
        ),
      );

  String _localeLabel(String locale) {
    const map = {
      'es-MX': 'Español · México',
      'es-ES': 'Español · España',
      'en-US': 'English · US',
    };
    return map[locale] ?? locale;
  }
}
