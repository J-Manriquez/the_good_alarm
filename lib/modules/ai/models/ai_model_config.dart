import 'dart:convert';

/// Template de chat que se aplica al prompt antes de enviarlo al modelo.
///
/// Los modelos en flutter_gemma tienen un template interno, pero no siempre
/// coincide con el formato que el modelo fue entrenado a esperar.
/// Esta configuración permite forzar el template correcto manualmente.
enum AiChatTemplate {
  /// Deja que flutter_gemma aplique el template según el [ModelType].
  /// Correcto para Gemma (gemmaIt). Puede generar basura en otros modelos.
  auto,

  /// ChatML — formato estándar de SmolLM, SmolLM2, Qwen, Phi.
  /// <|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n
  chatml,

  /// Llama 3 / Mistral — [INST] {user} [/INST]
  llama,

  /// Solo el texto del usuario sin ningún wrapper de template.
  raw,

  /// Template personalizado definido por el usuario.
  custom,
}

extension AiChatTemplateX on AiChatTemplate {
  String get label {
    switch (this) {
      case AiChatTemplate.auto:
        return 'Auto (según tipo de modelo)';
      case AiChatTemplate.chatml:
        return 'ChatML (SmolLM2, Qwen, Phi)';
      case AiChatTemplate.llama:
        return 'Llama 3 / Mistral';
      case AiChatTemplate.raw:
        return 'Sin template (texto directo)';
      case AiChatTemplate.custom:
        return 'Personalizado';
    }
  }

  String get description {
    switch (this) {
      case AiChatTemplate.auto:
        return 'flutter_gemma aplica el template internamente. '
            'Funciona bien para Gemma IT. Puede fallar en otros modelos.';
      case AiChatTemplate.chatml:
        return 'Recomendado para SmolLM2, Qwen3, Phi. Usa tokens <|im_start|>.';
      case AiChatTemplate.llama:
        return 'Recomendado para Llama 3, Mistral. Usa tokens [INST].';
      case AiChatTemplate.raw:
        return 'Envía el prompt sin wrapping. Útil para depurar o modelos base.';
      case AiChatTemplate.custom:
        return 'Define tu propio template con {system}, {user} y {assistant}.';
    }
  }

  /// Aplica el template al prompt y la instrucción de sistema.
  /// Para [AiChatTemplate.auto] retorna null (flutter_gemma maneja el formato).
  /// Para el resto retorna el prompt formateado listo para pasar como texto raw.
  String? format({
    required String userMessage,
    required String systemInstruction,
    String? customTemplate,
  }) {
    switch (this) {
      case AiChatTemplate.auto:
        return null; // flutter_gemma aplica su propio template
      case AiChatTemplate.chatml:
        final sys = systemInstruction.isNotEmpty
            ? '<|im_start|>system\n$systemInstruction<|im_end|>\n'
            : '';
        return '$sys<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n';
      case AiChatTemplate.llama:
        final sys = systemInstruction.isNotEmpty
            ? '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$systemInstruction<|eot_id|>\n'
            : '<|begin_of_text|>';
        return '$sys<|start_header_id|>user<|end_header_id|>\n\n$userMessage<|eot_id|>\n<|start_header_id|>assistant<|end_header_id|>\n\n';
      case AiChatTemplate.raw:
        return userMessage;
      case AiChatTemplate.custom:
        if (customTemplate == null || customTemplate.isEmpty) return userMessage;
        return customTemplate
            .replaceAll('{system}', systemInstruction)
            .replaceAll('{user}', userMessage)
            .replaceAll('{assistant}', '');
    }
  }
}

/// Configuración de inferencia para un modelo específico.
class AiModelConfig {
  final String modelId;
  final AiChatTemplate template;
  final String customTemplate;
  final String systemInstruction;
  final double temperature;
  final int maxOutputTokens;
  final int topK;

  const AiModelConfig({
    required this.modelId,
    this.template = AiChatTemplate.auto,
    this.customTemplate = '',
    this.systemInstruction = '',
    this.temperature = 0.7,
    this.maxOutputTokens = 512,
    this.topK = 40,
  });

  AiModelConfig copyWith({
    AiChatTemplate? template,
    String? customTemplate,
    String? systemInstruction,
    double? temperature,
    int? maxOutputTokens,
    int? topK,
  }) {
    return AiModelConfig(
      modelId: modelId,
      template: template ?? this.template,
      customTemplate: customTemplate ?? this.customTemplate,
      systemInstruction: systemInstruction ?? this.systemInstruction,
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      topK: topK ?? this.topK,
    );
  }

  Map<String, dynamic> toJson() => {
    'template': template.name,
    'customTemplate': customTemplate,
    'systemInstruction': systemInstruction,
    'temperature': temperature,
    'maxOutputTokens': maxOutputTokens,
    'topK': topK,
  };

  factory AiModelConfig.fromJson(String modelId, Map<String, dynamic> json) {
    return AiModelConfig(
      modelId: modelId,
      template: AiChatTemplate.values.firstWhere(
        (e) => e.name == json['template'],
        orElse: () => AiChatTemplate.auto,
      ),
      customTemplate: (json['customTemplate'] as String?) ?? '',
      systemInstruction: (json['systemInstruction'] as String?) ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxOutputTokens: (json['maxOutputTokens'] as int?) ?? 512,
      topK: (json['topK'] as int?) ?? 40,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory AiModelConfig.fromJsonString(String modelId, String raw) {
    try {
      return AiModelConfig.fromJson(
        modelId,
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return AiModelConfig(modelId: modelId);
    }
  }
}
