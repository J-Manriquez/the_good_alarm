import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'habit_edit_screen.dart';
import 'models/habit_models.dart';
import 'services/habit_repository.dart';
import 'services/habit_scheduler.dart';
import 'settings_screen.dart';

class HabitsScreen extends StatefulWidget {
  final bool embedInShell;
  final bool manageCloudSync;

  const HabitsScreen({
    super.key,
    this.embedInShell = false,
    this.manageCloudSync = true,
  });

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  final HabitRepository _repo = HabitRepository();
  final HabitScheduler _scheduler = HabitScheduler();

  bool _loading = true;
  bool _cloudSyncEnabled = false;
  User? _user;
  List<HabitModel> _habits = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repo.stopAllCloudSync();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;

    _user = FirebaseAuth.instance.currentUser;
    final userId = _user?.uid;
    if (userId != null) {
      if (widget.manageCloudSync && _cloudSyncEnabled) {
        await _repo.reconcile(userId: userId);
        await _repo.startCloudSync(
          userId: userId,
          onHabitsBatchApplied: (_) async {
            if (!mounted) return;
            await _reloadLocal();
            await _scheduleAll();
          },
          onCompletionsApplied: () async {
            if (!mounted) return;
          },
        );
      }
    }

    await _reloadLocal();
    await _scheduleAll();

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _reloadLocal() async {
    final habits = await _repo.loadLocalHabits();
    if (!mounted) return;
    setState(() {
      _habits = habits;
    });
  }

  Future<void> _scheduleAll() async {
    final now = DateTime.now();
    final userId = _user?.uid;
    for (final habit in _habits) {
      if (!habit.isActive || habit.deletedAt != null) continue;

      final next = _scheduler.nextOccurrenceLocal(habit, now);
      if (next == null) {
        final prev = habit.nextScheduledAtLocal;
        if (prev != null) {
          final prevKey = _scheduler.occurrenceKeyFor(habit.id, prev);
          try {
            await _scheduler.cancelOccurrence(occurrenceKey: prevKey);
          } catch (_) {}
        }
        if (habit.nextScheduledAtLocal != null) {
          await _repo.upsertHabit(
            habit: habit.copyWith(nextScheduledAtLocal: null),
            cloudSyncEnabled: _cloudSyncEnabled,
            userId: userId,
          );
        }
        continue;
      }

      final needsUpdate = habit.nextScheduledAtLocal == null || habit.nextScheduledAtLocal != next;
      if (needsUpdate) {
        await _repo.upsertHabit(
          habit: habit.copyWith(nextScheduledAtLocal: next),
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: userId,
        );
      }
      try {
        await _scheduler.scheduleOccurrence(habit: habit, whenLocal: next);
      } catch (_) {}
    }
    await _reloadLocal();
  }

  String _formatTime(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime local) =>
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year.toString().padLeft(4, '0')}';

  Future<void> _openEditor({HabitModel? habit}) async {
    final saved = await Navigator.of(context).push<HabitModel>(
      MaterialPageRoute(
        builder: (_) => HabitEditScreen(habit: habit),
      ),
    );
    if (saved == null) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    await _repo.upsertHabit(habit: saved, cloudSyncEnabled: _cloudSyncEnabled, userId: userId);
    await _reloadLocal();
    await _scheduleAll();
  }

  Future<void> _deleteHabit(HabitModel habit) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final prev = habit.nextScheduledAtLocal;
    if (prev != null) {
      final prevKey = _scheduler.occurrenceKeyFor(habit.id, prev);
      try {
        await _scheduler.cancelOccurrence(occurrenceKey: prevKey);
      } catch (_) {}
    }
    await _repo.deleteHabit(habitId: habit.id, cloudSyncEnabled: _cloudSyncEnabled, userId: userId);
    await _reloadLocal();
  }

  Future<void> _toggleHabitActive(HabitModel habit, bool active) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final prev = habit.nextScheduledAtLocal;
    if (!active && prev != null) {
      final prevKey = _scheduler.occurrenceKeyFor(habit.id, prev);
      try {
        await _scheduler.cancelOccurrence(occurrenceKey: prevKey);
      } catch (_) {}
    }

    final updated = habit.copyWith(isActive: active);
    final now = DateTime.now();
    final next = active ? _scheduler.nextOccurrenceLocal(updated, now) : null;
    final updatedWithNext = updated.copyWith(nextScheduledAtLocal: next);

    await _repo.upsertHabit(habit: updatedWithNext, cloudSyncEnabled: _cloudSyncEnabled, userId: userId);
    if (active && next != null) {
      try {
        await _scheduler.scheduleOccurrence(habit: updatedWithNext, whenLocal: next);
      } catch (_) {}
    }
    await _reloadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _habits.isEmpty
            ? Center(
                child: Text(
                  'No hay hábitos todavía',
                  style: TextStyle(color: scheme.onSurface),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _habits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final habit = _habits[i];
                  final cardColor = habit.cardBackgroundColorArgb != null
                      ? Color(habit.cardBackgroundColorArgb!)
                      : scheme.surface;
                  final titleColor = habit.titleTextColorArgb != null
                      ? Color(habit.titleTextColorArgb!)
                      : scheme.onSurface;
                  final descColor = habit.descriptionTextColorArgb != null
                      ? Color(habit.descriptionTextColorArgb!)
                      : scheme.onSurface.withOpacity(0.8);
                  final timeColor = habit.timeTextColorArgb != null
                      ? Color(habit.timeTextColorArgb!)
                      : scheme.primary;
                  final next = habit.nextScheduledAtLocal;

                  return Card(
                    color: cardColor,
                    child: InkWell(
                      onTap: () => _openEditor(habit: habit),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    habit.title,
                                    style: TextStyle(
                                      color: titleColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: habit.isActive && habit.deletedAt == null,
                                  onChanged: habit.deletedAt != null
                                      ? null
                                      : (v) => _toggleHabitActive(habit, v),
                                  activeColor: scheme.primary,
                                ),
                                IconButton(
                                  onPressed: habit.deletedAt != null
                                      ? null
                                      : () => _deleteHabit(habit),
                                  icon: Icon(Icons.delete, color: scheme.error),
                                ),
                              ],
                            ),
                            if (habit.description.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                habit.description,
                                style: TextStyle(color: descColor),
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (next != null)
                              Text(
                                'Próximo: ${_formatDate(next)} ${_formatTime(next)}',
                                style: TextStyle(
                                  color: timeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              Text(
                                'Sin próxima programación',
                                style: TextStyle(color: timeColor),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

    if (widget.embedInShell) {
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () => _openEditor(),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hábitos'),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
