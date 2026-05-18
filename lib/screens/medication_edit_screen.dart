import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';
import '../services/medication_scheduler.dart';
import '../settings_screen.dart';

class MedicationEditScreen extends StatefulWidget {
  final MedicationModel? medication;

  const MedicationEditScreen({super.key, this.medication});

  @override
  State<MedicationEditScreen> createState() => _MedicationEditScreenState();
}

class _MedicationEditScreenState extends State<MedicationEditScreen> {
  final MedicationRepository _repo = MedicationRepository();
  final MedicationScheduler _scheduler = MedicationScheduler();
  final FlutterTts _tts = FlutterTts();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dosageAmountCtrl = TextEditingController();
  final TextEditingController _dosageUnitCtrl = TextEditingController();
  final TextEditingController _typeCtrl = TextEditingController();
  final TextEditingController _instructionsCtrl = TextEditingController();
  final TextEditingController _prescribedByCtrl = TextEditingController();
  final TextEditingController _purposeCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _snoozeCtrl = TextEditingController();
  final TextEditingController _confirmDelayCtrl = TextEditingController();

  bool _cloudSyncEnabled = false;
  bool _syncToCloud = true;
  bool _isActive = true;
  bool _requireConfirmation = true;
  bool _enableTts = true;
  String _ttsLanguage = 'es-MX';
  int _ttsVolume = 80; // 0-100
  String _colorHex = '#4CAF50';
  String _repeatMode = 'daily';
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    final med = widget.medication;
    if (med != null) {
      _nameCtrl.text = med.medicationName;
      _dosageAmountCtrl.text = med.dosageAmount;
      _dosageUnitCtrl.text = med.dosageUnit;
      _typeCtrl.text = med.medicationType;
      _instructionsCtrl.text = med.instructions;
      _prescribedByCtrl.text = med.prescribedBy;
      _purposeCtrl.text = med.purpose;
      _notesCtrl.text = med.notes;
      _snoozeCtrl.text = med.defaultSnoozeMinutes.toString();
      _confirmDelayCtrl.text = med.confirmationDelayMinutes.toString();
      _syncToCloud = med.syncToCloud;
      _isActive = med.isActive;
      _requireConfirmation = med.requireConfirmation;
      _enableTts = med.enableTts;
      _ttsLanguage = med.ttsLanguage;
      _ttsVolume = med.ttsVolume;
      _colorHex = med.colorHex.isEmpty ? '#4CAF50' : med.colorHex;
      _repeatMode = med.repeatMode;
      _weekdays = med.weekdays.toSet();
      _times = List<TimeOfDay>.from(med.times);
    } else {
      _snoozeCtrl.text = '10';
      _confirmDelayCtrl.text = '30';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageAmountCtrl.dispose();
    _dosageUnitCtrl.dispose();
    _typeCtrl.dispose();
    _instructionsCtrl.dispose();
    _prescribedByCtrl.dispose();
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    _snoozeCtrl.dispose();
    _confirmDelayCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final cloudSync = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    if (!mounted) return;
    setState(() {
      _cloudSyncEnabled = cloudSync;
      if (widget.medication == null) _syncToCloud = cloudSync;
    });
  }

