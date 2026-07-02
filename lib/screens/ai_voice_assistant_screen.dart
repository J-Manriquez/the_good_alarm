import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../modules/ai/services/ai_service.dart';
import '../services/ai_voice_service.dart';
import '../settings_screen.dart';

// ── Estado de la pantalla ───────────────────────────────────────────────────

enum _ScreenState {
  idle,       // Esperando que el usuario pulse el micrófono
  listening,  // Grabando voz del usuario
  thinking,   // IA procesando
  responding, // Mostrando respuesta (+ TTS reproduciéndose)
  confirming, // Esperando confirmación del usuario para crear
  creating,   // Guardando la entidad
  done,       // Éxito
}

// ── Screen ──────────────────────────────────────────────────────────────────

class AiVoiceAssistantScreen extends StatefulWidget {
  const AiVoiceAssistantScreen({super.key});

  @override
  State<AiVoiceAssistantScreen> createState() => _AiVoiceAssistantScreenState();
}

class _AiVoiceAssistantScreenState extends State<AiVoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  // ── Servicios ──────────────────────────────────────────────────────────
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiVoiceService _aiService = AiVoiceService.instance;

  // ── Estado ──────────────────────────────────────────────────────────────
  _ScreenState _state = _ScreenState.idle;
  bool _sttAvailable = false;
  bool _aiAvailable = false;
  String _partialText = '';
  final List<ConversationMessage> _history = [];
  AssistantResponse? _pendingResponse;
  String? _statusMessage;

  // ── Animación del micrófono ──────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── TTS locale ──────────────────────────────────────────────────────────
  String _ttsLocale = 'es-MX';
  double _ttsPitch = 1.0;
  double _ttsVolume = 0.8;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  // ── Inicialización ──────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsLocale = prefs.getString(SettingsScreen.defaultTtsLanguageKey) ?? 'es-MX';
    _ttsPitch = prefs.getDouble(SettingsScreen.defaultTtsPitchKey) ?? 1.0;
    _ttsVolume = (prefs.getInt(SettingsScreen.defaultTtsVolumeKey) ?? 80) / 100.0;

    await _tts.setLanguage(_ttsLocale);
    await _tts.setPitch(_ttsPitch);
    await _tts.setVolume(_ttsVolume);
    _tts.setCompletionHandler(() {
      if (mounted && _state == _ScreenState.responding) {
        setState(() => _state = _ScreenState.confirming);
      }
    });

    final sttOk = await _stt.initialize(
      onError: (error) => debugPrint('[STT] error: ${error.errorMsg}'),
    );
    final aiOk = await AiService.instance.isModelReady();

    if (mounted) {
      setState(() {
        _sttAvailable = sttOk;
        _aiAvailable = aiOk;
        _statusMessage = !sttOk
            ? 'El micrófono no está disponible en este dispositivo.'
            : !aiOk
                ? 'No hay modelo de IA activo. Ve a Configuración → Módulo IA para descargarlo.'
                : null;
      });
    }
  }

  // ── STT ─────────────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    if (!_sttAvailable || !_aiAvailable) return;
    setState(() {
      _state = _ScreenState.listening;
      _partialText = '';
    });
    _tts.stop();

    await _stt.listen(
      onResult: _onSttResult,
      listenOptions: SpeechListenOptions(
        localeId: _ttsLocale.replaceAll('-', '_'),
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _stt.stop();
    if (_partialText.trim().isNotEmpty) {
      await _processUserInput(_partialText.trim());
    } else {
      setState(() => _state = _ScreenState.idle);
    }
  }

  void _onSttResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _partialText = result.recognizedWords);
    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      _processUserInput(result.recognizedWords.trim());
    }
  }

  // ── Procesamiento IA ─────────────────────────────────────────────────────

  Future<void> _processUserInput(String text) async {
    if (text.isEmpty) {
      setState(() => _state = _ScreenState.idle);
      return;
    }

    await _stt.stop();
    _addMessage(text: text, isUser: true);

    setState(() {
      _state = _ScreenState.thinking;
      _partialText = '';
    });

    final response = await _aiService.processMessage(
      userMessage: text,
      history: _history,
    );

    _addMessage(text: response.message, isUser: false);

    if (!mounted) return;
    setState(() {
      _pendingResponse = response;
      _state = _ScreenState.responding;
    });

    await _speakResponse(response.message);
  }

  void _addMessage({required String text, required bool isUser}) {
    _history.add(ConversationMessage(text: text, isUser: isUser));
  }

  Future<void> _speakResponse(String text) async {
    await _tts.speak(text);
    // El handler de completion cambia el estado a confirming
    // Si TTS no dispara (silencio del sistema), cambiamos manualmente tras delay
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _state == _ScreenState.responding) {
        setState(() => _state = _ScreenState.confirming);
      }
    });
  }

  // ── Confirmar creación ───────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_pendingResponse == null) return;
    setState(() => _state = _ScreenState.creating);

    final result = await _aiService.createEntity(_pendingResponse!);

    _addMessage(text: result, isUser: false);
    await _speakResponse(result);

    if (!mounted) return;
    setState(() {
      _pendingResponse = null;
      _state = _ScreenState.done;
    });
  }

  void _cancel() {
    const cancelMsg = 'De acuerdo, no se creó nada. ¿En qué más te ayudo?';
    _addMessage(text: cancelMsg, isUser: false);
    _tts.speak(cancelMsg);
    setState(() {
      _pendingResponse = null;
      _state = _ScreenState.idle;
    });
  }

  void _reset() {
    _tts.stop();
    setState(() {
      _history.clear();
      _pendingResponse = null;
      _partialText = '';
      _state = _ScreenState.idle;
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente IA'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Nueva conversación',
              onPressed: _reset,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Estado del modelo ─────────────────────────────────────────
          if (_statusMessage != null)
            _StatusBanner(message: _statusMessage!, scheme: scheme),

          // ── Historial de conversación ─────────────────────────────────
          Expanded(
            child: _history.isEmpty
                ? _EmptyState(
                    aiAvailable: _aiAvailable,
                    sttAvailable: _sttAvailable,
                    scheme: scheme,
                  )
                : _ConversationList(
                    history: _history,
                    partialText: _partialText,
                    scheme: scheme,
                  ),
          ),

          // ── Zona de transcripción parcial ─────────────────────────────
          if (_state == _ScreenState.listening && _partialText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
              ),
              child: Text(
                _partialText,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // ── Barra de estado IA ────────────────────────────────────────
          if (_state == _ScreenState.thinking)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.tertiary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'IA procesando...',
                    style: TextStyle(color: scheme.tertiary, fontSize: 13),
                  ),
                ],
              ),
            ),

          if (_state == _ScreenState.creating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Creando...',
                    style: TextStyle(color: scheme.primary, fontSize: 13),
                  ),
                ],
              ),
            ),

          // ── Controles principales ─────────────────────────────────────
          _BottomControls(
            state: _state,
            aiAvailable: _aiAvailable,
            sttAvailable: _sttAvailable,
            pendingResponse: _pendingResponse,
            pulseAnim: _pulseAnim,
            scheme: scheme,
            onMicTap: () {
              if (_state == _ScreenState.listening) {
                _stopListening();
              } else if (_state == _ScreenState.idle ||
                  _state == _ScreenState.confirming ||
                  _state == _ScreenState.done) {
                _startListening();
              }
            },
            onConfirm: _confirm,
            onCancel: _cancel,
          ),
        ],
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final ColorScheme scheme;
  const _StatusBanner({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.errorContainer.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 16, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool aiAvailable;
  final bool sttAvailable;
  final ColorScheme scheme;
  const _EmptyState({
    required this.aiAvailable,
    required this.sttAvailable,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_none,
              size: 72,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Asistente de Voz IA',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Pulsa el micrófono y di qué quieres crear:\n\n'
              '🔔 "Crea una alarma para las 7 de la mañana"\n'
              '✅ "Recuérdame tomar agua a las 9 todos los días"\n'
              '📅 "Agrega una reunión el viernes a las 15:00"\n'
              '💊 "Recuérdame tomar mi pastilla de tensión a las 8"',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationList extends StatefulWidget {
  final List<ConversationMessage> history;
  final String partialText;
  final ColorScheme scheme;

  const _ConversationList({
    required this.history,
    required this.partialText,
    required this.scheme,
  });

  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> {
  final ScrollController _ctrl = ScrollController();

  @override
  void didUpdateWidget(_ConversationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ctrl.hasClients) {
        _ctrl.animateTo(
          _ctrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _ctrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: widget.history.length,
      itemBuilder: (context, index) {
        final msg = widget.history[index];
        return _Bubble(message: msg, scheme: widget.scheme);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final ConversationMessage message;
  final ColorScheme scheme;
  const _Bubble({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Icon(Icons.smart_toy_outlined, size: 16, color: scheme.tertiary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 6),
              Icon(Icons.person_outline, size: 16, color: scheme.onPrimaryContainer),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  final _ScreenState state;
  final bool aiAvailable;
  final bool sttAvailable;
  final AssistantResponse? pendingResponse;
  final Animation<double> pulseAnim;
  final ColorScheme scheme;
  final VoidCallback onMicTap;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _BottomControls({
    required this.state,
    required this.aiAvailable,
    required this.sttAvailable,
    required this.pendingResponse,
    required this.pulseAnim,
    required this.scheme,
    required this.onMicTap,
    required this.onConfirm,
    required this.onCancel,
  });

  bool get _canInteract => aiAvailable && sttAvailable;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Botones de confirmación (cuando IA tiene todo listo) ──
            if ((state == _ScreenState.confirming || state == _ScreenState.responding) &&
                pendingResponse?.status == AssistantStatus.ready) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirmar'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Micrófono ─────────────────────────────────────────────
            if (state != _ScreenState.thinking && state != _ScreenState.creating)
              Column(
                children: [
                  _MicButton(
                    isListening: state == _ScreenState.listening,
                    canInteract: _canInteract,
                    pulseAnim: pulseAnim,
                    scheme: scheme,
                    onTap: onMicTap,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state == _ScreenState.listening
                        ? 'Toca para detener'
                        : state == _ScreenState.confirming &&
                              pendingResponse?.status == AssistantStatus.needInfo
                            ? 'Toca para responder'
                            : state == _ScreenState.done
                                ? 'Toca para continuar'
                                : !_canInteract
                                    ? 'No disponible'
                                    : 'Toca y habla',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool isListening;
  final bool canInteract;
  final Animation<double> pulseAnim;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _MicButton({
    required this.isListening,
    required this.canInteract,
    required this.pulseAnim,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canInteract ? onTap : null,
      child: AnimatedBuilder(
        animation: pulseAnim,
        builder: (context, child) {
          final scale = isListening ? pulseAnim.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !canInteract
                ? scheme.onSurface.withValues(alpha: 0.15)
                : isListening
                    ? scheme.error
                    : scheme.primary,
            boxShadow: canInteract
                ? [
                    BoxShadow(
                      color: (isListening ? scheme.error : scheme.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: isListening ? 20 : 10,
                      spreadRadius: isListening ? 4 : 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            isListening ? Icons.stop : Icons.mic,
            size: 36,
            color: !canInteract
                ? scheme.onSurface.withValues(alpha: 0.3)
                : isListening
                    ? scheme.onError
                    : scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
