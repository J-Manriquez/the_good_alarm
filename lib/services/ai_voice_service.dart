import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelo_alarm.dart';
import '../models/calendar_models.dart';
import '../models/habit_models.dart';
import '../models/medication_models.dart';
import '../modules/ai/services/ai_service.dart';
import '../settings_screen.dart';
import 'alarm_local_service.dart';
import 'calendar_local_service.dart';
import 'habit_local_service.dart';
import 'medication_local_service.dart';

// ── Tipos de datos ──────────────────────────────────────────────────────────

enum AssistantIntent { alarm, habit, event, medication, unknown }

enum AssistantStatus { needInfo, ready }

class ConversationMessage {
  final String text;
  final bool isUser;
  ConversationMessage({required this.text, required this.isUser});
}

class AssistantResponse {
  final AssistantIntent intent;
  final AssistantStatus status;
  final Map<String, dynamic> data;
  final List<String> missing;
  final String message;

  AssistantResponse({
    required this.intent,
    required this.status,
    required this.data,
    required this.missing,
    required this.message,
  });
}

// ── Servicio principal ──────────────────────────────────────────────────────

class AiVoiceService {
  AiVoiceService._();
  static final AiVoiceService instance = AiVoiceService._();

  final AlarmLocalService _alarmService = AlarmLocalService();
  final HabitLocalService _habitService = HabitLocalService();
  final MedicationLocalService _medicationService = MedicationLocalService();
  final CalendarLocalService _calendarService = CalendarLocalService();

  static const _alarmChannel = MethodChannel('com.andodevs.the_good_alarm/alarm');

  static const String _systemInstruction = '''Eres un asistente de voz para una app de alarmas y productividad.
Tu única tarea: extraer información de lo que dice el usuario y responder con JSON.
REGLA ABSOLUTA: responde SOLO con JSON válido, sin markdown, sin texto extra, sin bloques de código.

Formato exacto de respuesta (una sola línea JSON):
{"intent":"alarm|habit|event|medication|unknown","status":"need_info|ready","data":{},"missing":[],"message":"texto"}

Tipos de intent:
- alarm: alarma que suena a una hora
- habit: hábito/rutina/tarea recurrente
- event: evento de calendario con fecha específica
- medication: recordatorio de medicamento/pastilla
- unknown: no se entiende

Campos de data según intent:
- alarm: time (HH:MM, obligatorio), title (opcional, describe el propósito), days (opcional: "once","daily","weekdays","weekends" o lista como [1,2,5]), date (YYYY-MM-DD, solo si es una sola vez y se menciona fecha)
- habit: title (obligatorio), time (HH:MM, obligatorio), description (opcional), days (opcional, default "daily")
- event: title (obligatorio), date (YYYY-MM-DD, obligatorio), time (HH:MM, obligatorio), description (opcional)
- medication: name (obligatorio), times (["HH:MM"], obligatorio, puede ser lista), dose (opcional), days (opcional, default "daily")
- unknown: data vacío

Lógica:
- Si falta un campo obligatorio: status="need_info", pregunta solo ese campo en "message"
- Si tienes todos los obligatorios: status="ready", confirma lo que crearás en "message"
- Para alarmas sin fecha específica, "days" por defecto es "once" (una sola vez, próxima ocurrencia)
- Interpreta el español natural: "a las 7", "mañana", "de lunes a viernes", "todos los días", "pastilla de", etc.
- Infiere el título si el usuario lo menciona (ej: "alarma para ir al gym" → title: "Ir al gym")
- Responde siempre en español, sé breve y amigable''';

  // ── Procesar mensaje del usuario ─────────────────────────────────────────

  Future<AssistantResponse> processMessage({
    required String userMessage,
    required List<ConversationMessage> history,
  }) async {
    final ready = await AiService.instance.isModelReady();
    if (!ready) {
      return AssistantResponse(
        intent: AssistantIntent.unknown,
        status: AssistantStatus.needInfo,
        data: {},
        missing: [],
        message: 'El modelo de IA no está activo. Ve a Configuración → Módulo IA para descargarlo.',
      );
    }

    final prompt = _buildPrompt(userMessage: userMessage, history: history);
    String raw;
    try {
      raw = await AiService.instance.generateText(
        prompt: prompt,
        systemInstruction: _systemInstruction,
        maxOutputTokens: 256,
        temperature: 0.2,
      );
    } catch (e) {
      return AssistantResponse(
        intent: AssistantIntent.unknown,
        status: AssistantStatus.needInfo,
        data: {},
        missing: [],
        message: 'Error al generar respuesta: $e',
      );
    }

    return _parseResponse(raw);
  }

