import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/habit_models.dart';
import 'services/habit_repository.dart';
import 'services/habit_scheduler.dart';
import 'settings_screen.dart';

class HabitAlertScreen extends StatefulWidget {
  final String habitId;
  final String occurrenceKey;
  final int scheduledAtLocalMillis;

  const HabitAlertScreen({
    super.key,
    required this.habitId,
    required this.occurrenceKey,
    required this.scheduledAtLocalMillis,
  });

  @override
  State<HabitAlertScreen> createState() => _HabitAlertScreenState();
}

class _HabitAlertScreenState extends State<HabitAlertScreen> {
  final HabitRepository _repo = HabitRepository();
  final HabitScheduler _scheduler = HabitScheduler();

  bool _cloudSyncEnabled = false;
  bool _loading = true;
  HabitModel? _habit;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    final habit = await _repo.loadLocalHabit(widget.habitId);
    if (!mounted) return;
    setState(() {
      _habit = habit;
      _loading = false;
    });
  }

  DateTime get _scheduledAtLocal =>
      DateTime.fromMillisecondsSinceEpoch(widget.scheduledAtLocalMillis);

  Future<void> _markDone() async {
    final habit = _habit;
    if (habit == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final completion = HabitCompletionModel(
      id: widget.occurrenceKey,
      ownerUid: habit.ownerUid,
      habitId: habit.id,
      scheduledAtLocal: _scheduledAtLocal,
      completedAtLocal: DateTime.now(),
      status: 'done',
      note: '',
    );

    await _repo.upsertCompletion(
      completion: completion,
      cloudSyncEnabled: _cloudSyncEnabled,
      userId: userId,
    );

    final next = _scheduler.nextOccurrenceLocal(habit, DateTime.now());
    final updatedHabit = habit.copyWith(nextScheduledAtLocal: next);
    await _repo.upsertHabit(habit: updatedHabit, cloudSyncEnabled: _cloudSyncEnabled, userId: userId);

    if (next != null) {
      try {
        await _scheduler.scheduleOccurrence(habit: updatedHabit, whenLocal: next);
      } catch (_) {}
    }

    try {
      await _scheduler.clearScreenFlag(occurrenceKey: widget.occurrenceKey);
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    final habit = _habit;
    if (habit == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final snoozeAt = DateTime.now().add(Duration(minutes: habit.defaultSnoozeMinutes));
    final updatedHabit = habit.copyWith(nextScheduledAtLocal: snoozeAt);
    await _repo.upsertHabit(habit: updatedHabit, cloudSyncEnabled: _cloudSyncEnabled, userId: userId);
    try {
      await _scheduler.scheduleOccurrence(habit: updatedHabit, whenLocal: snoozeAt);
    } catch (_) {}

    try {
      await _scheduler.clearScreenFlag(occurrenceKey: widget.occurrenceKey);
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildClassic(HabitModel habit, ColorScheme scheme) {
    final cardColor = habit.cardBackgroundColorArgb != null
        ? Color(habit.cardBackgroundColorArgb!)
        : scheme.surface;
    final titleColor = habit.titleTextColorArgb != null
        ? Color(habit.titleTextColorArgb!)
        : scheme.onSurface;
    final descColor = habit.descriptionTextColorArgb != null
        ? Color(habit.descriptionTextColorArgb!)
        : scheme.onSurface.withOpacity(0.85);
    final timeColor = habit.timeTextColorArgb != null
        ? Color(habit.timeTextColorArgb!)
        : scheme.primary;
    final scheduled = _scheduledAtLocal;
    final timeText =
        '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';

    return Center(
      child: Card(
        color: cardColor,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(timeText, style: TextStyle(color: timeColor, fontSize: 42, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(habit.title, style: TextStyle(color: titleColor, fontSize: 22, fontWeight: FontWeight.w800)),
              if (habit.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(habit.description, textAlign: TextAlign.center, style: TextStyle(color: descColor)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _markDone,
                      child: const Text('Hecho'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _snooze,
                      child: const Text('Posponer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTop(HabitModel habit, ColorScheme scheme) {
    final titleColor = habit.titleTextColorArgb != null ? Color(habit.titleTextColorArgb!) : scheme.onSurface;
    final descColor = habit.descriptionTextColorArgb != null
        ? Color(habit.descriptionTextColorArgb!)
        : scheme.onSurface.withOpacity(0.85);
    final scheduled = _scheduledAtLocal;
    final timeText =
        '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.primary,
            child: Row(
              children: [
                Text(timeText, style: TextStyle(color: scheme.onPrimary, fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(habit.title, style: TextStyle(color: scheme.onPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (habit.description.trim().isNotEmpty)
                    Text(habit.description, textAlign: TextAlign.center, style: TextStyle(color: descColor, fontSize: 18)),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _markDone,
                          child: const Text('Hecho'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _snooze,
                          child: const Text('Posponer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(habit.title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildFocusSlider(HabitModel habit, ColorScheme scheme) {
    final titleColor = habit.titleTextColorArgb != null ? Color(habit.titleTextColorArgb!) : scheme.onSurface;
    final descColor = habit.descriptionTextColorArgb != null
        ? Color(habit.descriptionTextColorArgb!)
        : scheme.onSurface.withOpacity(0.85);
    final scheduled = _scheduledAtLocal;
    final timeText =
        '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';

    double slider = 0;
    return StatefulBuilder(
      builder: (context, setInner) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(timeText, style: TextStyle(color: scheme.primary, fontSize: 48, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                Text(habit.title, style: TextStyle(color: titleColor, fontSize: 22, fontWeight: FontWeight.w800)),
                if (habit.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(habit.description, textAlign: TextAlign.center, style: TextStyle(color: descColor)),
                ],
                const SizedBox(height: 22),
                Text('Desliza para marcar como hecho', style: TextStyle(color: scheme.onSurface)),
                Slider(
                  value: slider,
                  onChanged: (v) => setInner(() => slider = v),
                  onChangeEnd: (v) async {
                    if (v >= 0.95) {
                      await _markDone();
                    } else {
                      setInner(() => slider = 0);
                    }
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _snooze,
                  child: const Text('Posponer'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final habit = _habit;
    if (habit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hábito')),
        body: Center(child: Text('Hábito no encontrado', style: TextStyle(color: scheme.onSurface))),
      );
    }

    final layout = habit.alertLayoutId;
    final body = layout == 'compactTop'
        ? _buildCompactTop(habit, scheme)
        : layout == 'focusSlider'
            ? _buildFocusSlider(habit, scheme)
            : _buildClassic(habit, scheme);

    return Scaffold(
      backgroundColor: scheme.background,
      body: body,
    );
  }
}

