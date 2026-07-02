import 'package:flutter/material.dart';

import '../models/ai_model_catalog.dart';
import '../services/ai_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatLine {
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime timestamp;

  _ChatLine({
    required this.text,
    required this.isUser,
    this.isError = false,
  }) : timestamp = DateTime.now();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final AiService _ai = AiService.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatLine> _lines = <_ChatLine>[];

  bool _ready = false;
  bool _sending = false;
  String? _status;
  String? _activeModelName;
  static const Duration _responseTimeout = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkModel() async {
    setState(() {
      _status = 'Verificando modelo activo...';
      _ready = false;
      _activeModelName = null;
    });

    try {
      final id = await _ai.activeModelId();
      if (id == null) {
        if (!mounted) return;
        setState(() => _status = 'No hay un modelo activo. Descarga y activa uno desde el gestor.');
        return;
      }

      final entry = AiModelCatalog.byId(id);
      final name = entry?.displayName ?? id;
      final downloaded = await _ai.isModelDownloaded(id);

      if (!mounted) return;
      setState(() {
        _ready = downloaded;
        _activeModelName = name;
        _status = downloaded
            ? 'Modelo activo: $name'
            : 'El modelo "$name" no está descargado. Descárgalo desde el gestor.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error al verificar modelo: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (!_ready || text.isEmpty || _sending) return;

    _inputController.clear();
    setState(() {
      _lines.add(_ChatLine(text: text, isUser: true));
      _sending = true;
      _status = 'Generando respuesta... (puede tardar 10-60 seg según el modelo)';
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      final answer = await _ai.generateText(
        prompt: text,
        systemInstruction: 'Eres un asistente breve, claro y útil. Responde en español.',
        maxOutputTokens: 512,
      ).timeout(
        _responseTimeout,
        onTimeout: () {
          throw TimeoutException(
            'El modelo tardó más de ${_responseTimeout.inSeconds} segundos. '
            'Puede que el dispositivo no tenga suficiente RAM/GPU para este modelo.',
          );
        },
      );

      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _lines.add(
          _ChatLine(
            text: answer.isEmpty ? '(Respuesta vacía)' : answer,
            isUser: false,
          ),
        );
        _status = 'Modelo: $_activeModelName  |  ${stopwatch.elapsedMilliseconds}ms';
      });
      _scrollToBottom();
    } on TimeoutException catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      _showErrorSnackBar(e.message ?? e.toString());
      setState(() {
        _lines.add(_ChatLine(
          text: '⏱ Timeout: el modelo no respondió en ${_responseTimeout.inSeconds}s. '
              'Prueba con un modelo más liviano.',
          isUser: false,
          isError: true,
        ));
        _status = 'Timeout — prueba un modelo más liviano';
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
      setState(() {
        _lines.add(_ChatLine(text: 'Error: $e', isUser: false, isError: true));
        _status = 'Error — revisa los logs';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: scheme.error,
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Error del módulo IA',
              style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onError),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(color: scheme.onError, fontSize: 12),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Revisa los logs (flutter run) para el detalle completo.',
              style: TextStyle(color: scheme.onError.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Cerrar',
          textColor: scheme.onError,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _unloadModel() {
    _ai.unload();
    setState(() => _status = 'Modelo liberado de memoria');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeModelName != null ? 'Chat — $_activeModelName' : 'Chat IA'),
        actions: [
          IconButton(
            tooltip: 'Liberar modelo de memoria',
            icon: const Icon(Icons.memory),
            onPressed: _unloadModel,
          ),
          IconButton(
            tooltip: 'Revisar modelo activo',
            icon: const Icon(Icons.refresh),
            onPressed: _checkModel,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Banner de estado ──────────────────────────────────────────
          if (_status != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: _ready
                  ? scheme.primaryContainer.withValues(alpha: 0.4)
                  : scheme.secondaryContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(
                    _ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                    size: 16,
                    color: _ready ? scheme.primary : scheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _ready ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ── Mensajes ─────────────────────────────────────────────────
          Expanded(
            child: !_ready
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 64,
                            color: scheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _status ??
                                'Descarga y activa un modelo desde el gestor para poder usar el chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      return Align(
                        alignment: line.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: line.isError
                                ? scheme.errorContainer
                                : line.isUser
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: line.isError
                                ? Border.all(color: scheme.error.withValues(alpha: 0.5))
                                : null,
                          ),
                          child: Text(
                            line.text,
                            style: TextStyle(
                              color: line.isError
                                  ? scheme.onErrorContainer
                                  : line.isUser
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // ── Input ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    enabled: _ready && !_sending,
                    decoration: InputDecoration(
                      hintText: _sending ? 'Esperando respuesta...' : 'Escribe un mensaje...',
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (!_ready || _sending) ? null : _sendMessage,
                  child: _sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TimeoutException implements Exception {
  final String? message;
  const TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