  String _weekdayLabel(int wd) {
    const labels = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S', 7: 'D'};
    return labels[wd] ?? '?';
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _times.add(picked);
        _times.sort((a, b) => a.hour != b.hour
            ? a.hour.compareTo(b.hour)
            : a.minute.compareTo(b.minute));
      });
    }
  }

  Future<void> _previewTts() async {
    final med = _buildModel();
    if (med == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ingresa el nombre del medicamento primero')));
      return;
    }
    try {
      await _tts.stop();
      await _tts.setLanguage(_ttsLanguage);
      await _tts.setSpeechRate(0.5);
      await _tts.speak(med.buildTtsReminderText());
    } catch (e) {
      print('[MedicationEditScreen] TTS preview error: $e');
    }
  }

  MedicationModel? _buildModel() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return null;
    final existing = widget.medication;
    final now = DateTime.now();
    return MedicationModel(
      id: existing?.id ?? 'med_${now.millisecondsSinceEpoch}',
      ownerUid: existing?.ownerUid ?? (FirebaseAuth.instance.currentUser?.uid ?? ''),
      medicationName: name,
      dosageAmount: _dosageAmountCtrl.text.trim(),
      dosageUnit: _dosageUnitCtrl.text.trim(),
      medicationType: _typeCtrl.text.trim(),
      instructions: _instructionsCtrl.text.trim(),
      prescribedBy: _prescribedByCtrl.text.trim(),
      purpose: _purposeCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      colorHex: _colorHex,
      isActive: _isActive,
      syncToCloud: _syncToCloud,
      repeatMode: _repeatMode,
      weekdays: _weekdays.toList()..sort(),
      times: List<TimeOfDay>.from(_times),
      requireConfirmation: _requireConfirmation,
      confirmationDelayMinutes:
          int.tryParse(_confirmDelayCtrl.text) ?? 30,
      defaultSnoozeMinutes: int.tryParse(_snoozeCtrl.text) ?? 10,
      enableTts: _enableTts,
      ttsLanguage: _ttsLanguage,
      ttsVolume: _ttsVolume,
      nextScheduledAtLocal: existing?.nextScheduledAtLocal,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _save() async {
    final med = _buildModel();
    if (med == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre del medicamento es obligatorio')),
      );
      return;
    }

    setState(() => _saving = true);
    print('[MedicationEditScreen] guardando medicamento id=${med.id}');

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final next = _scheduler.nextOccurrenceLocal(med, DateTime.now());
      final medWithNext = med.copyWith(nextScheduledAtLocal: next);

      await _repo.upsertMedication(
        medication: medWithNext,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: userId,
      );

      if (_isActive && next != null) {
        await _scheduler.scheduleOccurrence(med: medWithNext, whenLocal: next);
        print('[MedicationEditScreen] ocurrencia programada: ${next.toIso8601String()}');
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      print('[MedicationEditScreen] error guardando: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.medication == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nuevo medicamento' : 'Editar medicamento'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Guardar',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Sección 1: Datos del medicamento ─────────────────────────────
          _sectionHeader('Datos del medicamento', scheme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del medicamento *',
                      prefixIcon: Icon(Icons.medication),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dosageAmountCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dosis (cantidad)',
                            prefixIcon: Icon(Icons.numbers),
                          ),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _dosageUnitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Unidad (mg, ml…)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _typeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tipo (pastilla, jarabe…)',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _instructionsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Instrucciones',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _prescribedByCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prescrito por',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _purposeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Propósito / indicación',
                      prefixIcon: Icon(Icons.healing_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas adicionales',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Color del card
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined),
                      const SizedBox(width: 8),
                      const Text('Color del recordatorio:'),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _pickColor,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(
                                int.tryParse(_colorHex.replaceFirst('#', '0xFF')) ??
                                    0xFF4CAF50),
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outline),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    title: const Text('Activo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─── Sección 2: Horarios ──────────────────────────────────────────
          _sectionHeader('Horarios', scheme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modo repetición
                  const Text('Repetición:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Wrap(
                    spacing: 8,
                    children: [
                      _repeatChip('daily', 'Diario'),
                      _repeatChip('customDays', 'Días específicos'),
                    ],
                  ),
                  if (_repeatMode == 'customDays') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(7, (i) {
                        final wd = i + 1;
                        return FilterChip(
                          label: Text(_weekdayLabel(wd)),
                          selected: _weekdays.contains(wd),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _weekdays.add(wd);
                            } else {
                              _weekdays.remove(wd);
                            }
                          }),
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text('Horas del recordatorio:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ..._times.map((t) => Chip(
                            label: Text(
                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _times.remove(t)),
                          )),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('Agregar hora'),
                        onPressed: _addTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _snoozeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Minutos de postergación (snooze)',
                      prefixIcon: Icon(Icons.snooze),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─── Sección 3: Confirmación ──────────────────────────────────────
          _sectionHeader('Confirmación', scheme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _requireConfirmation,
                    onChanged: (v) => setState(() => _requireConfirmation = v),
                    title: const Text('Pedir confirmación'),
                    subtitle: const Text(
                        'Siempre enviará un recordatorio de confirmación'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_requireConfirmation) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmDelayCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tiempo para la confirmación (minutos)',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─── Sección 4: Voz (TTS) ────────────────────────────────────────
          _sectionHeader('Voz (TTS)', scheme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _enableTts,
                    onChanged: (v) => setState(() => _enableTts = v),
                    title: const Text('Leer recordatorio en voz alta'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_enableTts) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _ttsLanguage,
                      decoration: const InputDecoration(
                          labelText: 'Idioma de voz'),
                      items: const [
                        DropdownMenuItem(value: 'es-MX', child: Text('Español (México)')),
                        DropdownMenuItem(value: 'es-ES', child: Text('Español (España)')),
                        DropdownMenuItem(value: 'en-US', child: Text('English (US)')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _ttsLanguage = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.volume_up, size: 20),
                        const SizedBox(width: 8),
                        const Text('Volumen del recordatorio'),
                        const Spacer(),
                        Text('$_ttsVolume%',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Slider(
                      value: _ttsVolume.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$_ttsVolume%',
                      onChanged: (v) => setState(() => _ttsVolume = v.round()),
                    ),
                    Text(
                      'Este volumen prevalece sobre la configuración del sistema',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _previewTts,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Probar audio'),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─── Sección 5: Sincronización ────────────────────────────────────
          if (_cloudSyncEnabled)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Sincronización', scheme),
                Card(
                  child: SwitchListTile(
                    value: _syncToCloud,
                    onChanged: (v) => setState(() => _syncToCloud = v),
                    title: const Text('Sincronizar con la nube'),
                    subtitle: const Text('Requiere conexión a internet'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),

          // Botón guardar
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: const Text('Guardar medicamento'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _repeatChip(String mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _repeatMode == mode,
      onSelected: (_) => setState(() => _repeatMode = mode),
    );
  }

  Future<void> _pickColor() async {
    final colors = [
      '#4CAF50', '#2196F3', '#9C27B0', '#FF9800',
      '#F44336', '#00BCD4', '#795548', '#607D8B',
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Elige un color'),
        children: colors.map((hex) {
          final color = Color(int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFF4CAF50);
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(hex),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Text(hex),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (picked != null) setState(() => _colorHex = picked);
  }
}
