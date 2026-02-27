import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/habit_models.dart';
import 'services/habit_scheduler.dart';
import 'settings_screen.dart';
import 'widgets/color_input_widget.dart';

class HabitEditScreen extends StatefulWidget {
  final HabitModel? habit;

  const HabitEditScreen({super.key, this.habit});

  @override
  State<HabitEditScreen> createState() => _HabitEditScreenState();
}

class _HabitEditScreenState extends State<HabitEditScreen> {
  final HabitScheduler _scheduler = HabitScheduler();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _snoozeMinutesController = TextEditingController();

  bool _cloudSyncEnabled = false;
  bool _syncToCloud = true;
  bool _isActive = true;
  bool _requireConfirmation = true;

  String _repeatMode = 'daily';
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];

  int? _cardBackgroundColorArgb;
  int? _titleTextColorArgb;
  int? _descriptionTextColorArgb;
  int? _timeTextColorArgb;

  String _alertScreenType = 'fullscreen';
  String _alertLayoutId = 'classic';

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    final habit = widget.habit;
    if (habit != null) {
      _titleController.text = habit.title;
      _descriptionController.text = habit.description;
      _snoozeMinutesController.text = habit.defaultSnoozeMinutes.toString();
      _syncToCloud = habit.syncToCloud;
      _isActive = habit.isActive;
      _repeatMode = habit.repeatMode;
      _weekdays = habit.weekdays.toSet();
      _times = List<TimeOfDay>.from(habit.times);
      _requireConfirmation = habit.requireConfirmation;
      _cardBackgroundColorArgb = habit.cardBackgroundColorArgb;
      _titleTextColorArgb = habit.titleTextColorArgb;
      _descriptionTextColorArgb = habit.descriptionTextColorArgb;
      _timeTextColorArgb = habit.timeTextColorArgb;
      _alertScreenType = habit.alertScreenType;
      _alertLayoutId = habit.alertLayoutId;
    } else {
      _snoozeMinutesController.text = '10';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _snoozeMinutesController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    if (!mounted) return;
    setState(() {
      _cloudSyncEnabled = cloudSyncEnabled;
      if (widget.habit == null) {
        _syncToCloud = cloudSyncEnabled;
      }
    });
  }

  String? _hexFromArgb(int? argb) {
    if (argb == null) return null;
    return '#${argb.toRadixString(16).padLeft(8, '0')}';
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return 'L';
      case 2:
        return 'M';
      case 3:
        return 'X';
      case 4:
        return 'J';
      case 5:
        return 'V';
      case 6:
        return 'S';
      case 7:
        return 'D';
      default:
        return '?';
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: _times.isNotEmpty ? _times.first : const TimeOfDay(hour: 8, minute: 0));
    if (picked == null) return;
    setState(() {
      _times = [..._times, picked];
      _times.sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));
    });
  }

  void _removeTime(TimeOfDay t) {
    setState(() {
      _times = _times.where((x) => x != t).toList();
      if (_times.isEmpty) {
        _times = [const TimeOfDay(hour: 8, minute: 0)];
      }
    });
  }

  HabitModel _buildModel() {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final id = widget.habit?.id ?? now.millisecondsSinceEpoch.toString();

    final snooze = int.tryParse(_snoozeMinutesController.text.trim()) ?? 10;
    final habit = HabitModel(
      id: id,
      ownerUid: widget.habit?.ownerUid.isNotEmpty == true ? widget.habit!.ownerUid : userId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      isActive: _isActive,
      syncToCloud: _syncToCloud,
      repeatMode: _repeatMode,
      weekdays: _weekdays.toList()..sort(),
      times: _times,
      requireConfirmation: _requireConfirmation,
      defaultSnoozeMinutes: snooze,
      cardBackgroundColorArgb: _cardBackgroundColorArgb,
      titleTextColorArgb: _titleTextColorArgb,
      descriptionTextColorArgb: _descriptionTextColorArgb,
      timeTextColorArgb: _timeTextColorArgb,
      alertScreenType: _alertScreenType,
      alertLayoutId: _alertLayoutId,
      nextScheduledAtLocal: widget.habit?.nextScheduledAtLocal,
      createdAt: widget.habit?.createdAt ?? now,
      updatedAt: now,
      deletedAt: widget.habit?.deletedAt,
      revision: widget.habit?.revision ?? 0,
      fieldUpdatedAt: widget.habit?.fieldUpdatedAt,
      extras: widget.habit?.extras,
    );

    if (!habit.isActive || habit.deletedAt != null) {
      return habit.copyWith(nextScheduledAtLocal: null);
    }
    final next = _scheduler.nextOccurrenceLocal(habit, now);
    return habit.copyWith(nextScheduledAtLocal: next);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final habit = _buildModel();
    Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Descripción'),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: SwitchListTile(
            title: const Text('Hábito activo'),
            value: _isActive,
            activeColor: scheme.primary,
            onChanged: (v) => setState(() => _isActive = v),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Repetición', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _repeatMode,
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Diario')),
                    DropdownMenuItem(value: 'customDays', child: Text('Días específicos')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _repeatMode = v;
                      if (v == 'daily') {
                        _weekdays = {1, 2, 3, 4, 5, 6, 7};
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (i) {
                    final weekday = i + 1;
                    final selected = _weekdays.contains(weekday);
                    return FilterChip(
                      label: Text(_weekdayLabel(weekday)),
                      selected: selected,
                      onSelected: _repeatMode != 'customDays'
                          ? null
                          : (v) {
                              setState(() {
                                if (v) {
                                  _weekdays.add(weekday);
                                } else {
                                  _weekdays.remove(weekday);
                                  if (_weekdays.isEmpty) {
                                    _weekdays.add(weekday);
                                  }
                                }
                              });
                            },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Horarios',
                        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: _addTime,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: _times
                      .map(
                        (t) => InputChip(
                          label: Text(_formatTime(t)),
                          onDeleted: _times.length <= 1 ? null : () => _removeTime(t),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Requiere confirmación'),
                  value: _requireConfirmation,
                  activeColor: scheme.primary,
                  onChanged: (v) => setState(() => _requireConfirmation = v),
                ),
                TextField(
                  controller: _snoozeMinutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutos de posposición',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pantalla de aviso', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _alertLayoutId,
                  items: const [
                    DropdownMenuItem(value: 'classic', child: Text('Clásica')),
                    DropdownMenuItem(value: 'compactTop', child: Text('Compacta')),
                    DropdownMenuItem(value: 'focusSlider', child: Text('Enfoque')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _alertLayoutId = v);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Colores', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ColorInputWidget(
                  label: 'Fondo',
                  initialColor: _hexFromArgb(_cardBackgroundColorArgb),
                  onColorChanged: (_) {},
                  onParsedColorChanged: (c) => setState(() => _cardBackgroundColorArgb = c?.value),
                ),
                const SizedBox(height: 12),
                ColorInputWidget(
                  label: 'Título',
                  initialColor: _hexFromArgb(_titleTextColorArgb),
                  onColorChanged: (_) {},
                  onParsedColorChanged: (c) => setState(() => _titleTextColorArgb = c?.value),
                ),
                const SizedBox(height: 12),
                ColorInputWidget(
                  label: 'Descripción',
                  initialColor: _hexFromArgb(_descriptionTextColorArgb),
                  onColorChanged: (_) {},
                  onParsedColorChanged: (c) => setState(() => _descriptionTextColorArgb = c?.value),
                ),
                const SizedBox(height: 12),
                ColorInputWidget(
                  label: 'Hora',
                  initialColor: _hexFromArgb(_timeTextColorArgb),
                  onColorChanged: (_) {},
                  onParsedColorChanged: (c) => setState(() => _timeTextColorArgb = c?.value),
                ),
              ],
            ),
          ),
        ),
        if (_cloudSyncEnabled && FirebaseAuth.instance.currentUser != null) ...[
          const SizedBox(height: 16),
          Card(
            color: scheme.surface,
            child: SwitchListTile(
              title: const Text('Guardar en Firebase'),
              subtitle: Text(
                _syncToCloud ? 'Este hábito se sincronizará con la nube' : 'Este hábito solo será local',
                style: TextStyle(color: scheme.onSurface),
              ),
              value: _syncToCloud,
              activeColor: scheme.primary,
              onChanged: (v) => setState(() => _syncToCloud = v),
            ),
          ),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? 'Nuevo hábito' : 'Editar hábito'),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: content,
    );
  }
}