  // ── Construir prompt con historial ──────────────────────────────────────

  String _buildPrompt({
    required String userMessage,
    required List<ConversationMessage> history,
  }) {
    final buffer = StringBuffer();

    // Incluir hasta 6 mensajes de historial para contexto
    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;
    if (recent.isNotEmpty) {
      buffer.writeln('Conversación previa:');
      for (final msg in recent) {
        buffer.writeln('${msg.isUser ? "Usuario" : "Asistente"}: ${msg.text}');
      }
      buffer.writeln();
    }

    buffer.writeln('Usuario dice ahora: $userMessage');
    buffer.writeln('Responde con JSON:');
    return buffer.toString();
  }

  // ── Parsear respuesta JSON ───────────────────────────────────────────────

  AssistantResponse _parseResponse(String raw) {
    // Limpiar posibles artefactos de markdown
    String cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll(RegExp(r'```[a-z]*\n?'), '').trim();
    }

    // Buscar el primer { y último } para extraer solo el JSON
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return AssistantResponse(
        intent: AssistantIntent.unknown,
        status: AssistantStatus.needInfo,
        data: {},
        missing: [],
        message: 'No entendí tu solicitud. ¿Puedes reformularla? Por ejemplo: "Crea una alarma para las 7 de la mañana".',
      );
    }

    final intentStr = json['intent'] as String? ?? 'unknown';
    final statusStr = json['status'] as String? ?? 'need_info';
    final data = (json['data'] as Map<String, dynamic>?) ?? {};
    final missing = ((json['missing'] as List?) ?? []).cast<String>();
    final message = json['message'] as String? ?? 'Entendido.';

    final intent = _parseIntent(intentStr);
    final status = statusStr == 'ready'
        ? AssistantStatus.ready
        : AssistantStatus.needInfo;

    return AssistantResponse(
      intent: intent,
      status: status,
      data: data,
      missing: missing,
      message: message,
    );
  }

  AssistantIntent _parseIntent(String s) {
    switch (s.toLowerCase()) {
      case 'alarm':
        return AssistantIntent.alarm;
      case 'habit':
        return AssistantIntent.habit;
      case 'event':
        return AssistantIntent.event;
      case 'medication':
        return AssistantIntent.medication;
      default:
        return AssistantIntent.unknown;
    }
  }

  // ── Crear entidades ──────────────────────────────────────────────────────

  Future<String> createEntity(AssistantResponse response) async {
    try {
      switch (response.intent) {
        case AssistantIntent.alarm:
          return await _createAlarm(response.data);
        case AssistantIntent.habit:
          return await _createHabit(response.data);
        case AssistantIntent.event:
          return await _createEvent(response.data);
        case AssistantIntent.medication:
          return await _createMedication(response.data);
        case AssistantIntent.unknown:
          return 'No se pudo identificar qué crear.';
      }
    } catch (e) {
      return 'Error al crear: $e';
    }
  }

  // ── Alarma ───────────────────────────────────────────────────────────────

  Future<String> _createAlarm(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    final timeStr = data['time'] as String? ?? '08:00';
    final alarmTime = _parseTime(timeStr);
    final title = data['title'] as String? ?? 'Alarma';
    final daysValue = data['days'];
    final dateStr = data['date'] as String?;

    final now = DateTime.now();
    DateTime base;
    if (dateStr != null) {
      base = DateTime.tryParse(dateStr) ?? now;
    } else {
      base = now;
    }

    final scheduledTime = DateTime(
      base.year,
      base.month,
      base.day,
      alarmTime.hour,
      alarmTime.minute,
    );
    // Si la hora ya pasó hoy, mover a mañana
    final finalTime = (scheduledTime.isBefore(now) && dateStr == null)
        ? scheduledTime.add(const Duration(days: 1))
        : scheduledTime;

    final repeatDays = _parseDays(daysValue);
    final isDaily = daysValue == 'daily';
    final isWeekend = daysValue == 'weekends';

    final id = DateTime.now().millisecondsSinceEpoch;
    final alarm = Alarm(
      id: id,
      time: finalTime,
      title: title,
      message: '',
      isActive: true,
      isDaily: isDaily,
      isWeekend: isWeekend,
      repeatDays: repeatDays,
      enableTts: true,
      ttsLanguage: prefs.getString(SettingsScreen.defaultTtsLanguageKey) ?? 'es-MX',
      ttsVolume: prefs.getInt(SettingsScreen.defaultTtsVolumeKey) ?? 80,
      ttsPitch: prefs.getDouble(SettingsScreen.defaultTtsPitchKey) ?? 1.0,
      ttsRepeatCount: prefs.getInt(SettingsScreen.defaultTtsRepeatCountKey) ?? 3,
      ttsRepeatDelaySeconds: prefs.getInt(SettingsScreen.defaultTtsRepeatDelayKey) ?? 1,
      maxVolumePercent: prefs.getInt(SettingsScreen.defaultMaxVolumeKey) ?? 100,
      volumeRampUpDurationSeconds: prefs.getInt(SettingsScreen.defaultVolumeRampUpKey) ?? 30,
      maxSnoozes: prefs.getInt(SettingsScreen.maxSnoozesKey) ?? 3,
      snoozeDurationMinutes: prefs.getInt(SettingsScreen.snoozeDurationKey) ?? 5,
      createdAt: DateTime.now(),
    );

    await _alarmService.upsertAlarm(alarm);
    await _scheduleNativeAlarm(alarm);

    final timeLabel = '${alarmTime.hour.toString().padLeft(2, '0')}:${alarmTime.minute.toString().padLeft(2, '0')}';
    return 'Alarma "$title" creada para las $timeLabel.';
  }

  Future<void> _scheduleNativeAlarm(Alarm alarm) async {
    try {
      List<int> repeatDays = alarm.repeatDays;
      if (alarm.isDaily) repeatDays = [1, 2, 3, 4, 5, 6, 7];
      if (alarm.isWeekend) repeatDays = [6, 7];

      await _alarmChannel.invokeMethod('setAlarm', {
        'id': alarm.id,
        'hour': alarm.time.hour,
        'minute': alarm.time.minute,
        'title': alarm.title,
        'message': alarm.message,
        'screenRoute': '/alarm',
        'repeatDays': repeatDays,
        'isDaily': alarm.isDaily,
        'isWeekly': alarm.isWeekly,
        'isWeekend': alarm.isWeekend,
        'maxSnoozes': alarm.maxSnoozes,
        'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
        'maxVolumePercent': alarm.maxVolumePercent,
        'volumeRampUpDurationSeconds': alarm.volumeRampUpDurationSeconds,
        'tempVolumeReductionPercent': alarm.tempVolumeReductionPercent,
        'tempVolumeReductionDurationSeconds': alarm.tempVolumeReductionDurationSeconds,
      });
    } catch (e) {
      debugPrint('[AiVoiceService] Error scheduling native alarm: $e');
    }
  }

  // ── Hábito ────────────────────────────────────────────────────────────────

  Future<String> _createHabit(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? 'Hábito';
    final description = data['description'] as String? ?? '';
    final timeStr = data['time'] as String? ?? '08:00';
    final tod = _parseTime(timeStr);
    final daysValue = data['days'];
    final weekdays = _parseDaysForModel(daysValue);
    final repeatMode = _parseRepeatMode(daysValue);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final habit = HabitModel(
      id: id,
      ownerUid: uid,
      title: title,
      description: description,
      isActive: true,
      repeatMode: repeatMode,
      weekdays: weekdays,
      times: [TimeOfDay(hour: tod.hour, minute: tod.minute)],
      createdAt: DateTime.now(),
    );

    await _habitService.upsertHabit(habit);

    final timeLabel = '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
    return 'Hábito "$title" creado a las $timeLabel.';
  }

  // ── Evento ────────────────────────────────────────────────────────────────

  Future<String> _createEvent(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? 'Evento';
    final description = data['description'] as String? ?? '';
    final dateStr = data['date'] as String? ?? DateTime.now().toIso8601String().substring(0, 10);
    final timeStr = data['time'] as String? ?? '08:00';
    final tod = _parseTime(timeStr);

    final eventDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final startAt = DateTime(eventDate.year, eventDate.month, eventDate.day, tod.hour, tod.minute);
    final endAt = startAt.add(const Duration(hours: 1));

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Obtener o crear el calendario por defecto
    final calendars = await _calendarService.getAllCalendars();
    String calendarId;
    if (calendars.isNotEmpty) {
      calendarId = calendars.first.id;
    } else {
      calendarId = 'default_${DateTime.now().millisecondsSinceEpoch}';
      await _calendarService.upsertCalendar(CalendarModel(
        id: calendarId,
        ownerUid: uid,
        name: 'Mi calendario',
        colorArgb: 0xFF4CAF50,
        timeZone: 'America/Mexico_City',
      ));
    }

    final eventId = DateTime.now().millisecondsSinceEpoch.toString();
    final event = CalendarEvent(
      id: eventId,
      calendarId: calendarId,
      title: title,
      description: description,
      startAt: startAt,
      endAt: endAt,
      createdAt: DateTime.now(),
    );

    await _calendarService.upsertEvent(event);

    final dateLabel = '${eventDate.day}/${eventDate.month}/${eventDate.year}';
    final timeLabel = '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
    return 'Evento "$title" creado para el $dateLabel a las $timeLabel.';
  }

  // ── Medicamento ───────────────────────────────────────────────────────────

  Future<String> _createMedication(Map<String, dynamic> data) async {
    final name = data['name'] as String? ?? 'Medicamento';
    final dose = data['dose'] as String? ?? '';
    final timesRaw = data['times'];
    final daysValue = data['days'];

    List<TimeOfDay> times;
    if (timesRaw is List && timesRaw.isNotEmpty) {
      times = timesRaw
          .map((t) => _parseTime(t.toString()))
          .map((t) => TimeOfDay(hour: t.hour, minute: t.minute))
          .toList();
    } else if (timesRaw is String) {
      final t = _parseTime(timesRaw);
      times = [TimeOfDay(hour: t.hour, minute: t.minute)];
    } else {
      times = [const TimeOfDay(hour: 8, minute: 0)];
    }

    final weekdays = _parseDaysForModel(daysValue);
    final repeatMode = _parseRepeatMode(daysValue);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final medication = MedicationModel(
      id: id,
      ownerUid: uid,
      medicationName: name,
      dosageAmount: dose,
      isActive: true,
      repeatMode: repeatMode,
      weekdays: weekdays,
      times: times,
      createdAt: DateTime.now(),
    );

    await _medicationService.upsertMedication(medication);

    final timeLabels = times
        .map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
        .join(', ');
    return 'Medicamento "$name" creado para las $timeLabels.';
  }

  // ── Helpers de parsing ────────────────────────────────────────────────────

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '8') ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  List<int> _parseDays(dynamic daysValue) {
    if (daysValue == null || daysValue == 'once') return [];
    if (daysValue == 'daily') return [1, 2, 3, 4, 5, 6, 7];
    if (daysValue == 'weekdays') return [1, 2, 3, 4, 5];
    if (daysValue == 'weekends') return [6, 7];
    if (daysValue is List) {
      return daysValue.map((e) => (e as num).toInt()).toList();
    }
    return [];
  }

  List<int> _parseDaysForModel(dynamic daysValue) {
    if (daysValue == null || daysValue == 'daily') return [1, 2, 3, 4, 5, 6, 7];
    if (daysValue == 'weekdays') return [1, 2, 3, 4, 5];
    if (daysValue == 'weekends') return [6, 7];
    if (daysValue is List) {
      return daysValue.map((e) => (e as num).toInt()).toList();
    }
    return [1, 2, 3, 4, 5, 6, 7];
  }

  String _parseRepeatMode(dynamic daysValue) {
    if (daysValue == null || daysValue == 'daily') return 'daily';
    return 'customDays';
  }
}
